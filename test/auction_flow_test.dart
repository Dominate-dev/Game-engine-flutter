import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Auction end-to-end flow, driven by the real-device runtime log.
//
// The event sequence below is the one the log shows, in the order it shows it.
// Nothing is invented: where the log does not establish an ordering, the test
// does not assert one.
//
//   GameUpdated(phase 1, currentBid 0, currentTurn 10002, isTimerStarted false)
//   ChangeTurn(10002) · AuctionBiddingPhaseStarted(gameId)
//   PlayerBidded(10002, 1) → ChangeTurn(47)    → TimerUpdatedSeconds 31
//   PlayerBidded(47, 2)    → ChangeTurn(10002) → TimerUpdatedSeconds 31
//   PlayerBidded(10002, 3) → ChangeTurn(47)    → TimerUpdatedSeconds 31
//   Pass(gameId)
//   AuctionAnswerPhaseStarted{47, 2} → ScoreUpdate{0, 2} → ChangeTurn(47)
//   TimeStarted → TimerUpdatedSeconds → SubmitAnswer
//   PlayerWon/LostAuctionRound → AuctionBiddingPhaseStarted (next question)

const _localId = '47';
const _opponentId = '10002';

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  /// Drives invoke()'s return the way a disconnected hub would.
  bool connected = true;

  List<({String method, List<Object?>? args})> named(String method) =>
      invocations.where((i) => i.method == method).toList();

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    if (!connected) {
      return false;
    }
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

