import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/presentation/widgets/rounds/selectable_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Breaker (round 5) screen — confirmed to render via the exact same shared
// content widget as Comeback (ComebackStyleRoundContent), so this file only
// proves the two Breaker-specific differences (heading text, and that the
// shared mechanism activates for GamePhase.breaker) plus a compact repeat
// of the reused-behavior checks the task asks to prove explicitly.
// comeback_screen_test.dart is the full, unmodified coverage for the
// mechanism itself.

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

Map<String, dynamic> _questionJson({
  required int id,
  required List<Map<String, dynamic>> answers,
  String? text,
}) =>
    {
      'id': id,
      'text': text ?? 'q$id',
      'textEn': text ?? 'q$id',
      'answers': answers,
    };

Map<String, dynamic> _breakerGame({
  String currentTurn = '',
  int myTryCount = 0,
  int myMaxTryCount = 3,
  int opponentTryCount = 0,
  int opponentMaxTryCount = 3,
  Map<String, dynamic>? question,
  bool isTimerStarted = true,
  double currentTimerValue = 30,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 5, // GameType.breaker
      'groupId': 'grp',
      'currentTurn': currentTurn,
      'isTimerStarted': isTimerStarted,
      'currentTimerValue': currentTimerValue,
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'makeupTryCount': myTryCount,
          'maxMakeupTryCount': myMaxTryCount,
        },
        {
          'id': _opponentId,
          'playerName': 'them',
          'makeupTryCount': opponentTryCount,
          'maxMakeupTryCount': opponentMaxTryCount,
        },
      ],
      'currentQuestion': question ??
          _questionJson(
            id: 1,
            answers: [
              {'id': 10, 'text': 'a1', 'textEn': 'a1'},
              {'id': 11, 'text': 'a2', 'textEn': 'a2'},
            ],
          ),
    };

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;

  final strings = PlayGameStrings.forLanguage(AppLanguage.english);

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  Future<void> pumpBreaker(
    WidgetTester tester, {
    String currentTurn = '',
    int myTryCount = 0,
    int myMaxTryCount = 3,
    int opponentTryCount = 0,
    int opponentMaxTryCount = 3,
    Map<String, dynamic>? question,
    bool isTimerStarted = true,
    double currentTimerValue = 30,
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
        child: const MaterialApp(home: BreakerRoundScreen()),
      ),
    );
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _breakerGame(
        currentTurn: currentTurn,
        myTryCount: myTryCount,
        myMaxTryCount: myMaxTryCount,
        opponentTryCount: opponentTryCount,
        opponentMaxTryCount: opponentMaxTryCount,
        question: question,
        isTimerStarted: isTimerStarted,
        currentTimerValue: currentTimerValue,
      ),
    );
    await tester.pump();
  }

  Future<void> nextQuestion(
    WidgetTester tester,
    Map<String, dynamic> question,
  ) async {
    notifier().applySharedRoundEvent(PlayGameHubEvents.nextQuestion, question);
    await tester.pump();
  }

  Future<void> timeStarted(WidgetTester tester) async {
    notifier().applySharedRoundEvent(PlayGameHubEvents.timeStarted, null);
    await tester.pump();
  }

  Future<void> timerUpdatedSeconds(WidgetTester tester, num seconds) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.timerUpdatedSeconds,
      HubEventPayload.mapFromArgs([seconds, 'g1']),
    );
    await tester.pump();
  }

  Future<void> penalty(
    WidgetTester tester, {
    required String playerId,
    required int type,
  }) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.penalty,
      {'playerId': playerId, 'type': type},
    );
    await tester.pump();
  }

  group('the only Breaker-specific difference: the round heading', () {
    testWidgets('shows the Breaker heading, not the Comeback one',
        (tester) async {
      await pumpBreaker(tester);

      expect(find.text(strings.breakerRoundHeading), findsOneWidget);
      expect(find.text(strings.comeBackRoundHeading), findsNothing);
    });
  });

  group('both players can answer without currentTurn', () {
    testWidgets('both players see the chips regardless of currentTurn == me',
        (tester) async {
      await pumpBreaker(tester, currentTurn: _localId);

      expect(find.text('a1'), findsOneWidget);
      expect(find.text('a2'), findsOneWidget);
    });

    testWidgets(
        'currentTurn == opponent does not block my submission '
        '(tries available)', (tester) async {
      await pumpBreaker(
        tester,
        currentTurn: _opponentId,
        myTryCount: 0,
        myMaxTryCount: 3,
      );
      expect(current().isMyTurn, isFalse);

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
      expect(signalR.submissions.single.args, ['g1', 10]);
    });
  });

  group('attempt limit gating', () {
    testWidgets('my tries exhausted → chip tap submits nothing',
        (tester) async {
      await pumpBreaker(tester, myTryCount: 3, myMaxTryCount: 3);

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, isEmpty);
    });

    testWidgets('the answer container remains visible when attempts are '
        'exhausted', (tester) async {
      await pumpBreaker(tester, myTryCount: 3, myMaxTryCount: 3);

      expect(find.byType(SelectableChipsBox), findsOneWidget);
      expect(find.text('a1'), findsOneWidget);
    });

    testWidgets('the attempts row displays my live makeupTryCount/'
        'maxMakeupTryCount', (tester) async {
      await pumpBreaker(tester, myTryCount: 1, myMaxTryCount: 3);

      expect(find.text(strings.numberOfAttempts), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
    });
  });

  group('SubmitAnswer payload/guard', () {
    testWidgets('tapping an answer calls submitComebackAnswer with its id',
        (tester) async {
      await pumpBreaker(tester, myTryCount: 0, myMaxTryCount: 3);

      await tester.tap(find.text('a2'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
      expect(signalR.submissions.single.args, ['g1', 11]);
    });

    testWidgets('duplicate taps do not submit the same question twice',
        (tester) async {
      await pumpBreaker(tester, myTryCount: 0, myMaxTryCount: 3);

      await tester.tap(find.text('a1'));
      await tester.pump();
      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
    });
  });

  group('progressive NextQuestion (revealed on TimerUpdatedSeconds)', () {
    testWidgets('question/answers are hidden before TimerUpdatedSeconds',
        (tester) async {
      await pumpBreaker(tester, isTimerStarted: false, currentTimerValue: 0);

      expect(find.text('q1'), findsNothing);
      expect(find.text('a1'), findsNothing);
    });

    testWidgets(
        'NextQuestion renders exactly the just-received partial text, and '
        'later repeats update it progressively', (tester) async {
      await pumpBreaker(tester, isTimerStarted: false, currentTimerValue: 0);
      await timeStarted(tester);
      await timerUpdatedSeconds(tester, 30);

      await nextQuestion(
        tester,
        _questionJson(
          id: 1,
          text: 'لاعب',
          answers: [
            {'id': 10, 'text': 'a1', 'textEn': 'a1'},
          ],
        ),
      );
      expect(find.text('لاعب'), findsOneWidget);

      await nextQuestion(
        tester,
        _questionJson(
          id: 1,
          text: 'لاعب حالي',
          answers: [
            {'id': 10, 'text': 'a1', 'textEn': 'a1'},
          ],
        ),
      );
      expect(find.text('لاعب حالي'), findsOneWidget);
      expect(find.text('لاعب'), findsNothing);
    });

    testWidgets('a new question id replaces the previous question',
        (tester) async {
      await pumpBreaker(tester);

      await nextQuestion(
        tester,
        _questionJson(
          id: 2,
          answers: [
            {'id': 20, 'text': 'b1', 'textEn': 'b1'},
          ],
        ),
      );

      expect(find.text('q2'), findsOneWidget);
      expect(find.text('b1'), findsOneWidget);
      expect(find.text('a1'), findsNothing);
    });
  });

  group('CorrectAnswer', () {
    testWidgets('ends the question for both players — no further answering '
        'until the next question', (tester) async {
      await pumpBreaker(tester, myTryCount: 0, myMaxTryCount: 3);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.correctAnswer,
        {'arg2': _opponentId},
      );
      await tester.pump();

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, isEmpty);
    });
  });

  group('Penalty', () {
    testWidgets('type: 1 (timeout) locks answering, tries remaining or not',
        (tester) async {
      await pumpBreaker(tester, myTryCount: 0, myMaxTryCount: 3);

      await penalty(tester, playerId: _localId, type: 1);
      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, isEmpty);
    });

    testWidgets('type: 2 (wrong) does not lock answering', (tester) async {
      await pumpBreaker(tester, myTryCount: 0, myMaxTryCount: 3);

      await penalty(tester, playerId: _localId, type: 2);
      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
    });
  });

  group('timeout — Penalty(type: 1) does not freeze the timer either',
      () {
    testWidgets('the timer keeps running through a timeout', (tester) async {
      await pumpBreaker(tester);
      await timerUpdatedSeconds(tester, 10);

      await penalty(tester, playerId: _localId, type: 1);

      expect(current().game?.isTimerStarted, isTrue);
      expect(current().game?.currentTimerValue, 10);
    });
  });

  group('restore behavior', () {
    testWidgets(
        'restore with an already-running timer restores the visible '
        'question/answers', (tester) async {
      await pumpBreaker(tester, isTimerStarted: false, currentTimerValue: 0);
      expect(find.text('q1'), findsNothing);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _breakerGame(isTimerStarted: true, currentTimerValue: 9.46),
      );
      await tester.pump();

      expect(find.text('q1'), findsOneWidget);
      expect(find.text('a1'), findsOneWidget);
    });

    testWidgets(
        'CHARACTERIZATION (unresolved): a GameRestore that is the very '
        'first event a fresh screen instance ever sees cannot distinguish '
        'an already-resolved question from an active one — with tries '
        'still below max, the restored snapshot renders fully answerable '
        '(mirrors comeback_screen_test.dart\'s 6b — Breaker confirmed '
        'identical, same shared ComebackStyleRoundContent, same gap)',
        (tester) async {
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
          child: const MaterialApp(home: BreakerRoundScreen()),
        ),
      );
      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _breakerGame(
          myTryCount: 0,
          myMaxTryCount: 3,
          isTimerStarted: true,
          currentTimerValue: 9.46,
        ),
      );
      await tester.pump();
      expect(find.text('a1'), findsOneWidget, reason: 'sanity');

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(
        signalR.submissions,
        hasLength(1),
        reason: 'no repository-evidenced resolved-question field exists '
            '(see comeback_screen_test.dart 6b for the full inspection '
            'citation) — no production change was made for R-08',
      );
    });
  });
}
