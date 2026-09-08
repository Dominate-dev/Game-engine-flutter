import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Bell B-3 — dialogs through the shared round dialog queue.
//
// They share the queue and its lifecycle rules with WDYK and Auction.
// ChangeTurn is the race result: "fastest" only when Bell was racing before
// the winner was named; otherwise it is the ordinary WDYK-style turn dialog.
// CorrectAnswer and PlayerAnswered are unconditional, matching the reference
// (T30 does not branch on CorrectAnswer.playerId). Penalty has no strike row.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async => true;

  @override
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) =>
      () {};

  @override
  void reattachEventHandlers() {}
}

class _FakeHubBindings extends PlayGameHubBindings {
  _FakeHubBindings(super.signalR);

  final _events = StreamController<GameHubEvent>.broadcast();

  @override
  Stream<GameHubEvent> get stream => _events.stream;

  @override
  void bindAll() {}

  @override
  void bindEvents(Iterable<String> eventNames) {}

  @override
  void dispose() {
    _events.close();
  }
}

/// Silences playback the same way the WDYK intro test does.
class _FakeAudioService extends AudioService {
  final musicStarted = <String>[];

  List<String> get introMusic =>
      musicStarted.where((a) => a == AppSounds.musicRunning).toList();

  @override
  Future<void> start(
    String asset, {
    AudioSourceType type = AudioSourceType.sfx,
    String? package,
    bool? loop,
    double? volume,
  }) async {}

  @override
  Future<void> playMusic(
    String asset, {
    String? package,
    bool loop = true,
    double? volume,
  }) async {
    musicStarted.add(asset);
  }

  @override
  Future<void> playSfx(
    String asset, {
    String? package,
    double? volume,
  }) async {}
}

/// Keeps each dialog "open" until the test dismisses it, so stacking shows up.
class _DialogRecorder {
  final shown = <Widget>[];
  final _open = <Completer<void>>[];

  Future<void> show({required Widget child, bool barrierDismissible = true}) {
    shown.add(child);
    final completer = Completer<void>();
    _open.add(completer);
    return completer.future;
  }

  int get openCount => _open.where((c) => !c.isCompleted).length;

  T last<T>() => shown.last as T;

  void dismissAll() {
    for (final completer in _open) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }
}

