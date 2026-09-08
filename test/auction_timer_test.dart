import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Auction A-5 — the answering countdown is ONE continuous run.
//
// TimerUpdatedSeconds starts and updates it; answering, a correct answer and a
// wrong answer all leave it running. Only a terminal ends it: reaching the
// goal, a timeout Penalty(1), or PlayerWon/LostAuctionRound.
//
// The display is read through the real screen so a freeze is observable, the
// same way the WDYK timer tests work.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    invocations.add((method: methodName, args: args));
    return true;
  }

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

Map<String, dynamic> _auctionGame({
  int makeupTryCount = 0,
  int maxMakeupTryCount = 3,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 2,
      'groupId': 'grp',
      'currentTurn': _localId,
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'makeupTryCount': makeupTryCount,
          'maxMakeupTryCount': maxMakeupTryCount,
        },
        {
          'id': _opponentId,
          'playerName': 'them',
          'makeupTryCount': 0,
          'maxMakeupTryCount': maxMakeupTryCount,
        },
      ],
      'currentQuestion': {
        'id': 1682,
        'text': 'q',
        'textEn': 'q',
        'type': 1,
        'maxCorrectAnswersCount': 23,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
          {'id': 11, 'text': 'a2', 'textEn': 'a2'},
        ],
      },
      'auctionGameMetadata': {
        'phase': 2,
        'currentScore': 0,
        'currentBid': 4,
        'answerTimeout': 8,
      },
    };

