import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Auction A-4 — overlays.
//
// They share the round dialog queue and its lifecycle rules with WDYK, but not
// its business rules: ownership comes from the auction contract.

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

Map<String, dynamic> _game({required int type}) => {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      'currentTurn': _localId,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
      'currentQuestion': {
        'id': 1682,
        'text': 'q',
        'textEn': 'q',
        'type': 1,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
      if (type == 2)
        'auctionGameMetadata': {
          'phase': 2,
          'currentScore': 0,
          'currentBid': 4,
          'answerTimeout': 8,
        },
    };

void main() {
  late ProviderContainer container;
  late _DialogRecorder recorder;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  final strings = PlayGameStrings.forLanguage(AppLanguage.english);

  Future<void> enterRound(WidgetTester tester, {int type = 2}) async {
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
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _game(type: type),
    );
    await tester.pump();
  }

  Future<void> answerPhase(WidgetTester tester, String playerId) async {
    notifier().applyAuctionEvent(
      PlayGameHubEvents.auctionAnswerPhaseStarted,
      {'playerId': playerId, 'bidValue': 4},
    );
    await tester.pump();
  }

  Future<void> setLifecycle(
    WidgetTester tester,
    AppLifecycleState state,
  ) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );
    await tester.pump();
  }

  group('event to dialog', () {
    testWidgets('ChangeTurn shows the named turn overlay', (tester) async {
      await enterRound(tester);

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().text, strings.turnOverlayText(isMine: true, playerName: 'me'));
    });

    testWidgets('the opponent turn is named too', (tester) async {
      await enterRound(tester);

      notifier().onChangeTurn(
        {'arg0': _opponentId, 'arg1': 'g1'},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().text, strings.turnOverlayText(isMine: false, playerName: 'them'));
    });

    testWidgets('an unseated turn id shows nothing', (tester) async {
      await enterRound(tester);

      notifier().onChangeTurn({'arg0': '999', 'arg1': 'g1'}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('Penalty(2) shows nothing — the answer flow carries on',
        (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);

      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty,
          reason: 'AuctionAnswerPhaseScoreUpdate reports the wrong count');
    });

    testWidgets('Penalty(2) shows nothing on either device', (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _opponentId);

      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      notifier().onPenalty({'playerId': _opponentId, 'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('Penalty(2) leaves the answering flow and timer alone',
        (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.timeStarted,
        HubEventPayload.mapFromArgs(['', 'g1']),
      );
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([9, 'g1']),
      );
      await tester.pump();

      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 2},
      );
      await tester.pump();

      final state = container.read(gameControllerProvider);
      expect(recorder.shown, isEmpty, reason: 'no dialog');
      expect(state.game?.isTimerStarted, isTrue, reason: 'timer still running');
      expect(state.auctionPhase, AuctionPhase.answering,
          reason: 'still answering');
      expect(notifier().canSubmitAuctionAnswer, isTrue,
          reason: 'the player can keep answering');
      expect(state.wrongScore, isNull,
          reason: 'only AuctionAnswerPhaseScoreUpdate reports the count');
    });

    testWidgets('Penalty(1) shows the timeout overlay', (tester) async {
      await enterRound(tester);

      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().text, strings.timeout);
    });

    testWidgets('CorrectAnswer shows no overlay — the score update reports it',
        (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);

      notifier().onCorrectAnswer(null, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty,
          reason: 'like a wrong answer, AuctionAnswerPhaseScoreUpdate '
              'reports this, not a dialog');
    });

    testWidgets('TimeStarted shows the time-start overlay', (tester) async {
      await enterRound(tester);

      notifier().onTimeStarted(
        HubEventPayload.mapFromArgs(['', 'g1']),
        recorder.show,
      );
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().text, strings.startTimer);
      expect(recorder.last<RoundLottieDialog>().timer, 2000,
          reason: 'the same overlay the app already uses');
    });

    testWidgets('TimeStarted is shown to both players', (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _opponentId);

      notifier().onTimeStarted(null, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1),
          reason: 'the countdown starts for the round, not for a player');
    });

    testWidgets('TimeStarted queues behind an overlay already up',
        (tester) async {
      await enterRound(tester);

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      notifier().onTimeStarted(null, recorder.show);
      await tester.pump();

      expect(recorder.openCount, 1, reason: 'no stacking');
      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(2),
          reason: 'shown as soon as the turn overlay closes — not delayed by '
              "its post-close grace period");
      expect(recorder.last<RoundLottieDialog>().text, strings.startTimer);
    });

    testWidgets('TimeStarted is suppressed while the app is away',
        (tester) async {
      await enterRound(tester);
      await setLifecycle(tester, AppLifecycleState.paused);

      notifier().onTimeStarted(null, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('the overlay does not touch the countdown', (tester) async {
      await enterRound(tester);

      notifier().onTimeStarted(null, recorder.show);
      await tester.pump();

      expect(container.read(gameControllerProvider).game?.currentTimerValue, 0,
          reason: 'TimerUpdatedSeconds drives the countdown, not this dialog');
    });

    testWidgets('PlayerAnswered reveals the text', (tester) async {
      await enterRound(tester);

      notifier().onPlayerAnswered(
        {'answerText': 'blue', 'answerTextEn': 'blue'},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.last<Widget>(), isA<PlayerAnsweredDialog>());
      expect(recorder.last<PlayerAnsweredDialog>().answer, 'blue');
    });
  });

  group('start increasing', () {
    /// The overlay is driven from the reduced bidding state, so the tests go
    /// through the same path the screen does.
    void enterBidding() {
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionBiddingPhaseStarted,
        {'arg0': 'g1'},
      );
    }

    testWidgets('it is shown when I may raise on my turn', (tester) async {
      await enterRound(tester);
      enterBidding();
      await tester.pump();

      notifier().showAuctionStartIncreasing(recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().text, strings.startIncreasing);
    });

    testWidgets('it uses the legacy 2000ms duration', (tester) async {
      await enterRound(tester);
      enterBidding();
      await tester.pump();

      notifier().showAuctionStartIncreasing(recorder.show);
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().timer, 2000);
    });

    testWidgets('it is not shown when it is not my turn', (tester) async {
      await enterRound(tester);
      enterBidding();
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.changeTurn,
        {'arg0': _opponentId, 'arg1': 'g1'},
      );
      await tester.pump();

      notifier().showAuctionStartIncreasing(recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('it is not shown once I am the standing bidder',
        (tester) async {
      await enterRound(tester);
      enterBidding();
      notifier().applyAuctionEvent(
        PlayGameHubEvents.playerBidded,
        {'playerId': _localId, 'bidValue': 3},
      );
      await tester.pump();

      notifier().showAuctionStartIncreasing(recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty,
          reason: 'isBiding is closed until the opponent raises');
    });

    testWidgets('it returns once the opponent raises', (tester) async {
      await enterRound(tester);
      enterBidding();
      notifier().applyAuctionEvent(
        PlayGameHubEvents.playerBidded,
        {'playerId': _localId, 'bidValue': 3},
      );
      notifier().applyAuctionEvent(
        PlayGameHubEvents.playerBidded,
        {'playerId': _opponentId, 'bidValue': 5},
      );
      await tester.pump();

      notifier().showAuctionStartIncreasing(recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
    });

    testWidgets('it queues behind an overlay already on screen',
        (tester) async {
      await enterRound(tester);
      enterBidding();
      await tester.pump();

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      notifier().showAuctionStartIncreasing(recorder.show);
      await tester.pump();

      expect(recorder.openCount, 1, reason: 'no stacking');
      expect(recorder.shown, hasLength(1));

      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(2),
          reason: 'shown as soon as the turn overlay closes — not delayed by '
              "its post-close grace period");
      expect(recorder.last<RoundLottieDialog>().text, strings.startIncreasing);
    });

    testWidgets('it is suppressed while the app is away', (tester) async {
      await enterRound(tester);
      enterBidding();
      await tester.pump();
      await setLifecycle(tester, AppLifecycleState.paused);

      notifier().showAuctionStartIncreasing(recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });
  });

  group('PlayerLostAuctionRound wording follows the timer', () {
    Future<void> withTimer(WidgetTester tester, double seconds) async {
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([seconds, 'g1']),
      );
      await tester.pump();
    }

    testWidgets('time still on the clock reads as round finished',
        (tester) async {
      await enterRound(tester);
      await withTimer(tester, 5);

      notifier().onAuctionRoundLost(
        {'arg0': _localId, 'arg1': 'g1'},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().text, strings.finishRoundTitle);
    });

    testWidgets('a clock at zero reads as timed out', (tester) async {
      await enterRound(tester);
      await withTimer(tester, 0);

      notifier().onAuctionRoundLost(
        {'arg0': _localId, 'arg1': 'g1'},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().text, strings.timeout);
    });

    testWidgets('it keeps the timeout overlay presentation', (tester) async {
      await enterRound(tester);
      await withTimer(tester, 5);

      notifier().onAuctionRoundLost(
        {'arg0': _localId, 'arg1': 'g1'},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });

    testWidgets('it is shown only to the player it names', (tester) async {
      await enterRound(tester);
      await withTimer(tester, 5);

      notifier().onAuctionRoundLost(
        {'arg0': _opponentId, 'arg1': 'g1'},
        recorder.show,
      );
      notifier().onAuctionRoundLost({'arg0': '999'}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });
  });

  group('PlayerWonAuctionRound (R-12)', () {
    // Same [playerId, gameId] payload shape as PlayerLostAuctionRound
    // (confirmed by _applyAuctionOutcome, which reduces both from the same
    // positional playerId) and the same single-sided treatment. Before this
    // fix there was no handler for this event at all — the losing side
    // always got a "Finish round"/"Timeout" overlay (onAuctionRoundLost),
    // but the winning side got nothing in either case.
    testWidgets('shows the winning player a Finish round overlay',
        (tester) async {
      await enterRound(tester);

      notifier().onAuctionRoundWon(
        {'arg0': _localId, 'arg1': 'g1'},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().text, strings.finishRoundTitle);
      expect(recorder.last<RoundLottieDialog>().timer, 1500,
          reason: 'the same 1500ms every other auction overlay uses');
    });

    testWidgets('shows nothing to the player it does not name',
        (tester) async {
      await enterRound(tester);

      notifier().onAuctionRoundWon(
        {'arg0': _opponentId, 'arg1': 'g1'},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.shown, isEmpty,
          reason: 'single-sided, same as PlayerLostAuctionRound — the '
              'auction contract does not ask for the watcher to see it');
    });

    testWidgets('an unseated or missing playerId shows nothing',
        (tester) async {
      await enterRound(tester);

      notifier().onAuctionRoundWon({'arg0': '999'}, recorder.show);
      notifier().onAuctionRoundWon(const {}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets(
        'winning and losing are no longer asymmetric — this device now '
        'sees an overlay either way the round could end for it',
        (tester) async {
      await enterRound(tester);

      // Same device, naming itself in each of the two possible outcomes —
      // before this fix, only the second of these ever produced a dialog.
      notifier().onAuctionRoundWon(
        {'arg0': _localId, 'arg1': 'g1'},
        recorder.show,
      );
      await tester.pump();
      expect(recorder.shown, hasLength(1), reason: 'winning shows it');
      recorder.dismissAll();
      await tester.pump();

      notifier().onAuctionRoundLost(
        {'arg0': _localId, 'arg1': 'g1'},
        recorder.show,
      );
      await tester.pump();
      expect(recorder.shown, hasLength(2), reason: 'losing shows it too');
    });
  });

  group('ownership', () {
    testWidgets('a penalty naming the opponent shows me nothing',
        (tester) async {
      await enterRound(tester);

      notifier().onPenalty({'playerId': _opponentId, 'type': 2}, recorder.show);
      notifier().onPenalty({'playerId': _opponentId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty,
          reason: 'the auction contract asks for neither on the watcher');
    });

    testWidgets('a penalty naming nobody shows nothing', (tester) async {
      await enterRound(tester);

      notifier().onPenalty({'playerId': '999', 'type': 2}, recorder.show);
      notifier().onPenalty({'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('CorrectAnswer is silent regardless of who is answering',
        (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _opponentId);

      notifier().onCorrectAnswer(null, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('CorrectAnswer is silent before an answer phase',
        (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(null, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('the answer reveal is shown to both players', (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _opponentId);

      notifier().onPlayerAnswered({'answerText': 'blue'}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1),
          reason: 'the reference reveals the text to both');
    });
  });

  group('timing', () {
    testWidgets('every auction overlay is 1500ms', (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      await tester.pump();
      expect(recorder.last<RoundLottieDialog>().timer, 1500);

      recorder.dismissAll();
      await tester.pump();

      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();
      expect(recorder.last<RoundLottieDialog>().timer, 1500);

      recorder.dismissAll();
      await tester.pump();

      notifier().onPlayerAnswered({'answerText': 'x'}, recorder.show);
      await tester.pump();
      expect(recorder.last<PlayerAnsweredDialog>().timer, 1500);
    });

    testWidgets('a dialog queued behind the turn overlay waits for it to close',
        (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1), reason: 'no stacking');
      expect(recorder.openCount, 1);
    });

    testWidgets(
        'the next dialog is shown as soon as the turn overlay closes — not '
        'after its 4000ms post-close grace period',
        (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();
      expect(recorder.shown, hasLength(1));

      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(2),
          reason: 'the post-close grace period no longer holds the queue');
    });
  });

  group('queue behaviour', () {
    testWidgets('overlays never stack', (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      notifier().onPlayerAnswered({'answerText': 'x'}, recorder.show);
      await tester.pump();

      expect(recorder.openCount, 1);
      expect(recorder.shown, hasLength(1));

      for (var i = 0; i < 3; i++) {
        recorder.dismissAll();
        await tester.pump();
      }
      expect(recorder.shown, hasLength(3));
    });

    testWidgets('queued dialogs are shown in FIFO order', (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      notifier().onPlayerAnswered({'answerText': 'x'}, recorder.show);
      await tester.pump();

      for (var i = 0; i < 2; i++) {
        expect(recorder.openCount, 1, reason: 'no stacking');
        recorder.dismissAll();
        await tester.pump();
      }

      expect(recorder.shown, hasLength(3));
      expect(recorder.shown[0], isA<RoundLottieDialog>().having(
          (d) => d.text, 'text', strings.turnOverlayText(isMine: true, playerName: 'me')),
          reason: 'ChangeTurn first');
      expect(recorder.shown[1], isA<RoundLottieDialog>().having(
          (d) => d.text, 'text', strings.timeout),
          reason: 'Penalty second');
      expect(recorder.shown[2], isA<PlayerAnsweredDialog>(),
          reason: 'PlayerAnswered third');
    });

    testWidgets('a repeated event queues rather than overlapping',
        (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);

      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.openCount, 1, reason: 'one at a time');
    });

    testWidgets('leaving the round drops a queued overlay', (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);

      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      notifier().onPlayerAnswered({'answerText': 'x'}, recorder.show);
      await tester.pump();
      expect(recorder.shown, hasLength(1));

      notifier().showPhase(GamePhase.finishRound);
      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(1),
          reason: 'the queued overlay is re-checked against the phase');
    });
  });

  group('lifecycle', () {
    testWidgets('nothing is shown while the app is away', (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);
      await setLifecycle(tester, AppLifecycleState.paused);

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('nothing is replayed on resume', (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);
      await setLifecycle(tester, AppLifecycleState.paused);
      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();

      await setLifecycle(tester, AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 4000));

      expect(recorder.shown, isEmpty);
    });

    testWidgets('overlays work again after resuming', (tester) async {
      await enterRound(tester);
      await answerPhase(tester, _localId);
      await setLifecycle(tester, AppLifecycleState.paused);
      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();
      expect(recorder.shown, isEmpty);

      await setLifecycle(tester, AppLifecycleState.resumed);
      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
    });
  });

  group('WDYK is unaffected', () {
    testWidgets('a WDYK penalty keeps its own overlay and duration',
        (tester) async {
      await enterRound(tester, type: 1);

      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().timer, 2000,
          reason: 'WDYK strike stays 2000ms');
    });

    testWidgets('a WDYK opponent timeout still reaches this device',
        (tester) async {
      await enterRound(tester, type: 1);

      notifier().onPenalty({'playerId': _opponentId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1),
          reason: 'WDYK shows the watcher a timeout; auction does not');
      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });

    testWidgets(
        'a WDYK turn overlay is not held up by its 1500ms post-close grace '
        'period either', (tester) async {
      await enterRound(tester, type: 1);

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      notifier().onPlayerAnswered({'answerText': 'x'}, recorder.show);
      await tester.pump();
      expect(recorder.shown, hasLength(1));

      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(2),
          reason: 'the shared queue no longer blocks on either grace period');
    });
  });
}