Map<String, dynamic> _bellGame({String currentTurn = ''}) => {
      'id': 'g1',
      'status': 3,
      'type': 3,
      'groupId': 'grp',
      'currentTurn': currentTurn,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
      'currentQuestion': {
        'id': 1,
        'text': 'q',
        'textEn': 'q',
        'type': 1,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
    };

void main() {
  late ProviderContainer container;
  late _DialogRecorder recorder;
  late _FakeAudioService audio;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  final strings = PlayGameStrings.forLanguage(AppLanguage.english);

  Future<void> enterRound(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    final signalR = _FakeSignalRService();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider
            .overrideWithValue(_FakeHubBindings(signalR)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(sub.close);
    recorder = _DialogRecorder();
    audio = _FakeAudioService();

    await tester.pumpWidget(const SizedBox());
    notifier().applySessionEvent(PlayGameHubEvents.gameStarted, _bellGame());
    await tester.pump();
  }

  /// TimeStarted with no turn yet — arms the Bell (B-1).
  Future<void> race(WidgetTester tester) async {
    notifier().applySharedRoundEvent(PlayGameHubEvents.timeStarted, null);
    await tester.pump();
  }

  /// Drives ChangeTurn through both pipelines, dialog first — the same
  /// order production guarantees (the dialog listener runs synchronously
  /// ahead of the reducer's stream-delivered update). Needed whenever a test
  /// checks a *second* event's dialog against the *first* event's resulting
  /// state, since a single call to the dialog method alone never updates
  /// game.currentTurn.
  Future<void> changeTurn(WidgetTester tester, String playerId) async {
    final data = {'arg0': playerId, 'arg1': 'g1'};
    notifier().onChangeTurn(data, recorder.show);
    notifier().applySharedRoundEvent(PlayGameHubEvents.changeTurn, data);
    await tester.pump();
  }

  group('Bell round intro', () {
    testWidgets('is queued for 2000ms and plays music once it closes',
        (tester) async {
      await enterRound(tester);

      // Fire-and-forget, matching how GameControllerScreen actually calls
      // this (unawaited) — the recorder's dialog Future only resolves once
      // dismissAll() runs, same as every other queued-dialog test here.
      unawaited(notifier().showRoundIntro(recorder.show, audio));
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().timer, 2000);

      recorder.dismissAll();
      await tester.pump();

      expect(audio.introMusic, hasLength(1),
          reason: 'showRoundIntro ran to completion — the existing shared '
              'round-entry mechanism, unmodified for Bell');
    });
  });

  group('TimeStarted', () {
    testWidgets(
        'enqueues the start-time overlay for 2000ms, through the shared '
        'queue', (tester) async {
      await enterRound(tester);

      notifier().onTimeStarted(null, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      final dialog = recorder.last<RoundLottieDialog>();
      expect(dialog.timer, 2000,
          reason: 'the same duration WDYK/Auction already use');
      expect(dialog.text, strings.startTimer);
      expect(dialog.sound, AppSounds.startTime,
          reason: 'the existing start_time_t30 resource');
      expect((dialog.lottie as AppLottieView).asset, AppAssets.lottieTimer,
          reason: 'the existing timer Lottie WDYK/Auction already use');
    });

    testWidgets(
        'queues behind an overlay already up, and appears immediately once '
        'it closes — no inter-dialog delay', (tester) async {
      await enterRound(tester);
      await race(tester);
      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);

      notifier().onTimeStarted(null, recorder.show);
      await tester.pump();

      expect(recorder.openCount, 1, reason: 'no stacking');
      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(2),
          reason: 'shown as soon as the previous dialog closes');
      expect(recorder.last<RoundLottieDialog>().text, strings.startTimer);
    });
  });

  group('ChangeTurn is the race result', () {
    testWidgets('names me while racing → the "you\'re the fastest" dialog',
        (tester) async {
      await enterRound(tester);
      await race(tester);

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().text, strings.youAreFastest);
      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });

    testWidgets('names the opponent while racing → the "he\'s the fastest" '
        'dialog', (tester) async {
      await enterRound(tester);
      await race(tester);

      notifier().onChangeTurn(
        {'arg0': _opponentId, 'arg1': 'g1'},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().text, strings.opponentIsFastest);
    });

    testWidgets('names me without a race → the normal turn dialog',
        (tester) async {
      await enterRound(tester);
      // No TimeStarted — bellPhase stays idle, never racing.

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().text,
          strings.turnOverlayText(isMine: true, playerName: 'me'),
          reason: 'the existing WDYK-style turn dialog — now worded as a '
              'turn rather than a bare name');
      expect(recorder.last<RoundLottieDialog>().text,
          isNot(strings.youAreFastest));
    });

    testWidgets('names the opponent without a race → the normal turn dialog',
        (tester) async {
      await enterRound(tester);

      notifier().onChangeTurn(
        {'arg0': _opponentId, 'arg1': 'g1'},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().text,
          strings.turnOverlayText(isMine: false, playerName: 'them'));
      expect(recorder.last<RoundLottieDialog>().text,
          isNot(strings.opponentIsFastest));
    });

    testWidgets('an id matching neither player shows nothing', (tester) async {
      await enterRound(tester);
      await race(tester);

      notifier().onChangeTurn({'arg0': '999', 'arg1': 'g1'}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('an explicitly empty playerId shows nothing — a silent reset',
        (tester) async {
      await enterRound(tester);
      await race(tester);

      notifier().onChangeTurn({'arg0': '', 'arg1': 'g1'}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });
  });

  group('B-4 — repeated NextQuestion must not end the race early', () {
    // Real-device evidence: the server sends NextQuestion several times for
    // the same question, each carrying progressively more text, while Bell
    // is still actively racing — well before any ChangeTurn/Penalty ends it.
    testWidgets(
        'still shows "fastest" after several NextQuestion repeats mid-race',
        (tester) async {
      await enterRound(tester);
      await race(tester);
      expect(current().bellArmed, isTrue);

      for (var i = 0; i < 3; i++) {
        notifier().applySharedRoundEvent(
          PlayGameHubEvents.nextQuestion,
          {
            'id': 1,
            'text': 'q' * (i + 1),
            'textEn': 'q' * (i + 1),
            'type': 1,
            'answers': [
              {'id': 10, 'text': 'a1', 'textEn': 'a1'},
            ],
          },
        );
        await tester.pump();
      }
      expect(current().bellArmed, isTrue,
          reason: 'still racing — NextQuestion repeats must not disarm it');

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().text, strings.youAreFastest,
          reason: 'the race was never actually interrupted');
    });

    testWidgets('the Bell button stays armed through repeated NextQuestion',
        (tester) async {
      await enterRound(tester);
      await race(tester);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.nextQuestion,
        {
          'id': 1,
          'text': 'longer question text',
          'textEn': 'longer question text',
          'type': 1,
          'answers': [
            {'id': 10, 'text': 'a1', 'textEn': 'a1'},
          ],
        },
      );
      await tester.pump();

      expect(notifier().bellPhase, BellPhase.racing);
      expect(notifier().isBellVisible, isTrue);
      expect(notifier().canRingBell, isTrue);
    });
  });

  group('B-5 — ChangeTurn after an answer is a normal turn, not fastest', () {
    // The full lifecycle: racing → fastest → an answer result → a second,
    // unrelated ChangeTurn naming the OTHER player. bellPhase is read live
    // off game.currentTurn + bellArmed on every call — there is no cached
    // "who was fastest" anywhere, so this proves the second dialog reflects
    // only the new event, not the first one. Each step's dialog is dismissed
    // before the next is enqueued — the shared queue only starts the next
    // dialog once the current one closes.
    testWidgets(
        'after my answer, ChangeTurn(opponent) shows the opponent turn '
        'dialog, not "he\'s fastest" again', (tester) async {
      await enterRound(tester);
      await race(tester);
      await changeTurn(tester, _localId);
      expect(recorder.last<RoundLottieDialog>().text, strings.youAreFastest);
      recorder.dismissAll();
      await tester.pump();

      // I answer; the server resolves it. Neither event touches currentTurn.
      notifier().onCorrectAnswer(null, recorder.show);
      await tester.pump();
      recorder.dismissAll();
      await tester.pump();

      // The next ChangeTurn hands the turn to the opponent directly — no
      // fresh TimeStarted/race in between.
      await changeTurn(tester, _opponentId);

      expect(recorder.last<RoundLottieDialog>().text,
          strings.turnOverlayText(isMine: false, playerName: 'them'),
          reason: 'a normal turn dialog, using the new event\'s playerId');
      expect(recorder.last<RoundLottieDialog>().text,
          isNot(strings.opponentIsFastest));
    });

    testWidgets(
        'after the opponent\'s answer, ChangeTurn(me) shows my turn dialog, '
        'not "you\'re fastest" again', (tester) async {
      await enterRound(tester);
      await race(tester);
      await changeTurn(tester, _opponentId);
      expect(
        recorder.last<RoundLottieDialog>().text,
        strings.opponentIsFastest,
      );
      recorder.dismissAll();
      await tester.pump();

      notifier().onPenalty({'playerId': _opponentId, 'type': 2}, recorder.show);
      await tester.pump();
      recorder.dismissAll();
      await tester.pump();

      await changeTurn(tester, _localId);

      expect(recorder.last<RoundLottieDialog>().text,
          strings.turnOverlayText(isMine: true, playerName: 'me'),
          reason: 'a normal turn dialog, using the new event\'s playerId');
      expect(recorder.last<RoundLottieDialog>().text,
          isNot(strings.youAreFastest));
    });

    testWidgets('a third ChangeTurn back to the original racer is still '
        'a normal turn, not fastest', (tester) async {
      // Guards against any state that only survives one hop.
      await enterRound(tester);
      await race(tester);
      await changeTurn(tester, _localId);
      recorder.dismissAll();
      await tester.pump();
      notifier().onCorrectAnswer(null, recorder.show);
      await tester.pump();
      recorder.dismissAll();
      await tester.pump();
      await changeTurn(tester, _opponentId);
      recorder.dismissAll();
      await tester.pump();
      notifier().onPenalty({'playerId': _opponentId, 'type': 2}, recorder.show);
      await tester.pump();
      recorder.dismissAll();
      await tester.pump();

      await changeTurn(tester, _localId);

      expect(recorder.last<RoundLottieDialog>().text,
          strings.turnOverlayText(isMine: true, playerName: 'me'));
      expect(recorder.last<RoundLottieDialog>().text,
          isNot(strings.youAreFastest));
    });
  });

  group('CorrectAnswer', () {
    testWidgets('is shown unconditionally — no ownership check', (tester) async {
      await enterRound(tester);
      // Not racing, no turn assigned, no answering-player state at all —
      // still shown, per the reference's explicit "does not branch" rule.
      notifier().onCorrectAnswer(null, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().text, strings.correctAnswer);
      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });
  });

  group('Penalty', () {
    testWidgets('type 2 (wrong) shows the wrong-answer overlay, not a strike',
        (tester) async {
      await enterRound(tester);

      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().text, strings.wrongAnswer);
      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });

    testWidgets('type 1 (timeout) shows the timeout overlay', (tester) async {
      await enterRound(tester);

      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().text, strings.timeout);
      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });

    testWidgets(
        'type 1 (timeout) naming the opponent still shows it to me — both '
        'players see it (B-6)', (tester) async {
      await enterRound(tester);

      notifier().onPenalty({'playerId': _opponentId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().text, strings.timeout);
      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });

    testWidgets(
        'type 2 (wrong) naming the opponent still shows it to me — both '
        'players see it (B-5)', (tester) async {
      await enterRound(tester);

      notifier().onPenalty({'playerId': _opponentId, 'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().text, strings.wrongAnswer);
      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });
  });

  group('PlayerAnswered', () {
    testWidgets('reveals the answer text', (tester) async {
      await enterRound(tester);

      notifier().onPlayerAnswered(
        {'answerText': 'blue', 'answerTextEn': 'blue'},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.last<Widget>(), isA<PlayerAnsweredDialog>());
      expect(recorder.last<PlayerAnsweredDialog>().answer, 'blue');
      expect(recorder.last<PlayerAnsweredDialog>().timer, 1500);
    });
  });

  group('queue behaviour', () {
    testWidgets('multiple Bell dialogs are FIFO and never stack', (tester) async {
      await enterRound(tester);
      await race(tester);

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      notifier().onCorrectAnswer(null, recorder.show);
      notifier().onPlayerAnswered({'answerText': 'x'}, recorder.show);
      await tester.pump();

      expect(recorder.openCount, 1, reason: 'no stacking');
      expect(recorder.shown, hasLength(1));

      for (var i = 0; i < 2; i++) {
        recorder.dismissAll();
        await tester.pump();
      }

      expect(recorder.shown, hasLength(3));
      expect(
        recorder.shown[0],
        isA<RoundLottieDialog>()
            .having((d) => d.text, 'text', strings.youAreFastest),
        reason: 'ChangeTurn first',
      );
      expect(
        recorder.shown[1],
        isA<RoundLottieDialog>()
            .having((d) => d.text, 'text', strings.correctAnswer),
        reason: 'CorrectAnswer second',
      );
      expect(recorder.shown[2], isA<PlayerAnsweredDialog>(),
          reason: 'PlayerAnswered third');
    });

    testWidgets('the next dialog appears immediately after the previous one '
        'closes — no extra inter-dialog delay', (tester) async {
      await enterRound(tester);
      await race(tester);
      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      notifier().onCorrectAnswer(null, recorder.show);
      await tester.pump();
      expect(recorder.shown, hasLength(1));

      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(2),
          reason: 'shown on the very next pump — no delay was awaited');
    });
  });

  group('unrelated events', () {
    testWidgets('do not enqueue a Bell dialog', (tester) async {
      await enterRound(tester);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.questionOver,
        {'arg0': 'g1'},
      );
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });
  });

  group('dialog handling does not mutate state', () {
    testWidgets('the ChangeTurn dialog handler alone touches no state',
        (tester) async {
      await enterRound(tester);
      await race(tester);
      expect(current().bellArmed, isTrue);

      // Calling the dialog method directly, without also driving it through
      // applySharedRoundEvent, proves the handler itself is presentation
      // only — B-1's reducer is what actually owns this transition.
      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      await tester.pump();

      expect(current().game?.currentTurn ?? '', isEmpty,
          reason: 'unchanged — only the reducer path sets this');
      expect(current().bellArmed, isTrue,
          reason: 'unchanged — the dialog handler never writes state');
    });
  });
}
