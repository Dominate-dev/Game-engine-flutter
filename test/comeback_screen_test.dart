import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/presentation/widgets/rounds/selectable_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Comeback C-3 — live screen wiring.
//
// Both players can answer concurrently: currentTurn/isMyTurn/isOpponentTurn
// must never gate the answer chips. The only answering gate is each
// player's own makeupTryCount/maxMakeupTryCount, read live off the roster —
// never a locally maintained counter.

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

Map<String, dynamic> _comebackGame({
  String currentTurn = '',
  int myTryCount = 0,
  int myMaxTryCount = 3,
  int opponentTryCount = 0,
  int opponentMaxTryCount = 3,
  Map<String, dynamic>? question,
  // C-4.3: nonzero by default so every pre-existing test here — none of
  // which are about the start flow itself — keeps behaving as "a round
  // already past its first TimerUpdatedSeconds", the same scenario
  // initState's own immediate-reveal branch is for. The dedicated
  // start-flow tests below pass 0 (and isTimerStarted: false) explicitly.
  bool isTimerStarted = true,
  double currentTimerValue = 30,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 4,
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

  Future<void> pumpComeback(
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
        child: const MaterialApp(home: ComeBackRoundScreen()),
      ),
    );
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _comebackGame(
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

  Future<void> gameUpdated(
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
    notifier().applySessionEvent(
      PlayGameHubEvents.gameUpdated,
      _comebackGame(
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

  group('C-4.3 — question/answers reveal only on TimerUpdatedSeconds', () {
    testWidgets(
        '1. GameUpdated delivering the question before TimerUpdatedSeconds '
        'does not reveal it', (tester) async {
      await pumpComeback(
        tester,
        isTimerStarted: false,
        currentTimerValue: 0,
      );

      expect(find.text('q1'), findsNothing);
      expect(find.text('a1'), findsNothing);
      expect(find.text('a2'), findsNothing);
    });

    testWidgets(
        '2. TimeStarted shows the Start Timer dialog wiring but does not '
        'reveal the answers, even after its 2000ms would have elapsed',
        (tester) async {
      await pumpComeback(
        tester,
        isTimerStarted: false,
        currentTimerValue: 0,
      );

      await timeStarted(tester);
      expect(find.text('q1'), findsNothing);

      // TimeStarted's own overlay is 2000ms — waiting it out must not
      // reveal anything; only TimerUpdatedSeconds may.
      await tester.pump(const Duration(milliseconds: 2500));
      expect(find.text('q1'), findsNothing,
          reason: 'no TimerUpdatedSeconds arrived yet');
    });

    testWidgets(
        '3. TimerUpdatedSeconds alone reveals the container but does not '
        'invent/show the full GameUpdated question', (tester) async {
      await pumpComeback(
        tester,
        isTimerStarted: false,
        currentTimerValue: 0,
      );
      await timeStarted(tester);
      expect(find.text('q1'), findsNothing);

      await timerUpdatedSeconds(tester, 30);

      // Revealed, but empty — GameUpdated's own 'q1'/'a1'/'a2' must never
      // be the source; only a NextQuestion supplies content.
      expect(find.text('q1'), findsNothing);
      expect(find.text('a1'), findsNothing);
      expect(find.byType(SelectableChipsBox), findsOneWidget);
    });

    testWidgets(
        'NextQuestion with partial text renders exactly that text — the '
        'first progressive reveal', (tester) async {
      await pumpComeback(
        tester,
        isTimerStarted: false,
        currentTimerValue: 0,
      );
      await timeStarted(tester);
      await timerUpdatedSeconds(tester, 30);

      await nextQuestion(
        tester,
        _questionJson(id: 1, text: 'لاعب', answers: const [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ]),
      );

      expect(find.text('لاعب'), findsOneWidget);
      expect(find.text('q1'), findsNothing,
          reason: 'never the full GameUpdated text');
    });

    testWidgets(
        'a further NextQuestion for the same id updates the text to the '
        'newly received partial text', (tester) async {
      await pumpComeback(
        tester,
        isTimerStarted: false,
        currentTimerValue: 0,
      );
      await timeStarted(tester);
      await timerUpdatedSeconds(tester, 30);
      await nextQuestion(
        tester,
        _questionJson(id: 1, text: 'لاعب', answers: const [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ]),
      );
      expect(find.text('لاعب'), findsOneWidget);

      await nextQuestion(
        tester,
        _questionJson(id: 1, text: 'لاعب حالي', answers: const [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ]),
      );

      expect(find.text('لاعب حالي'), findsOneWidget);
      expect(find.text('لاعب'), findsNothing);
    });

    testWidgets(
        'repeated NextQuestion events continue updating the same question '
        'progressively, matching the server exactly', (tester) async {
      await pumpComeback(
        tester,
        isTimerStarted: false,
        currentTimerValue: 0,
      );
      await timeStarted(tester);
      await timerUpdatedSeconds(tester, 30);

      const progression = [
        'لاعب',
        'لاعب حالي',
        'لاعب حالي بدأ',
        'لاعب حالي بدأ مسيرته',
        'لاعب حالي بدأ مسيرته في',
      ];
      for (final text in progression) {
        await nextQuestion(
          tester,
          _questionJson(id: 1, text: text, answers: const [
            {'id': 10, 'text': 'a1', 'textEn': 'a1'},
          ]),
        );
        expect(find.text(text), findsOneWidget,
            reason: 'renders exactly the just-received server text');
      }
    });

    testWidgets(
        'the answers stay available throughout the progressive reveal',
        (tester) async {
      await pumpComeback(
        tester,
        myTryCount: 0,
        myMaxTryCount: 3,
        isTimerStarted: false,
        currentTimerValue: 0,
      );
      await timeStarted(tester);
      await timerUpdatedSeconds(tester, 30);
      await nextQuestion(
        tester,
        _questionJson(id: 1, text: 'لاعب', answers: const [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ]),
      );
      expect(find.text('a1'), findsOneWidget);

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
      expect(signalR.submissions.single.args, ['g1', 10]);
    });

    testWidgets(
        '5. attempts exhausted still prevents answering after the '
        'progressive reveal', (tester) async {
      await pumpComeback(
        tester,
        myTryCount: 3,
        myMaxTryCount: 3,
        isTimerStarted: false,
        currentTimerValue: 0,
      );
      await timeStarted(tester);
      await timerUpdatedSeconds(tester, 30);
      await nextQuestion(
        tester,
        _questionJson(id: 1, text: 'لاعب', answers: const [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ]),
      );
      expect(find.text('a1'), findsOneWidget,
          reason: 'revealed — only submission is gated by tries');

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, isEmpty);
    });

    testWidgets(
        '6. restore with an already-running timer restores the visible '
        'question/answers', (tester) async {
      await pumpComeback(
        tester,
        isTimerStarted: false,
        currentTimerValue: 0,
      );
      expect(find.text('q1'), findsNothing);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _comebackGame(isTimerStarted: true, currentTimerValue: 9.46),
      );
      await tester.pump();

      expect(find.text('q1'), findsOneWidget,
          reason: 'no NextQuestion history after a restore — the snapshot '
              'itself is what is shown');
      expect(find.text('a1'), findsOneWidget);
    });

    testWidgets(
        '6b. CHARACTERIZATION (unresolved): a GameRestore that is the '
        'very first event a fresh screen instance ever sees cannot '
        'distinguish an already-resolved question from an active one — '
        'with tries still below max, the restored snapshot renders fully '
        'answerable', (tester) async {
      // A standalone fresh mount (not pumpComeback's GameStarted-first
      // flow): GameRestore is the FIRST event this ComeBackRoundScreen
      // instance ever observes, matching a real disconnect-before-connect
      // reconnect — not a live reconnect while the same widget instance
      // (and its own already-set _questionResolved, if any) is still
      // mounted, which is unaffected by this gap.
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
          child: const MaterialApp(home: ComeBackRoundScreen()),
        ),
      );
      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _comebackGame(
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
        reason: 'R-08 inspection findings: neither CreatedGameModel.merge, '
            'GamePlayer, nor CurrentQuestion (grepped in full) carry any '
            'resolved-question field, and the native reference\'s own '
            'restore contract (comeback-round-workflow.md, section I / '
            'test matrix row 9) is documented as exactly "Same tries + '
            'question" — no resolved flag either. _questionResolved '
            '(comeback_style_round_content.dart) is local widget state, '
            'set only by a *live* CorrectAnswer, and correctly starts '
            'false on a fresh mount since there is no restorable '
            'equivalent. With tries still below max (also correctly '
            'server-driven — see the sibling test above with tries at '
            'max), this client has no information proving the question '
            'was already resolved before the disconnect, so the chip '
            'renders tappable and the tap is dispatched. The server '
            'remains authoritative over submitAnswer regardless — this '
            'does not fabricate a false correct/incorrect result locally, '
            'and no repository-evidenced field exists to distinguish this '
            'case, so no production change was made for R-08.',
      );
    });

    testWidgets(
        '7. both players can see and answer regardless of currentTurn',
        (tester) async {
      await pumpComeback(
        tester,
        currentTurn: _opponentId,
        myTryCount: 0,
        myMaxTryCount: 3,
        isTimerStarted: false,
        currentTimerValue: 0,
      );
      await timeStarted(tester);
      await timerUpdatedSeconds(tester, 30);
      await nextQuestion(
        tester,
        _questionJson(id: 1, text: 'لاعب', answers: const [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ]),
      );
      expect(current().isMyTurn, isFalse);

      expect(find.text('a1'), findsOneWidget);
      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
    });

    testWidgets(
        'a repeated TimeStarted before TimerUpdatedSeconds still does not '
        'reveal anything', (tester) async {
      await pumpComeback(
        tester,
        isTimerStarted: false,
        currentTimerValue: 0,
      );

      await timeStarted(tester);
      await timeStarted(tester);
      await tester.pump(const Duration(milliseconds: 3000));

      expect(find.text('q1'), findsNothing);
    });

    testWidgets(
        'a same-question NextQuestion repeat does not hide an '
        'already-revealed question', (tester) async {
      await pumpComeback(tester); // nonzero currentTimerValue — visible
      expect(find.text('q1'), findsOneWidget);

      await nextQuestion(
        tester,
        _questionJson(
          id: 1,
          answers: [
            {'id': 10, 'text': 'a1', 'textEn': 'a1'},
            {'id': 11, 'text': 'a2', 'textEn': 'a2'},
          ],
        ),
      );

      expect(find.text('q1'), findsOneWidget,
          reason: 'still visible — a repeat must not hide it');
    });

    testWidgets('7b. a new question id replaces the previous question',
        (tester) async {
      await pumpComeback(
        tester,
        isTimerStarted: false,
        currentTimerValue: 0,
      );
      await timeStarted(tester);
      await timerUpdatedSeconds(tester, 30);
      await nextQuestion(
        tester,
        _questionJson(id: 1, text: 'لاعب حالي بدأ', answers: const [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ]),
      );
      expect(find.text('لاعب حالي بدأ'), findsOneWidget);

      await nextQuestion(
        tester,
        _questionJson(id: 2, text: 'سؤال جديد', answers: const [
          {'id': 20, 'text': 'b1', 'textEn': 'b1'},
        ]),
      );

      expect(find.text('سؤال جديد'), findsOneWidget);
      expect(find.text('لاعب حالي بدأ'), findsNothing);
      expect(find.text('b1'), findsOneWidget);
      expect(find.text('a1'), findsNothing);
    });
  });

  group('timeout locks answering', () {
    testWidgets('a tap after Penalty(type: 1) cannot dispatch SubmitAnswer',
        (tester) async {
      await pumpComeback(tester, myTryCount: 0, myMaxTryCount: 3);

      await penalty(tester, playerId: _localId, type: 1);
      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, isEmpty);
    });

    testWidgets('the lock outlives the dialog\'s 1500ms duration',
        (tester) async {
      await pumpComeback(tester, myTryCount: 0, myMaxTryCount: 3);

      await penalty(tester, playerId: _localId, type: 1);
      await tester.pump(const Duration(milliseconds: 2000));

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, isEmpty,
          reason: 'still locked — only a genuine new question reopens it');
    });

    testWidgets('a genuine new question reopens answering when tries remain',
        (tester) async {
      await pumpComeback(tester, myTryCount: 0, myMaxTryCount: 3);
      await penalty(tester, playerId: _localId, type: 1);

      await nextQuestion(
        tester,
        _questionJson(
          id: 2,
          answers: [
            {'id': 20, 'text': 'b1', 'textEn': 'b1'},
          ],
        ),
      );

      await tester.tap(find.text('b1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
    });

    testWidgets('Penalty(type: 2, wrong) does not lock answering',
        (tester) async {
      await pumpComeback(tester, myTryCount: 0, myMaxTryCount: 3);

      await penalty(tester, playerId: _localId, type: 2);
      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
    });
  });

  group('question', () {
    testWidgets('renders from the live game state', (tester) async {
      await pumpComeback(tester);

      expect(find.text('q1'), findsOneWidget);
    });
  });

  group('answer chips — always visible to both players', () {
    testWidgets('both players see the chips regardless of currentTurn == me',
        (tester) async {
      await pumpComeback(tester, currentTurn: _localId);

      expect(find.text('a1'), findsOneWidget);
      expect(find.text('a2'), findsOneWidget);
    });

    testWidgets('chips stay visible when currentTurn == opponent',
        (tester) async {
      await pumpComeback(tester, currentTurn: _opponentId);

      expect(find.text('a1'), findsOneWidget);
      expect(find.text('a2'), findsOneWidget);
    });

    testWidgets(
        'currentTurn == opponent does not block my submission '
        '(tries available)', (tester) async {
      await pumpComeback(
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

  group('eligibility — tries, never turn', () {
    testWidgets('my tries available → chip tap submits', (tester) async {
      await pumpComeback(tester, myTryCount: 1, myMaxTryCount: 3);

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
    });

    testWidgets('my tries exhausted → chip tap submits nothing',
        (tester) async {
      await pumpComeback(tester, myTryCount: 3, myMaxTryCount: 3);

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, isEmpty);
    });

    testWidgets(
        'the opponent exhausting their tries does not disable mine',
        (tester) async {
      await pumpComeback(
        tester,
        myTryCount: 0,
        myMaxTryCount: 3,
        opponentTryCount: 3,
        opponentMaxTryCount: 3,
      );

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
    });
  });

  group('attempts row', () {
    testWidgets('displays my live makeupTryCount/maxMakeupTryCount',
        (tester) async {
      await pumpComeback(tester, myTryCount: 1, myMaxTryCount: 3);

      expect(find.text(strings.numberOfAttempts), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);
    });

    testWidgets('a later GameUpdated moves the count with no local counter',
        (tester) async {
      await pumpComeback(tester, myTryCount: 0, myMaxTryCount: 3);
      expect(find.text('0/3'), findsOneWidget);

      await gameUpdated(tester, myTryCount: 1, myMaxTryCount: 3);

      expect(find.text('1/3'), findsOneWidget);
      expect(find.text('0/3'), findsNothing);
    });
  });

  group('submission', () {
    testWidgets('tapping an answer calls submitComebackAnswer with its id',
        (tester) async {
      await pumpComeback(tester, myTryCount: 0, myMaxTryCount: 3);

      await tester.tap(find.text('a2'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
      expect(signalR.submissions.single.args, ['g1', 11]);
    });

    testWidgets('duplicate taps do not submit the same question twice',
        (tester) async {
      await pumpComeback(tester, myTryCount: 0, myMaxTryCount: 3);

      await tester.tap(find.text('a1'));
      await tester.pump();
      await tester.tap(find.text('a1'));
      await tester.pump();
      await tester.tap(find.text('a2'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
    });
  });

  group('the answer container', () {
    testWidgets('remains visible when my attempts are exhausted',
        (tester) async {
      await pumpComeback(tester, myTryCount: 3, myMaxTryCount: 3);

      expect(find.byType(SelectableChipsBox), findsOneWidget);
      expect(find.text('a1'), findsOneWidget);
      expect(find.text('a2'), findsOneWidget);
    });
  });

  group('CorrectAnswer ends the question for both players', () {
    testWidgets(
        'blocks a tap until the next question, even for a player who never '
        'answered', (tester) async {
      await pumpComeback(tester, myTryCount: 0, myMaxTryCount: 3);

      // The opponent answered correctly — the question is over for both.
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.correctAnswer,
        {'arg2': _opponentId},
      );
      await tester.pump();

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, isEmpty);
    });

    testWidgets('a new question reopens answering', (tester) async {
      await pumpComeback(tester, myTryCount: 0, myMaxTryCount: 3);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.correctAnswer,
        {'arg2': _opponentId},
      );
      await tester.pump();

      await nextQuestion(
        tester,
        _questionJson(
          id: 2,
          answers: [
            {'id': 20, 'text': 'b1', 'textEn': 'b1'},
          ],
        ),
      );

      await tester.tap(find.text('b1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
    });
  });

  group('local lock reset', () {
    testWidgets('a new question resets the local selection lock',
        (tester) async {
      await pumpComeback(tester, myTryCount: 0, myMaxTryCount: 3);

      await tester.tap(find.text('a1'));
      await tester.pump();
      expect(signalR.submissions, hasLength(1));

      await nextQuestion(
        tester,
        _questionJson(
          id: 2,
          answers: [
            {'id': 20, 'text': 'b1', 'textEn': 'b1'},
          ],
        ),
      );

      await tester.tap(find.text('b1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(2));
      expect(signalR.submissions.last.args, ['g1', 20]);
    });

    testWidgets(
        'a fresh try count on the same question after a wrong answer '
        'reopens the lock', (tester) async {
      await pumpComeback(tester, myTryCount: 0, myMaxTryCount: 3);

      await tester.tap(find.text('a1'));
      await tester.pump();
      expect(signalR.submissions, hasLength(1));

      // Same question, tries moved — the server's own evidence of a new
      // opportunity after a wrong answer.
      await gameUpdated(tester, myTryCount: 1, myMaxTryCount: 3);

      await tester.tap(find.text('a2'));
      await tester.pump();

      expect(signalR.submissions, hasLength(2));
      expect(signalR.submissions.last.args, ['g1', 11]);
    });
  });
}
