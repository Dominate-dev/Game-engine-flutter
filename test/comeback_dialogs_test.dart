import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Comeback C-4 — dialogs through the shared round dialog queue.
//
// Unlike Bell (unconditional CorrectAnswer to both), Comeback shows two
// different CorrectAnswer overlays: mine when I answered, the opponent's
// name when they did. Wrong (Penalty type 2) is shown only to whoever it
// happened to; timeout (type 1) is shown to both, matching the reference.

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

Map<String, dynamic> _comebackGame() => {
      'id': 'g1',
      'status': 3,
      'type': 4,
      'groupId': 'grp',
      'currentTurn': '',
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
        {
          'id': _opponentId,
          'playerName': 'them',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
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

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

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

    await tester.pumpWidget(const SizedBox());
    notifier()
        .applySessionEvent(PlayGameHubEvents.gameStarted, _comebackGame());
    await tester.pump();
  }

  // CorrectAnswer is (text, textEn, playerId, gameId) per the established
  // W-CONTRACT shape every round's CorrectAnswer already shares — arg2 is
  // the player.
  Map<String, dynamic> correctAnswerArgs(String playerId) => {
        'arg0': 'answer',
        'arg1': 'answer en',
        'arg2': playerId,
      };

  group('TimeStarted', () {
    testWidgets(
        'enqueues the Start Timer overlay for 2000ms, through the shared '
        'queue — native GameControllerFragment.startTimer()', (tester) async {
      await enterRound(tester);

      notifier().onTimeStarted(null, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      final dialog = recorder.last<RoundLottieDialog>();
      expect(dialog.timer, 2000);
      expect(dialog.text, strings.startTimer);
      expect(dialog.sound, AppSounds.startTime);
      expect((dialog.lottie as AppLottieView).asset, AppAssets.lottieTimer);
    });
  });

  group('CorrectAnswer', () {
    testWidgets('mine → my own correct-answer overlay, 1500ms',
        (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      final dialog = recorder.last<RoundLottieDialog>();
      expect(dialog.text, strings.correctAnswer);
      expect((dialog.lottie as AppLottieView).asset,
          AppAssets.lottieCorrectAnswer);
      expect(dialog.sound, AppSounds.rightAnswer);
      expect(dialog.timer, 1500);
    });

    testWidgets("the opponent's → the answer bar naming them, 2000ms",
        (tester) async {
      await enterRound(tester);

      notifier()
          .onCorrectAnswer(correctAnswerArgs(_opponentId), recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      final dialog = recorder.last<PlayerAnsweredDialog>();
      expect(dialog.answer, 'answer en');
      expect(dialog.playerName, 'them',
          reason: 'the roster name, shown in yellow under the answer');
      expect(dialog.timer, 2000);
    });

    testWidgets('a payload with no answer text shows nothing', (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(
        {'arg0': '', 'arg1': '', 'arg2': _localId},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.shown, isEmpty,
          reason: 'the bar carries the text itself — there is nothing to show');
    });

    testWidgets('an id naming neither player shows nothing', (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs('999'), recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('a null payload shows nothing', (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(null, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });
  });

  group('Penalty', () {
    testWidgets('type 2 (wrong) for me shows the wrong-answer dialog, 1500ms',
        (tester) async {
      await enterRound(tester);

      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().text, strings.wrongAnswer);
      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });

    testWidgets('type 2 (wrong) for the opponent shows nothing to me',
        (tester) async {
      await enterRound(tester);

      notifier()
          .onPenalty({'playerId': _opponentId, 'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty,
          reason: 'the reference is explicit: only the player it happened '
              'to sees the wrong-answer overlay');
    });

    testWidgets('type 1 (timeout) shows the timeout dialog, 1500ms',
        (tester) async {
      await enterRound(tester);

      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().text, strings.timeout);
      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });

    testWidgets(
        'type 1 (timeout) naming the opponent still shows it to me — both '
        'players see it', (tester) async {
      await enterRound(tester);

      notifier()
          .onPenalty({'playerId': _opponentId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().text, strings.timeout);
    });
  });

  group('queue behaviour', () {
    testWidgets('multiple Comeback dialogs are FIFO and never stack',
        (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      notifier().onPenalty({'playerId': _opponentId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.openCount, 1, reason: 'no stacking');
      expect(recorder.shown, hasLength(1));

      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(2));
      expect(
        recorder.shown[0],
        isA<RoundLottieDialog>()
            .having((d) => d.text, 'text', strings.correctAnswer),
        reason: 'CorrectAnswer first',
      );
      expect(
        recorder.shown[1],
        isA<RoundLottieDialog>().having((d) => d.text, 'text', strings.timeout),
        reason: 'Penalty (timeout) second',
      );
    });

    testWidgets('the next dialog appears immediately after the previous one '
        'closes — no extra inter-dialog delay', (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();
      expect(recorder.shown, hasLength(1));

      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(2),
          reason: 'shown on the very next pump — no delay was awaited');
    });
  });

  group('dialog handling does not mutate state', () {
    testWidgets('CorrectAnswer alone touches no state', (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      await tester.pump();

      expect(
        container.read(gameControllerProvider).me?.makeupTryCount,
        0,
        reason: 'unchanged — dialogs are presentation only',
      );
    });
  });
}