/// The GameUpdated shape the log shows, with only the fields it reports.
Map<String, dynamic> _gameUpdated({
  required int phase,
  required int currentBid,
  required String currentTurn,
  int currentScore = 0,
  bool isTimerStarted = false,
  double? currentTimerValue,
  int makeupTryCount = 0,
  int maxMakeupTryCount = 3,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 2,
      'groupId': 'grp',
      'currentTurn': currentTurn,
      'isTimerStarted': isTimerStarted,
      if (currentTimerValue != null) 'currentTimerValue': currentTimerValue,
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
        'phase': phase,
        'currentScore': currentScore,
        'currentBid': currentBid,
        'answerTimeout': 8,
      },
    };

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState session() => container.read(gameControllerProvider);

  Future<void> pumpRound(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: AuctionRoundScreen()),
        ),
      ),
    );
    await tester.pump();
  }

  // ── the log's events, one helper each ────────────────────────────────────
  Future<void> gameUpdated(
    WidgetTester tester,
    Map<String, dynamic> payload,
  ) async {
    notifier().applySessionEvent(PlayGameHubEvents.gameUpdated, payload);
    await tester.pump();
  }

  Future<void> changeTurn(WidgetTester tester, String playerId) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.changeTurn,
      {'arg0': playerId, 'arg1': 'g1'},
    );
    await tester.pump();
  }

  Future<void> biddingPhaseStarted(WidgetTester tester) async {
    notifier().applyAuctionEvent(
      PlayGameHubEvents.auctionBiddingPhaseStarted,
      {'arg0': 'g1'},
    );
    await tester.pump();
  }

  Future<void> playerBidded(
    WidgetTester tester,
    String playerId,
    int bidValue,
  ) async {
    notifier().applyAuctionEvent(
      PlayGameHubEvents.playerBidded,
      {'playerId': playerId, 'bidValue': bidValue},
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

  Future<void> timeStarted(WidgetTester tester) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.timeStarted,
      HubEventPayload.mapFromArgs(['', 'g1']),
    );
    await tester.pump();
  }

  Future<void> answerPhaseStarted(
    WidgetTester tester,
    String playerId,
    int bidValue,
  ) async {
    notifier().applyAuctionEvent(
      PlayGameHubEvents.auctionAnswerPhaseStarted,
      {'playerId': playerId, 'bidValue': bidValue},
    );
    await tester.pump();
  }

  Future<void> scoreUpdate(
    WidgetTester tester, {
    required String playerId,
    int? currentScore,
    int? goalScore,
    int? wrongScore,
  }) async {
    notifier().applyAuctionEvent(
      PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
      {
        'playerId': playerId,
        if (currentScore != null) 'currentScore': currentScore,
        if (goalScore != null) 'goalScore': goalScore,
        if (wrongScore != null) 'wrongScore': wrongScore,
      },
    );
    await tester.pump();
  }

  Future<void> penalty(WidgetTester tester, String playerId, int type) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.penalty,
      {'playerId': playerId, 'type': type},
    );
    await tester.pump();
  }

  /// Dismisses whatever overlay is on screen so the controls are reachable.
  Future<void> settleOverlays(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 4000));
    await tester.pump();
  }

  Future<void> pickNumber(WidgetTester tester) async {
    await tester.tap(find.byType(AppTextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Choose'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  String pickerText(WidgetTester tester) =>
      tester.widget<AppTextField>(find.byType(AppTextField)).controller!.text;

  testWidgets('the whole auction round, as the runtime log shows it',
      (tester) async {
    await pumpRound(tester);

    // ── 1. the round starts in bidding ──────────────────────────────────
    await gameUpdated(
      tester,
      _gameUpdated(phase: 1, currentBid: 0, currentTurn: _opponentId),
    );
    await changeTurn(tester, _opponentId);
    await biddingPhaseStarted(tester);
    await settleOverlays(tester);

    expect(session().phase, GamePhase.auction);
    expect(session().auctionPhase, AuctionPhase.bidding);
    expect(session().currentBid, isNull, reason: 'currentBid 0 means no bid');
    expect(session().currentScore, isNull,
        reason: 'the bidding phase reset clears the answer-phase scores');
    expect(session().game?.isTimerStarted, isFalse);
    expect(find.text('Bidding'), findsOneWidget, reason: 'bidding UI');

    // ── 2. the opponent holds the first turn ────────────────────────────
    expect(session().isMyTurn, isFalse);
    expect(notifier().canBid, isFalse);
    expect(notifier().canTakeTurn, isFalse, reason: 'nobody has bid');

    // ── 3-5. opponent bids 1, turn comes to me, timer restarts ──────────
    await playerBidded(tester, _opponentId, 1);
    await changeTurn(tester, _localId);
    await settleOverlays(tester);
    await timerSeconds(tester, 31);

    expect(session().currentBid, 1, reason: 'the server bid value');
    expect(session().isMyTurn, isTrue, reason: 'ChangeTurn owns the turn');
    expect(session().isBiding, isTrue, reason: 'they bid, so I may raise');
    expect(notifier().auctionMinBid, 2, reason: 'one above the standing bid');
    expect(find.text('00:31'), findsOneWidget, reason: 'timer reset for me');

    // ── 3b. my bid: the picked number goes out, the field clears ────────
    await pickNumber(tester);
    expect(pickerText(tester), '2', reason: 'the picker floor');

    await tester.tap(find.text('Bidding'));
    await tester.pump();

    expect(signalR.named(PlayGameHubEvents.bid), hasLength(1));
    expect(signalR.named(PlayGameHubEvents.bid).single.args, [
      {'gameId': 'g1', 'bidValue': 2},
    ]);
    expect(pickerText(tester), isEmpty,
        reason: 'the field must not keep my last number');

    // ── 6-8. the server confirms my bid and the turn alternates ─────────
    await playerBidded(tester, _localId, 2);
    await changeTurn(tester, _opponentId);
    await settleOverlays(tester);
    await timerSeconds(tester, 31);

    expect(session().currentBid, 2);
    expect(session().isMyTurn, isFalse);
    expect(session().isBiding, isFalse, reason: 'I am the standing bidder');
    expect(notifier().canBid, isFalse);

    // ── 9-10. a third bid, turn back to me, timer resets again ──────────
    await playerBidded(tester, _opponentId, 3);
    await changeTurn(tester, _localId);
    await settleOverlays(tester);
    await timerSeconds(tester, 31);

    expect(session().currentBid, 3);
    expect(session().isMyTurn, isTrue);
    expect(session().isBiding, isTrue);
    expect(notifier().auctionMinBid, 4);
    expect(find.text('00:31'), findsOneWidget);
    expect(pickerText(tester), isEmpty, reason: 'still empty for this turn');

    // ── 11. Take the turn → Pass(gameId), no local phase change ─────────
    await tester.tap(find.text('Take the turn'));
    await tester.pump();

    expect(signalR.named(PlayGameHubEvents.pass), hasLength(1));
    expect(signalR.named(PlayGameHubEvents.pass).single.args, ['g1']);
    expect(session().auctionPhase, AuctionPhase.bidding,
        reason: 'the phase waits for the server');
    expect(find.text('Bidding'), findsOneWidget);

    // ── 12-14. the server opens the answer phase ────────────────────────
    await answerPhaseStarted(tester, _localId, 2);
    await scoreUpdate(tester, playerId: _localId, currentScore: 0, goalScore: 2);
    await changeTurn(tester, _localId);
    await settleOverlays(tester);

    expect(session().auctionPhase, AuctionPhase.answering);
    expect(session().answeringPlayerId, _localId);
    expect(notifier().isAuctionAnswerer, isTrue);
    expect(session().goalScore, 2, reason: 'the winning bid');
    expect(session().currentScore, 0);
    expect(find.text('Bidding'), findsNothing, reason: 'answer UI now');
    expect(find.text('0/2'), findsOneWidget);
    // Chips stay locked until a countdown is running (shared rule).
    expect(find.text('a1'), findsNothing,
        reason: 'no answering before TimerUpdatedSeconds');

    // ── 15-16. TimeStarted, then the authoritative countdown ────────────
    await timeStarted(tester);
    // The overlay itself is raised by the host screen and is covered in
    // auction_dialogs_test.dart; here the state effect is what matters.
    expect(session().game?.isTimerStarted, isTrue);
    expect(find.text('a1'), findsNothing,
        reason: 'TimeStarted alone does not open answering');
    await settleOverlays(tester);

    await timerSeconds(tester, 9);
    expect(find.text('00:09'), findsOneWidget);
    expect(find.text('a1'), findsOneWidget,
        reason: 'the countdown opened the chips');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:07'), findsOneWidget);

    // ── 17-18. answering never resets the countdown ─────────────────────
    await tester.tap(find.text('a1'));
    await tester.pump();
    expect(signalR.named(PlayGameHubEvents.submitAnswer), hasLength(1));
    expect(signalR.named(PlayGameHubEvents.submitAnswer).single.args,
        ['g1', 10]);
    expect(find.text('00:07'), findsOneWidget, reason: 'the tap resets nothing');

    await penalty(tester, _localId, 2); // wrong answer
    expect(session().game?.isTimerStarted, isTrue,
        reason: 'a wrong answer does not end the round');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:05'), findsOneWidget, reason: 'one continuous run');

    // ── 19. the server moves the scores ─────────────────────────────────
    await scoreUpdate(
      tester,
      playerId: _localId,
      currentScore: 1,
      goalScore: 2,
      wrongScore: 1,
    );
    expect(session().currentScore, 1);
    expect(session().wrongScore, 1);
    expect(session().game?.isTimerStarted, isTrue, reason: 'goal not reached');
    expect(find.text('1/2'), findsOneWidget);

    // ── 20. a terminal freezes the countdown ────────────────────────────
    notifier().applyAuctionEvent(
      PlayGameHubEvents.playerWonAuctionRound,
      {'arg0': _localId, 'arg1': 'g1'},
    );
    await tester.pump();

    expect(session().auctionResult, AuctionResult.won);
    expect(session().game?.isTimerStarted, isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('00:00'), findsOneWidget,
        reason: 'a phase boundary resets the auction display');

    // ── 21-24. the next question returns to bidding, with nothing stale ─
    await gameUpdated(
      tester,
      _gameUpdated(phase: 1, currentBid: 0, currentTurn: _opponentId),
    );
    await biddingPhaseStarted(tester);
    await changeTurn(tester, _opponentId);
    await settleOverlays(tester);

    final next = session();
    expect(next.auctionPhase, AuctionPhase.bidding);
    expect(next.currentBid, isNull, reason: 'bid reset');
    expect(next.answeringPlayerId, isNull, reason: 'answering state cleared');
    expect(next.goalScore, isNull);
    expect(next.wrongScore, isNull);
    expect(next.currentScore, isNull, reason: 'cleared for the new question');
    expect(next.auctionResult, AuctionResult.none);
    expect(next.isBiding, isTrue, reason: 'raising is open again');
    expect(next.isMyTurn, isFalse, reason: 'the server named the opponent');
    expect(find.text('Bidding'), findsOneWidget, reason: 'bidding UI is back');
    expect(pickerText(tester), isEmpty, reason: 'the field starts empty');

    // the countdown only runs again on the authoritative event
    expect(find.text('00:00'), findsOneWidget,
        reason: 'nothing carried over from the answer phase');
    await timerSeconds(tester, 31);
    expect(find.text('00:31'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:30'), findsOneWidget, reason: 'running again');

    // and I can bid once the turn returns
    await playerBidded(tester, _opponentId, 1);
    await changeTurn(tester, _localId);
    await settleOverlays(tester);
    expect(notifier().canBid, isTrue);
  });

  group('bid field behaviour across turns', () {
    testWidgets('an empty field shows the error and sends no Bid',
        (tester) async {
      await pumpRound(tester);
      await gameUpdated(
        tester,
        _gameUpdated(phase: 1, currentBid: 0, currentTurn: _localId),
      );
      await biddingPhaseStarted(tester);
      await settleOverlays(tester);

      await tester.tap(find.text('Bidding'));
      await tester.pump();

      expect(
        find.widgetWithText(SnackBar, 'Choose the number of answers'),
        findsOneWidget,
      );
      expect(signalR.named(PlayGameHubEvents.bid), isEmpty);
    });

    testWidgets('a failed dispatch keeps the number for the retry',
        (tester) async {
      await pumpRound(tester);
      await gameUpdated(
        tester,
        _gameUpdated(phase: 1, currentBid: 0, currentTurn: _localId),
      );
      await biddingPhaseStarted(tester);
      await settleOverlays(tester);
      await pickNumber(tester);
      expect(pickerText(tester), '1');

      // A disconnected hub: invoke returns false, nothing left the device.
      signalR.connected = false;
      await tester.tap(find.text('Bidding'));
      await tester.pump();

      expect(signalR.named(PlayGameHubEvents.bid), isEmpty);
      expect(pickerText(tester), '1',
          reason: 'the number is kept so the bid can be retried');

      // Reconnected: the same number goes out and only then is cleared.
      signalR.connected = true;
      await tester.tap(find.text('Bidding'));
      await tester.pump();

      expect(signalR.named(PlayGameHubEvents.bid), hasLength(1));
      expect(pickerText(tester), isEmpty);
    });
  });
}
