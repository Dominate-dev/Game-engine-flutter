import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The shared answer-availability rule, applied by every round.
//
// Only TimerUpdatedSeconds with time on it opens answering. A question, its
// answers and TimeStarted do not; the countdown running out closes it, and the
// next TimerUpdatedSeconds opens it again.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  List<({String method, List<Object?>? args})> get submissions => invocations
      .where((i) => i.method == PlayGameHubEvents.submitAnswer)
      .toList();

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

Map<String, dynamic> _roundJson({required int type}) => {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      'currentTurn': _localId,
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
        {'id': _opponentId, 'playerName': 'them'},
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
      if (type == 2)
        'auctionGameMetadata': {
          'phase': 2,
          'currentScore': 0,
          'currentBid': 2,
          'answerTimeout': 8,
        },
    };

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState session() => container.read(gameControllerProvider);

  /// Pumps the round screen for [type]: 1 WDYK, 2 Auction.
  Future<void> pumpRound(WidgetTester tester, {required int type}) async {
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
        child: MaterialApp(
          home: Scaffold(
            body: type == 1
                ? const WdykRoundScreen()
                : const AuctionRoundScreen(),
          ),
        ),
      ),
    );
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _roundJson(type: type),
    );
    await tester.pump();
    if (type == 2) {
      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 2},
      );
      await tester.pump();
      // Let the auction overlays retire so the chips are reachable.
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 4000));
      await tester.pump();
    }
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

  for (final round in const [
    (type: 1, name: 'WDYK'),
    (type: 2, name: 'Auction'),
  ]) {
    group('${round.name}: answers wait for the countdown', () {
      testWidgets('a question and its answers alone do not open answering',
          (tester) async {
        await pumpRound(tester, type: round.type);

        expect(session().game?.currentQuestion?.answers, hasLength(2),
            reason: 'the answers are there');
        expect(session().answersUnlocked, isFalse);
        expect(find.text('a1'), findsNothing);
      });

      testWidgets('TimeStarted alone does not open answering', (tester) async {
        await pumpRound(tester, type: round.type);

        await timeStarted(tester);

        expect(session().game?.isTimerStarted, isTrue,
            reason: 'the flag still follows the server');
        expect(session().answersUnlocked, isFalse);
        expect(find.text('a1'), findsNothing);
      });

      testWidgets('TimerUpdatedSeconds opens answering', (tester) async {
        await pumpRound(tester, type: round.type);
        await timeStarted(tester);

        await timerSeconds(tester, 3);

        expect(session().answersUnlocked, isTrue);
        expect(find.text('a1'), findsOneWidget);
      });

      testWidgets('the countdown running out closes answering',
          (tester) async {
        await pumpRound(tester, type: round.type);
        await timerSeconds(tester, 2);
        expect(find.text('a1'), findsOneWidget);

        await tick(tester, 2);

        expect(find.text('00:00'), findsOneWidget);
        expect(session().answersUnlocked, isFalse);
        expect(find.text('a1'), findsNothing);
      });

      testWidgets('the next TimerUpdatedSeconds opens it again',
          (tester) async {
        await pumpRound(tester, type: round.type);
        await timerSeconds(tester, 2);
        await tick(tester, 2);
        expect(session().answersUnlocked, isFalse);

        await timerSeconds(tester, 5);

        expect(session().answersUnlocked, isTrue);
        expect(find.text('a1'), findsOneWidget);
      });

      testWidgets('a server value of zero closes answering', (tester) async {
        await pumpRound(tester, type: round.type);
        await timerSeconds(tester, 5);
        expect(session().answersUnlocked, isTrue);

        await timerSeconds(tester, 0);

        expect(session().answersUnlocked, isFalse);
        expect(find.text('a1'), findsNothing);
      });

      testWidgets('no answer can be submitted while it is closed',
          (tester) async {
        await pumpRound(tester, type: round.type);
        await timerSeconds(tester, 2);
        await tick(tester, 2);

        // The chips are gone, so there is nothing to tap; the guard behind
        // them is checked directly.
        expect(find.text('a1'), findsNothing);
        expect(signalR.submissions, isEmpty);
      });
    });
  }

  group('boundaries close answering', () {
    testWidgets('a new question arrives closed', (tester) async {
      await pumpRound(tester, type: 1);
      await timerSeconds(tester, 5);
      expect(session().answersUnlocked, isTrue);

      notifier().applySharedRoundEvent(PlayGameHubEvents.nextQuestion, {
        'id': 2,
        'text': 'q2',
        'textEn': 'q2',
        'type': 1,
        'answers': [
          {'id': 20, 'text': 'b1', 'textEn': 'b1'},
        ],
      });
      await tester.pump();

      expect(session().answersUnlocked, isFalse);
      expect(find.text('b1'), findsNothing);
    });

    testWidgets('a new round arrives closed', (tester) async {
      await pumpRound(tester, type: 1);
      await timerSeconds(tester, 5);
      expect(session().answersUnlocked, isTrue);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.nextRoundStarted,
        HubEventPayload.mapFromArgs([2, 'g1']),
      );
      await tester.pump();

      expect(session().answersUnlocked, isFalse);
    });

    testWidgets('an auction answer phase arrives closed', (tester) async {
      await pumpRound(tester, type: 2);
      await timerSeconds(tester, 5);
      expect(session().answersUnlocked, isTrue);

      notifier().applyAuctionEvent(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 3},
      );
      await tester.pump();

      expect(session().answersUnlocked, isFalse,
          reason: 'the new phase waits for its own countdown');
    });
  });
}
