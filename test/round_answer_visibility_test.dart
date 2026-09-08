import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The ANSWER visibility contract, audited per round: answer choices must not
// be visible until that round's own timer-start signal arrives.
//
// The signal is NOT the same mechanism in every round, and this file does not
// impose one:
//   * WDYK / Auction / Bell release chips through the shared
//     GameSessionState.answersUnlocked, opened only by a TimerUpdatedSeconds
//     carrying time.
//   * Comeback / Breaker release them through the widget-local
//     _questionVisible latch in ComebackStyleRoundContent, combined with
//     their own progressive NextQuestion sourcing.
//
// Nothing here asserts anything about the QUESTION: question visibility is a
// separate concern and the question is allowed to be visible before the
// timer.

const _localId = '47';
const _opponentId = '211403';

const _answer1 = 'a1';
const _answer2 = 'a2';

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

Map<String, dynamic> _questionJson({int id = 1}) => {
      'id': id,
      'text': 'q$id',
      'textEn': 'q$id',
      'type': 1,
      'maxCorrectAnswersCount': 23,
      'answers': [
        {'id': 10, 'text': _answer1, 'textEn': _answer1},
        {'id': 11, 'text': _answer2, 'textEn': _answer2},
      ],
    };

/// A round snapshot carrying the full question AND its answers — the payload
/// the server really does deliver before the round is active.
Map<String, dynamic> _game({
  required int type,
  bool isTimerStarted = false,
  double currentTimerValue = 0,
  String currentTurn = _localId,
  // Auction only: 1 bidding, 2 answering. A restore taken mid-answer-phase
  // really does carry 2 (see auction_restore_test.dart); restoring with 1
  // puts the bidding panel back up, where there are no chips either way.
  int auctionPhase = 1,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      'currentTurn': currentTurn,
      'isTimerStarted': isTimerStarted,
      'currentTimerValue': currentTimerValue,
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
      'currentQuestion': _questionJson(),
      if (type == 2)
        'auctionGameMetadata': {
          'phase': auctionPhase,
          'currentScore': 0,
          'currentBid': 0,
          'answerTimeout': 8,
        },
    };

void main() {
  late ProviderContainer container;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  Future<void> newContainer() async {
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
  }

  Future<void> mount(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // The real host wraps the round in AppScaffold; Auction's bid picker
        // needs a Material ancestor.
        child: MaterialApp(home: Scaffold(body: screen)),
      ),
    );
  }

  /// Entering a round raises its intro / "start increasing" overlay; letting
  /// it retire keeps the panel underneath reachable.
  Future<void> settleOverlay(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pump();
  }

  Future<void> session(
    WidgetTester tester,
    String event, {
    required int type,
    bool isTimerStarted = false,
    double currentTimerValue = 0,
    String currentTurn = _localId,
    int auctionPhase = 1,
  }) async {
    notifier().applySessionEvent(
      event,
      _game(
        type: type,
        isTimerStarted: isTimerStarted,
        currentTimerValue: currentTimerValue,
        currentTurn: currentTurn,
        auctionPhase: auctionPhase,
      ),
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

  Future<void> timerUpdatedSeconds(WidgetTester tester, num seconds) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.timerUpdatedSeconds,
      HubEventPayload.mapFromArgs([seconds, 'g1']),
    );
    await tester.pump();
  }

  /// The round boundary. Routed through applySharedRoundEvent, which is
  /// where NextRoundStarted is actually reduced.
  Future<void> nextRoundStarted(WidgetTester tester, int roundType) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.nextRoundStarted,
      HubEventPayload.mapFromArgs([roundType, 'g1']),
    );
    await tester.pump();
  }

  /// Comeback/Breaker render only what NextQuestion delivers — never the
  /// GameUpdated snapshot. Their chips therefore need this as well as a
  /// countdown. That progressive sourcing is theirs and is left untouched.
  Future<void> nextQuestion(WidgetTester tester, {int id = 1}) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.nextQuestion,
      _questionJson(id: id),
    );
    await tester.pump();
  }

  void expectAnswersHidden() {
    expect(find.text(_answer1), findsNothing);
    expect(find.text(_answer2), findsNothing);
  }

  void expectAnswersVisible() {
    expect(find.text(_answer1), findsOneWidget);
    expect(find.text(_answer2), findsOneWidget);
  }

  // =====================================================================
  // WDYK (1) and Bell (3) — chips gated by isMyTurn && answersUnlocked.
  // =====================================================================
  final turnRounds = <String, ({int type, Widget screen})>{
    'WDYK': (type: 1, screen: const WdykRoundScreen()),
    'Bell': (type: 3, screen: const BellRoundScreen()),
  };

  for (final entry in turnRounds.entries) {
    final name = entry.key;
    final round = entry.value;

    group('$name — answer chips wait for the countdown', () {
      testWidgets('C. GameUpdated carrying the answers does not show them',
          (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(tester, PlayGameHubEvents.gameUpdated, type: round.type);

        expect(current().isMyTurn, isTrue,
            reason: 'the turn is mine — only the countdown is missing');
        expect(current().answersUnlocked, isFalse);
        expectAnswersHidden();
      });

      testWidgets('D. TimeStarted alone does not show them', (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(tester, PlayGameHubEvents.gameUpdated, type: round.type);
        await timeStarted(tester);

        expect(current().game?.isTimerStarted, isTrue,
            reason: 'TimeStarted flips the flag but opens nothing');
        expectAnswersHidden();

        await tester.pump(const Duration(milliseconds: 2500));
        expectAnswersHidden();
      });

      testWidgets('E. the first TimerUpdatedSeconds shows them',
          (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(tester, PlayGameHubEvents.gameUpdated, type: round.type);
        await timeStarted(tester);
        expectAnswersHidden();

        await timerUpdatedSeconds(tester, 30);

        expectAnswersVisible();
      });

      testWidgets('E2. a countdown carrying no time does not show them',
          (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(tester, PlayGameHubEvents.gameUpdated, type: round.type);

        await timerUpdatedSeconds(tester, 0);

        expectAnswersHidden();
      });

      testWidgets('F. a restore with no running countdown keeps them hidden',
          (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(tester, PlayGameHubEvents.gameRestore, type: round.type);

        expect(current().answersUnlocked, isFalse);
        expectAnswersHidden();
      });

      testWidgets('G. a restore with an already-running countdown may show '
          'them', (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(
          tester,
          PlayGameHubEvents.gameRestore,
          type: round.type,
          isTimerStarted: true,
          currentTimerValue: 12,
        );

        expectAnswersVisible();
      });

      testWidgets('H. entering this round from a previous one does not leak '
          'answers before the new countdown', (tester) async {
        await newContainer();
        // A previous round, mid-question, with a live countdown.
        await session(
          tester,
          PlayGameHubEvents.gameUpdated,
          type: round.type == 1 ? 3 : 1,
          isTimerStarted: true,
          currentTimerValue: 9,
        );
        await timerUpdatedSeconds(tester, 9);
        expect(current().answersUnlocked, isTrue, reason: 'sanity');

        // The round boundary.
        await nextRoundStarted(tester, round.type);
        await mount(tester, round.screen);
        await settleOverlay(tester);
        await session(tester, PlayGameHubEvents.gameUpdated, type: round.type);

        expect(current().answersUnlocked, isFalse);
        expectAnswersHidden();
      });

      testWidgets('I. the opponent\'s turn still gets no chips after the '
          'countdown — the eligibility rule is unchanged', (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(
          tester,
          PlayGameHubEvents.gameUpdated,
          type: round.type,
          currentTurn: _opponentId,
        );
        await timerUpdatedSeconds(tester, 30);

        expect(current().answersUnlocked, isTrue, reason: 'countdown is open');
        expectAnswersHidden();
      });
    });
  }

  // =====================================================================
  // Auction (2) — answering-phase chips only. Bidding controls and the bid
  // picker are NOT answer choices and are deliberately not asserted on.
  // =====================================================================
  group('Auction — answering-phase chips wait for the countdown', () {
    Future<void> enterAuction(WidgetTester tester) async {
      await newContainer();
      await mount(tester, const AuctionRoundScreen());
      await session(tester, PlayGameHubEvents.gameStarted, type: 2);
      await settleOverlay(tester);
    }

    Future<void> answerPhase(WidgetTester tester, String playerId) async {
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': playerId, 'bidValue': 3},
      );
      await tester.pump();
    }

    testWidgets('C. the named answerer sees no chips before the countdown',
        (tester) async {
      await enterAuction(tester);
      await answerPhase(tester, _localId);

      expect(notifier().isAuctionAnswerer, isTrue,
          reason: 'named by AuctionAnswerPhaseStarted');
      expect(current().answersUnlocked, isFalse);
      expectAnswersHidden();
    });

    testWidgets('D. TimeStarted alone does not show them', (tester) async {
      await enterAuction(tester);
      await answerPhase(tester, _localId);
      await timeStarted(tester);

      expectAnswersHidden();
      await tester.pump(const Duration(milliseconds: 2500));
      expectAnswersHidden();
    });

    testWidgets('E. the answer countdown shows them', (tester) async {
      await enterAuction(tester);
      await answerPhase(tester, _localId);
      await timerUpdatedSeconds(tester, 30);

      expectAnswersVisible();
    });

    testWidgets('H. a new answer phase re-hides them until its own countdown',
        (tester) async {
      await enterAuction(tester);
      await answerPhase(tester, _localId);
      await timerUpdatedSeconds(tester, 30);
      expectAnswersVisible();

      await answerPhase(tester, _localId);

      expectAnswersHidden();
    });

    testWidgets('I. the watching player gets no chips even after the '
        'countdown', (tester) async {
      await enterAuction(tester);
      await answerPhase(tester, _opponentId);
      await timerUpdatedSeconds(tester, 30);

      expect(current().answersUnlocked, isTrue, reason: 'countdown is open');
      expect(notifier().isAuctionAnswerer, isFalse);
      expectAnswersHidden();
    });

    testWidgets('G. a restore with an already-running countdown may show them',
        (tester) async {
      await enterAuction(tester);
      await answerPhase(tester, _localId);
      await session(
        tester,
        PlayGameHubEvents.gameRestore,
        type: 2,
        isTimerStarted: true,
        currentTimerValue: 12,
        auctionPhase: 2,
      );

      expectAnswersVisible();
    });

    testWidgets('F. a restore with no running countdown keeps them hidden',
        (tester) async {
      await enterAuction(tester);
      await answerPhase(tester, _localId);
      await timerUpdatedSeconds(tester, 30);
      expectAnswersVisible();

      await session(
        tester,
        PlayGameHubEvents.gameRestore,
        type: 2,
        auctionPhase: 2,
      );

      expect(current().answersUnlocked, isFalse);
      expectAnswersHidden();
    });
  });

  // =====================================================================
  // Comeback (4) and Breaker (5) — the _questionVisible latch plus their
  // own NextQuestion sourcing.
  // =====================================================================
  final latchRounds = <String, ({int type, Widget screen, int previousType})>{
    'Comeback': (type: 4, screen: const ComeBackRoundScreen(), previousType: 3),
    'Breaker': (type: 5, screen: const BreakerRoundScreen(), previousType: 4),
  };

  for (final entry in latchRounds.entries) {
    final name = entry.key;
    final round = entry.value;

    group('$name — answer chips wait for the countdown', () {
      testWidgets('C. GameUpdated carrying the answers does not show them',
          (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(tester, PlayGameHubEvents.gameUpdated, type: round.type);

        expectAnswersHidden();
      });

      testWidgets('D. TimeStarted alone does not show them', (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(tester, PlayGameHubEvents.gameUpdated, type: round.type);
        await timeStarted(tester);

        expectAnswersHidden();
        await tester.pump(const Duration(milliseconds: 2500));
        expectAnswersHidden();
      });

      testWidgets('D2. TimeStarted flipping the flag while a frozen value is '
          'still standing does not show them', (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        // A frozen leftover: stopped, but the value was never zeroed.
        await session(
          tester,
          PlayGameHubEvents.gameUpdated,
          type: round.type,
          isTimerStarted: false,
          currentTimerValue: 9,
        );
        await nextQuestion(tester);
        expectAnswersHidden();

        // TimeStarted makes isTimerStarted true with that stale value still
        // in place — still not a countdown that has started.
        await timeStarted(tester);

        expectAnswersHidden();
      });

      testWidgets('E. a countdown plus the round\'s own NextQuestion shows '
          'them', (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(tester, PlayGameHubEvents.gameUpdated, type: round.type);
        await timerUpdatedSeconds(tester, 30);
        expectAnswersHidden();

        await nextQuestion(tester);

        expectAnswersVisible();
      });

      testWidgets('C2. NextQuestion before any countdown still shows nothing',
          (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(tester, PlayGameHubEvents.gameUpdated, type: round.type);

        await nextQuestion(tester);

        expectAnswersHidden();
      });

      testWidgets('F. a restore with no running countdown keeps them hidden',
          (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(tester, PlayGameHubEvents.gameRestore, type: round.type);

        expectAnswersHidden();
      });

      testWidgets('G. a restore with an already-running countdown may show '
          'them', (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(
          tester,
          PlayGameHubEvents.gameRestore,
          type: round.type,
          isTimerStarted: true,
          currentTimerValue: 12,
        );

        expectAnswersVisible();
      });

      testWidgets('F2. a snapshot whose countdown is frozen — stopped, but '
          'still carrying its last value — is not a running countdown',
          (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(
          tester,
          PlayGameHubEvents.gameUpdated,
          type: round.type,
          isTimerStarted: false,
          currentTimerValue: 9,
        );
        await nextQuestion(tester);

        expectAnswersHidden();
      });

      testWidgets('H. entering this round from a previous one whose countdown '
          'was frozen does not leak answers before the new countdown',
          (tester) async {
        await newContainer();
        // The previous round ends with its countdown FROZEN, not zeroed: a
        // stop is a freeze everywhere in this codebase, so currentTimerValue
        // stays positive across the boundary.
        await session(
          tester,
          PlayGameHubEvents.gameUpdated,
          type: round.previousType,
          isTimerStarted: true,
          currentTimerValue: 9,
        );
        await timerUpdatedSeconds(tester, 9);

        await nextRoundStarted(tester, round.type);
        expect(current().game?.currentTimerValue, greaterThan(0),
            reason: 'the frozen value really does survive the boundary — '
                'this is what the round entry must not treat as a live '
                'countdown');

        // The new round's screen mounts here, exactly as the router does it.
        await mount(tester, round.screen);
        await settleOverlay(tester);
        await nextQuestion(tester, id: 2);

        expectAnswersHidden();
      });

      testWidgets('I. both players may answer once revealed — no turn gate',
          (tester) async {
        await newContainer();
        await mount(tester, round.screen);
        await session(
          tester,
          PlayGameHubEvents.gameUpdated,
          type: round.type,
          currentTurn: _opponentId,
        );
        await timerUpdatedSeconds(tester, 30);
        await nextQuestion(tester);

        expect(current().isMyTurn, isFalse);
        expectAnswersVisible();
      });
    });
  }
}
