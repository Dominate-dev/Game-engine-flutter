import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/presentation/dialogs/count_answer_dialog.dart';
import 'package:play_game/presentation/widgets/rounds/round_attempts_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Auction A-2 — the bidding controls on the real screen.
//
// Enablement is read through the button's Opacity (1 live, 0.4 dead), the
// pattern the WDYK Pass button already uses.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];
  bool connected = true;

  List<({String method, List<Object?>? args})> get passes =>
      invocations.where((i) => i.method == PlayGameHubEvents.pass).toList();

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

Map<String, dynamic> _auctionGame({String currentTurn = _localId}) => {
      'id': 'g1',
      'status': 3,
      'type': 2,
      'groupId': 'grp',
      'currentTurn': currentTurn,
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'makeupTryCount': 1,
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
        'id': 1682,
        'text': 'q',
        'textEn': 'q',
        'type': 1,
        'maxCorrectAnswersCount': 23,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
      'auctionGameMetadata': {
        'phase': 1,
        'currentScore': 0,
        'currentBid': 0,
        'answerTimeout': 8,
      },
    };

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  Future<void> pumpBidding(
    WidgetTester tester, {
    String currentTurn = _localId,
    bool settleStartIncreasing = true,
  }) async {
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          // The real host wraps the round in AppScaffold; the picker field needs
          // a Material ancestor. GameControllerScreen also hosts the round
          // overlay layer, which is where a RoundLottieDialog now renders —
          // reproduced here so this screen's own overlays reach the tree.
          home: Scaffold(
            body: Stack(
              children: [
                AuctionRoundScreen(),
                Positioned.fill(child: RoundSubPanelLayer()),
              ],
            ),
          ),
        ),
      ),
    );
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _auctionGame(currentTurn: currentTurn),
    );
    await tester.pump();
    // Entering the bidding phase raises the "start increasing" overlay (A-4).
    // Most tests let it retire so the controls underneath are reachable.
    if (settleStartIncreasing) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();
    }
  }

  Future<void> bidded(WidgetTester tester, String playerId, int value) async {
    notifier().applyAuctionEvent(
      PlayGameHubEvents.playerBidded,
      {'playerId': playerId, 'bidValue': value},
    );
    await tester.pump();
  }

  double opacityOf(WidgetTester tester, String label) => tester
      .widget<Opacity>(
        find.ancestor(of: find.text(label), matching: find.byType(Opacity)).first,
      )
      .opacity;

  group('the bidding controls follow the server state', () {
    testWidgets('the bidding panel is shown while the phase is bidding',
        (tester) async {
      await pumpBidding(tester);

      expect(find.text('Bidding'), findsOneWidget);
      expect(find.text('Take the turn'), findsOneWidget);
    });

    testWidgets('Bid stays live with no number picked — legacy parity',
        (tester) async {
      await pumpBidding(tester);

      expect(opacityOf(tester, 'Bidding'), 1,
          reason: 'the empty case is answered by the tap, not by disabling');
    });

    testWidgets('tapping Bid with no number shows the error and sends nothing',
        (tester) async {
      await pumpBidding(tester);

      await tester.tap(find.text('Bidding'));
      await tester.pump();

      expect(
        find.widgetWithText(SnackBar, 'Choose the number of answers'),
        findsOneWidget,
      );
      expect(
        signalR.invocations.where((i) => i.method == PlayGameHubEvents.bid),
        isEmpty,
        reason: 'no hub call without a chosen number',
      );
    });

    testWidgets('Bid is dead when it is not my turn', (tester) async {
      await pumpBidding(tester, currentTurn: _opponentId);

      expect(opacityOf(tester, 'Bidding'), 0.4);
    });

    testWidgets('Take the turn is dead until someone has bid', (tester) async {
      await pumpBidding(tester);
      expect(opacityOf(tester, 'Take the turn'), 0.4);

      await bidded(tester, _opponentId, 3);

      expect(opacityOf(tester, 'Take the turn'), 1);
    });

    testWidgets('Take the turn stays dead when it is not my turn',
        (tester) async {
      await pumpBidding(tester, currentTurn: _opponentId);
      await bidded(tester, _opponentId, 3);

      expect(opacityOf(tester, 'Take the turn'), 0.4);
    });

    testWidgets('a chosen number dispatches the bid and shows no error',
        (tester) async {
      await pumpBidding(tester);

      // Choose a number through the real picker, as a player would.
      await tester.tap(find.byType(AppTextField));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Choose'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Bidding'));
      await tester.pump();

      final bids = signalR.invocations
          .where((i) => i.method == PlayGameHubEvents.bid)
          .toList();
      expect(bids, hasLength(1));
      expect(bids.single.args, [
        {'gameId': 'g1', 'bidValue': 1},
      ]);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('the standing bid is displayed', (tester) async {
      await pumpBidding(tester);
      expect(find.text('00'), findsOneWidget);

      await bidded(tester, _opponentId, 6);

      expect(find.text('6'), findsOneWidget);
      expect(find.text('00'), findsNothing);
    });

    testWidgets('tapping Take the turn does not switch to the answer panel',
        (tester) async {
      await pumpBidding(tester);
      await bidded(tester, _opponentId, 3);

      await tester.tap(find.text('Take the turn'));
      await tester.pump();

      expect(signalR.passes, hasLength(1), reason: 'Pass was dispatched');
      expect(signalR.passes.single.args, ['g1']);
      expect(find.text('Bidding'), findsOneWidget,
          reason: 'the panel waits for AuctionAnswerPhaseStarted');
    });

    testWidgets('the answer panel appears only on the server event',
        (tester) async {
      await pumpBidding(tester);
      await bidded(tester, _opponentId, 3);
      await tester.tap(find.text('Take the turn'));
      await tester.pump();
      expect(find.text('Bidding'), findsOneWidget);

      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _opponentId, 'bidValue': 3},
      );
      await tester.pump();

      expect(find.text('Bidding'), findsNothing);
      expect(find.text('Take the turn'), findsNothing);
    });
  });

  group('the answer-count field follows the turn', () {
    Future<void> tapCountField(WidgetTester tester) async {
      await tester.tap(find.byType(AppTextField));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    // Lets a start-increasing overlay raised by the new turn retire first.
    Future<void> changeTurn(WidgetTester tester, String playerId) async {
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.changeTurn,
        {'arg0': playerId, 'arg1': 'g1'},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();
    }

    testWidgets('it opens the picker on my turn', (tester) async {
      await pumpBidding(tester);

      await tapCountField(tester);

      expect(find.byType(CountAnswerDialog), findsOneWidget);
    });

    testWidgets('it opens no picker when it is not my turn', (tester) async {
      await pumpBidding(tester, currentTurn: _opponentId);

      await tapCountField(tester);

      expect(find.byType(CountAnswerDialog), findsNothing);
      expect(find.byType(AppTextField), findsOneWidget);
    });

    testWidgets('it opens the picker once the turn comes to me',
        (tester) async {
      await pumpBidding(tester, currentTurn: _opponentId);

      await changeTurn(tester, _localId);
      await tapCountField(tester);

      expect(find.byType(CountAnswerDialog), findsOneWidget);
    });

    testWidgets('it stops opening the picker once the turn moves away',
        (tester) async {
      await pumpBidding(tester);

      await changeTurn(tester, _opponentId);
      await tapCountField(tester);

      expect(find.byType(CountAnswerDialog), findsNothing);
    });
  });

  group('the start increasing overlay reaches the screen', () {
    /// The real-device order: the session is already in the auction bidding
    /// phase *before* this screen is ever built, because showPhase applies the
    /// metadata first. ref.listen sees no transition in that case.
    Future<void> pumpAfterBiddingBegan(
      WidgetTester tester, {
      String currentTurn = _localId,
    }) async {
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
      // Holds the autoDispose provider open while state is seeded before any
      // widget subscribes to it.
      final sub = container.listen(gameControllerProvider, (_, __) {});
      addTearDown(sub.close);

      // State first, screen second.
      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _auctionGame(currentTurn: currentTurn),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            // GameControllerScreen hosts the round overlay layer in
            // production; reproduced here so this screen's own overlays
            // reach the tree.
            home: Scaffold(
              body: Stack(
                children: [
                  AuctionRoundScreen(),
                  Positioned.fill(child: RoundSubPanelLayer()),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('it renders when the round opens already in bidding',
        (tester) async {
      await pumpAfterBiddingBegan(tester);

      expect(find.byType(RoundLottieDialog), findsOneWidget);
      expect(find.text('Start\nIncreasing'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();
      expect(find.byType(RoundLottieDialog), findsNothing);
    });

    testWidgets('it renders when bidding begins while the screen is up',
        (tester) async {
      await pumpBidding(tester, settleStartIncreasing: false);
      await tester.pump();

      expect(find.text('Start\nIncreasing'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();
    });

    testWidgets('it does not render when it is not my turn', (tester) async {
      await pumpAfterBiddingBegan(tester, currentTurn: _opponentId);

      expect(find.byType(RoundLottieDialog), findsNothing);
    });

    testWidgets('it renders once per bidding phase, not on every rebuild',
        (tester) async {
      await pumpBidding(tester, settleStartIncreasing: false);
      await tester.pump();
      expect(find.byType(RoundLottieDialog), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();

      // Another bid rebuilds the screen; the overlay must not come back.
      await bidded(tester, _opponentId, 3);
      await tester.pump();

      expect(find.byType(RoundLottieDialog), findsNothing);
    });

    testWidgets('a new bidding phase shows it again', (tester) async {
      await pumpBidding(tester);
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 3},
      );
      await tester.pump();

      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionBiddingPhaseStarted,
        {'arg0': 'g1'},
      );
      await tester.pump();

      expect(find.text('Start\nIncreasing'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();
    });
  });

  group('the number of attempts row', () {
    testWidgets('it is hidden during bidding', (tester) async {
      await pumpBidding(tester);

      expect(find.byType(RoundAttemptsInfo), findsNothing);
      expect(find.textContaining('Number of attempts'), findsNothing);
    });

    testWidgets('it is shown for the answering player', (tester) async {
      await pumpBidding(tester);
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 3},
      );
      await tester.pump();

      expect(find.byType(RoundAttemptsInfo), findsOneWidget);
      expect(find.textContaining('Number of attempts'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget,
          reason: 'the server makeup counters, under the legacy label');
    });

    testWidgets('it is hidden when it is not my turn', (tester) async {
      await pumpBidding(tester);
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 3},
      );
      await tester.pump();
      expect(find.byType(RoundAttemptsInfo), findsOneWidget);

      // The turn moves to the opponent.
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.changeTurn,
        {'arg0': _opponentId, 'arg1': 'g1'},
      );
      await tester.pump();

      expect(find.byType(RoundAttemptsInfo), findsNothing);
      expect(find.textContaining('Number of attempts'), findsNothing);
      expect(find.text('Strike'), findsNothing,
          reason: 'hidden, not replaced');
    });

    testWidgets('it returns when the turn comes back', (tester) async {
      await pumpBidding(tester, currentTurn: _opponentId);
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 3},
      );
      await tester.pump();
      expect(find.byType(RoundAttemptsInfo), findsNothing);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      await tester.pump();

      expect(find.byType(RoundAttemptsInfo), findsOneWidget);
    });

    testWidgets('it never uses Strike as its label', (tester) async {
      await pumpBidding(tester);
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 3},
      );
      await tester.pump();

      expect(find.text('Strike'), findsNothing,
          reason: 'Strike belongs to the wrong-answer dialog only');
    });

    testWidgets('it is absent when no answering player is known',
        (tester) async {
      await pumpBidding(tester);
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': '999', 'bidValue': 3},
      );
      await tester.pump();

      expect(find.byType(RoundAttemptsInfo), findsNothing);
    });
  });

  group('the answering panel follows the named player', () {
    Future<void> answerPhase(WidgetTester tester, String playerId) async {
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': playerId, 'bidValue': 3},
      );
      // Answering opens only once a countdown is running (shared rule).
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([30, 'g1']),
      );
      await tester.pump();
    }

    testWidgets('the answering player sees the chips and can tap one',
        (tester) async {
      await pumpBidding(tester);
      await answerPhase(tester, _localId);

      expect(find.text('a1'), findsOneWidget);

      await tester.tap(find.text('a1'));
      await tester.pump();

      final submissions = signalR.invocations
          .where((i) => i.method == PlayGameHubEvents.submitAnswer)
          .toList();
      expect(submissions, hasLength(1));
      expect(submissions.single.args, ['g1', 10]);
    });

    testWidgets('the watching player gets no chips at all', (tester) async {
      await pumpBidding(tester);
      await answerPhase(tester, _opponentId);

      expect(find.text('a1'), findsNothing);
      expect(find.text('a2'), findsNothing);
    });

    testWidgets('the goal is shown against the answering seat',
        (tester) async {
      await pumpBidding(tester);
      await answerPhase(tester, _localId);

      expect(find.text('0/3'), findsOneWidget);

      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {'playerId': _localId, 'currentScore': 2, 'goalScore': 3},
      );
      await tester.pump();

      expect(find.text('2/3'), findsOneWidget);
    });

    testWidgets('a tap moves no score on its own', (tester) async {
      await pumpBidding(tester);
      await answerPhase(tester, _localId);

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(find.text('0/3'), findsOneWidget,
          reason: 'the score waits for AuctionAnswerPhaseScoreUpdate');
    });
  });
}