void main() {
  late ProviderContainer container;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  Future<void> pumpAnswering(
    WidgetTester tester, {
    String answeringPlayerId = _localId,
    int goal = 5,
  }) async {
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: AuctionRoundScreen()),
        ),
      ),
    );
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _auctionGame(),
    );
    await tester.pump();
    notifier().applyAuctionEvent(
      PlayGameHubEvents.auctionAnswerPhaseStarted,
      {'playerId': answeringPlayerId, 'bidValue': goal},
    );
    await tester.pump();
  }

  Future<void> timeStarted(WidgetTester tester) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.timeStarted,
      HubEventPayload.mapFromArgs(['', 'g1']),
    );
    await tester.pump();
  }

  Future<void> timerSeconds(WidgetTester tester, num value) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.timerUpdatedSeconds,
      HubEventPayload.mapFromArgs([value, 'g1']),
    );
    await tester.pump();
  }

  Future<void> tick(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  /// Arms a live countdown at 10s and runs it down to 00:07.
  Future<void> runningTimer(WidgetTester tester) async {
    await timeStarted(tester);
    await timerSeconds(tester, 10);
    await tick(tester, 3);
    expect(find.text('00:07'), findsOneWidget);
  }

  group('TimerUpdatedSeconds drives the auction countdown', () {
    testWidgets('it starts the display', (tester) async {
      await pumpAnswering(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);

      expect(find.text('00:10'), findsOneWidget);
      await tick(tester, 3);
      expect(find.text('00:07'), findsOneWidget);
    });

    testWidgets('a later value restarts it from the server number',
        (tester) async {
      await pumpAnswering(tester);
      await runningTimer(tester);

      await timerSeconds(tester, 20);

      expect(find.text('00:20'), findsOneWidget);
    });

    testWidgets('fractional seconds are floored', (tester) async {
      await pumpAnswering(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 9.8);

      expect(find.text('00:09'), findsOneWidget);
    });
  });

  group('answering never resets the countdown', () {
    testWidgets('submitting an answer leaves it running', (tester) async {
      await pumpAnswering(tester);
      await runningTimer(tester);

      await notifier().submitAuctionAnswer(10);
      await tester.pump();

      expect(find.text('00:07'), findsOneWidget, reason: 'no reset');
      await tick(tester, 3);
      expect(find.text('00:04'), findsOneWidget, reason: 'still running');
    });

    testWidgets('a correct answer leaves it running', (tester) async {
      await pumpAnswering(tester);
      await runningTimer(tester);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.correctAnswer,
        {'arg0': 'a', 'arg1': 'a', 'arg2': _localId},
      );
      await tester.pump();

      expect(current().game?.isTimerStarted, isTrue);
      await tick(tester, 3);
      expect(find.text('00:04'), findsOneWidget);
    });

    testWidgets('a wrong answer Penalty(2) leaves it running', (tester) async {
      await pumpAnswering(tester);
      await runningTimer(tester);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 2},
      );
      await tester.pump();

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'a wrong answer does not end the auction round');
      await tick(tester, 3);
      expect(find.text('00:04'), findsOneWidget);
    });

    testWidgets('a score update short of the goal leaves it running',
        (tester) async {
      await pumpAnswering(tester, goal: 5);
      await runningTimer(tester);

      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {'playerId': _localId, 'currentScore': 3, 'goalScore': 5},
      );
      await tester.pump();

      expect(current().game?.isTimerStarted, isTrue);
      await tick(tester, 3);
      expect(find.text('00:04'), findsOneWidget);
    });

    testWidgets('it survives a whole sequence of answers', (tester) async {
      await pumpAnswering(tester, goal: 4);
      await timeStarted(tester);
      await timerSeconds(tester, 20);

      for (var i = 1; i <= 3; i++) {
        await notifier().submitAuctionAnswer(10);
        notifier().applySharedRoundEvent(
          PlayGameHubEvents.penalty,
          {'playerId': _localId, 'type': 2},
        );
        notifier().applyAuctionEvent(
          PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
          {'playerId': _localId, 'currentScore': i, 'goalScore': 4},
        );
        await tester.pump();
        await tick(tester, 2);
      }

      expect(current().game?.isTimerStarted, isTrue);
      expect(find.text('00:14'), findsOneWidget,
          reason: 'one continuous countdown across three answers');
    });

    testWidgets('a bid never touches the countdown', (tester) async {
      await pumpAnswering(tester);
      await runningTimer(tester);

      notifier().applyAuctionEvent(
        PlayGameHubEvents.playerBidded,
        {'playerId': _opponentId, 'bidValue': 6},
      );
      await tester.pump();

      expect(current().game?.isTimerStarted, isTrue);
      expect(find.text('00:07'), findsOneWidget);
    });
  });

  group('terminals freeze the countdown', () {
    testWidgets('reaching the goal freezes it', (tester) async {
      await pumpAnswering(tester, goal: 3);
      await runningTimer(tester);

      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {'playerId': _localId, 'currentScore': 3, 'goalScore': 3},
      );
      await tester.pump();

      expect(current().game?.isTimerStarted, isFalse);
      // UPDATED: frozen immediately, then cleared once
      // CountdownTimerText.freezeResetDelay has passed.
      await tick(tester, 3);
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('a timeout Penalty(1) freezes it', (tester) async {
      await pumpAnswering(tester);
      await runningTimer(tester);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 1},
      );
      await tester.pump();

      expect(current().game?.isTimerStarted, isFalse);
      // UPDATED: cleared after the 500ms post-freeze reset.
      await tick(tester, 3);
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('PlayerLostAuctionRound stops it and resets the display',
        (tester) async {
      await pumpAnswering(tester);
      await runningTimer(tester);

      notifier().applyAuctionEvent(
        PlayGameHubEvents.playerLostAuctionRound,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      await tester.pump();

      expect(current().game?.isTimerStarted, isFalse);
      // A phase boundary resets the auction display rather than freezing it.
      expect(find.text('00:00'), findsOneWidget);
      await tick(tester, 3);
      expect(find.text('00:00'), findsOneWidget, reason: 'still stopped');
    });

    testWidgets('PlayerWonAuctionRound freezes it', (tester) async {
      await pumpAnswering(tester);
      await runningTimer(tester);

      notifier().applyAuctionEvent(
        PlayGameHubEvents.playerWonAuctionRound,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      await tester.pump();

      expect(current().game?.isTimerStarted, isFalse);
    });

    testWidgets('a freeze never rewrites the server seconds', (tester) async {
      await pumpAnswering(tester, goal: 2);
      await runningTimer(tester);

      notifier().applyAuctionEvent(
        PlayGameHubEvents.playerLostAuctionRound,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      await tester.pump();

      expect(current().game?.currentTimerValue, 10);
    });

    testWidgets('a fresh TimerUpdatedSeconds restarts after a freeze',
        (tester) async {
      await pumpAnswering(tester, goal: 2);
      await runningTimer(tester);
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {'playerId': _localId, 'currentScore': 2, 'goalScore': 2},
      );
      await tester.pump();

      await timerSeconds(tester, 15);

      expect(find.text('00:15'), findsOneWidget);
    });
  });

  group('a phase change resets the display', () {
    testWidgets('AuctionAnswerPhaseStarted zeroes it and does not start it',
        (tester) async {
      await pumpAnswering(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 20);
      await tick(tester, 3);
      expect(find.text('00:17'), findsOneWidget);

      // Back to bidding, then a fresh answer phase.
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionBiddingPhaseStarted,
        {'arg0': 'g1'},
      );
      await tester.pump();
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 3},
      );
      await tester.pump();

      expect(find.text('00:00'), findsOneWidget);
      await tick(tester, 3);
      expect(find.text('00:00'), findsOneWidget, reason: 'not running');
    });

    testWidgets('TimeStarted alone does not start the countdown',
        (tester) async {
      await pumpAnswering(tester);
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 3},
      );
      await tester.pump();
      expect(find.text('00:00'), findsOneWidget);

      await timeStarted(tester);

      expect(find.text('00:00'), findsOneWidget);
      await tick(tester, 3);
      expect(find.text('00:00'), findsOneWidget,
          reason: 'only TimerUpdatedSeconds may start it');
    });

    testWidgets('TimerUpdatedSeconds then starts the answering countdown',
        (tester) async {
      await pumpAnswering(tester);
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 3},
      );
      await timeStarted(tester);
      await tester.pump();

      await timerSeconds(tester, 9);

      expect(find.text('00:09'), findsOneWidget);
      await tick(tester, 2);
      expect(find.text('00:07'), findsOneWidget);
    });

    testWidgets('ending the answer phase zeroes it for bidding',
        (tester) async {
      await pumpAnswering(tester);
      await runningTimer(tester);

      notifier().applyAuctionEvent(
        PlayGameHubEvents.playerWonAuctionRound,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      await tester.pump();
      expect(find.text('00:00'), findsOneWidget);

      // Returning to bidding keeps it at zero.
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionBiddingPhaseStarted,
        {'arg0': 'g1'},
      );
      await tester.pump();
      await tick(tester, 3);
      expect(find.text('00:00'), findsOneWidget,
          reason: 'no answering value carried into bidding');

      // Only the authoritative event restarts it.
      await timerSeconds(tester, 31);
      expect(find.text('00:31'), findsOneWidget);
      await tick(tester, 1);
      expect(find.text('00:30'), findsOneWidget);
    });
  });

  group('the client never moves the server counters', () {
    testWidgets('submitting bumps neither wrongScore nor makeupTryCount',
        (tester) async {
      await pumpAnswering(tester);
      await runningTimer(tester);

      await notifier().submitAuctionAnswer(10);
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 2},
      );
      await tester.pump();

      expect(current().wrongScore, isNull,
          reason: 'only AuctionAnswerPhaseScoreUpdate sets it');
      expect(current().me?.makeupTryCount, 0,
          reason: 'only GameUpdated moves it');
    });
  });

  // TimerUpdatedSeconds now reports isTimerStarted: true alongside the value,
  // so the countdown it starts is visible as running to every reader of the
  // flag. The auction's own rule — its answer phase is one continuous
  // countdown, and only a timeout, the goal, or a won/lost outcome ends it —
  // is decided by _eventStopsTimer and the auction handler, neither of which
  // changed. These pin that, with no TimeStarted in the sequence, exactly as
  // the server sends it.
  group('the auction answer phase is still one continuous countdown', () {
    testWidgets('TimerUpdatedSeconds alone reports it running', (tester) async {
      await pumpAnswering(tester);
      await timerSeconds(tester, 10);

      expect(current().game?.isTimerStarted, isTrue);
      expect(find.text('00:10'), findsOneWidget);
    });

    testWidgets('a correct answer does not stop it', (tester) async {
      await pumpAnswering(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.correctAnswer,
        HubEventPayload.mapFromArgs(['a1', 'a1', _localId]),
      );
      await tester.pump();

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'auction correct answers are not terminal — unchanged');
      await tick(tester, 2);
      expect(find.text('00:05'), findsOneWidget, reason: 'still counting');
    });

    testWidgets('a wrong-answer Penalty(2) does not stop it', (tester) async {
      await pumpAnswering(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);

      notifier().applySharedRoundEvent(PlayGameHubEvents.penalty, {
        ...?HubEventPayload.mapFromArgs([_localId, 'g1']),
        'type': 2,
      });
      await tester.pump();

      expect(current().game?.isTimerStarted, isTrue);
      await tick(tester, 2);
      expect(find.text('00:05'), findsOneWidget);
    });

    testWidgets('a timeout Penalty(1) still freezes and clears it',
        (tester) async {
      await pumpAnswering(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);

      notifier().applySharedRoundEvent(PlayGameHubEvents.penalty, {
        ...?HubEventPayload.mapFromArgs([_localId, 'g1']),
        'type': 1,
      });
      await tester.pump();

      expect(current().game?.isTimerStarted, isFalse);
      expect(find.text('00:07'), findsOneWidget, reason: 'frozen in place');
      await tick(tester, 1);
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('reaching the goal still freezes and clears it',
        (tester) async {
      await pumpAnswering(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);

      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {'playerId': _localId, 'currentScore': 5, 'goalScore': 5},
      );
      await tester.pump();

      expect(current().game?.isTimerStarted, isFalse);
      expect(find.text('00:07'), findsOneWidget);
      await tick(tester, 1);
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('the bidding phase boundary still zeroes it', (tester) async {
      await pumpAnswering(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);

      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionBiddingPhaseStarted,
        {'gameId': 'g1'},
      );
      await tester.pump();

      expect(find.text('00:00'), findsOneWidget,
          reason: 'the auction phase-boundary reset is untouched');
    });
  });
}
