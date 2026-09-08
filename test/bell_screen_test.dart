import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/presentation/widgets/rounds/selectable_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Bell B-2 — wiring the existing Bell screen to the B-1 state/actions.
//
// RingBell is server-authoritative: tapping it must never locally declare a
// winner. SubmitAnswer reuses the generic GameController.submitAnswer, gated
// by the same isMyTurn identity check WDYK already relies on — this drives
// the real screen the way wdyk_answer_selection_test.dart does for WDYK.

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
}) =>
    {
      'id': id,
      'text': 'q$id',
      'textEn': 'q$id',
      'answers': answers,
    };

Map<String, dynamic> _bellGame({
  String currentTurn = '',
  bool? isTimerStarted,
  double? currentTimerValue,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 3,
      'groupId': 'grp',
      'currentTurn': currentTurn,
      if (isTimerStarted != null) 'isTimerStarted': isTimerStarted,
      if (currentTimerValue != null) 'currentTimerValue': currentTimerValue,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
      'currentQuestion': _questionJson(
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

  Future<void> pumpBell(
    WidgetTester tester, {
    String currentTurn = '',
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
        child: const MaterialApp(home: BellRoundScreen()),
      ),
    );
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _bellGame(currentTurn: currentTurn),
    );
    await tester.pump();
  }

  Future<void> timeStarted(WidgetTester tester) async {
    notifier().applySharedRoundEvent(PlayGameHubEvents.timeStarted, null);
    await tester.pump();
  }

  Future<void> changeTurn(WidgetTester tester, String playerId) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.changeTurn,
      {'arg0': playerId, 'arg1': 'g1'},
    );
    await tester.pump();
  }

  Future<void> timerSeconds(WidgetTester tester, num seconds) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.timerUpdatedSeconds,
      HubEventPayload.mapFromArgs([seconds, 'g1']),
    );
    await tester.pump();
  }

  group('Bell button', () {
    testWidgets('is hidden while idle', (tester) async {
      await pumpBell(tester);

      expect(find.text(strings.bellRoundTitle), findsNothing);
    });

    testWidgets('appears once armed with no turn', (tester) async {
      await pumpBell(tester);

      await timeStarted(tester);

      expect(find.text(strings.bellRoundTitle), findsOneWidget);
    });

    testWidgets('is hidden once a turn already exists', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      expect(find.text(strings.bellRoundTitle), findsOneWidget);

      await changeTurn(tester, _localId);

      expect(find.text(strings.bellRoundTitle), findsNothing);
    });

    testWidgets('is hidden again after an explicit race reset',
        (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      expect(find.text(strings.bellRoundTitle), findsOneWidget);

      await changeTurn(tester, '');

      expect(find.text(strings.bellRoundTitle), findsNothing,
          reason: 'idle again — waits for the next TimeStarted');
    });
  });

  group('RingBell', () {
    testWidgets('tapping it sends gameId and nothing else', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);

      await tester.tap(find.text(strings.bellRoundTitle));
      await tester.pump();

      final rung = signalR.invocations
          .where((i) => i.method == PlayGameHubEvents.ringBell)
          .toList();
      expect(rung, hasLength(1));
      expect(rung.single.args, ['g1']);
    });

    testWidgets('does not locally declare a winner or hide the Bell',
        (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);

      await tester.tap(find.text(strings.bellRoundTitle));
      await tester.pump();

      expect(current().game?.currentTurn ?? '', isEmpty,
          reason: 'only ChangeTurn may set a turn');
      expect(current().isMyTurn, isFalse);
      expect(find.text(strings.bellRoundTitle), findsOneWidget,
          reason: 'still up — the server has not answered yet');
    });
  });

  group('answer chips', () {
    testWidgets('the winner sees and can submit an answer', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await changeTurn(tester, _localId);
      await timerSeconds(tester, 30);
      expect(find.text('a1'), findsOneWidget);

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
      expect(signalR.submissions.single.args, ['g1', 10]);
    });

    testWidgets(
        'the losing player sees no chips and cannot submit', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await changeTurn(tester, _opponentId);
      await timerSeconds(tester, 30);

      expect(find.text('a1'), findsNothing);
      expect(find.text('a2'), findsNothing);
      expect(signalR.submissions, isEmpty);
    });

    testWidgets('nobody sees chips before a winner is named', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);

      expect(find.text('a1'), findsNothing);
      expect(find.text('a2'), findsNothing);
    });

    testWidgets('a repeated tap after submitting sends nothing more',
        (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await changeTurn(tester, _localId);
      await timerSeconds(tester, 30);

      await tester.tap(find.text('a1'));
      await tester.pump();
      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
    });

    testWidgets('NextQuestion clears the lock and accepts a new submission',
        (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await changeTurn(tester, _localId);
      await timerSeconds(tester, 30);
      await tester.tap(find.text('a1'));
      await tester.pump();
      expect(signalR.submissions, hasLength(1));

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.nextQuestion,
        _questionJson(
          id: 2,
          answers: [
            {'id': 20, 'text': 'b1', 'textEn': 'b1'},
          ],
        ),
      );
      await tester.pump();
      // The turn is unchanged by NextQuestion (as WDYK's own reducer already
      // behaves) — its own countdown is what reopens answering.
      await timerSeconds(tester, 30);

      expect(find.text('b1'), findsOneWidget);
      await tester.tap(find.text('b1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(2));
      expect(signalR.submissions.last.args, ['g1', 20]);
    });
  });

  group('B-4 — the answer container stays up', () {
    testWidgets('is present before a turn exists — chips are what hide',
        (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);

      expect(find.byType(SelectableChipsBox), findsOneWidget,
          reason: 'the container itself, same as the previous round');
      expect(find.text('a1'), findsNothing);
      expect(find.text('a2'), findsNothing);
    });

    testWidgets('is present while the opponent is answering', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await changeTurn(tester, _opponentId);
      await timerSeconds(tester, 30);

      expect(find.byType(SelectableChipsBox), findsOneWidget);
      expect(find.text('a1'), findsNothing);
    });

    testWidgets('is present once I am the answering player, now with chips',
        (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await changeTurn(tester, _localId);
      await timerSeconds(tester, 30);

      expect(find.byType(SelectableChipsBox), findsOneWidget);
      expect(find.text('a1'), findsOneWidget);
    });
  });

  group('B-4 — the Bell button during racing', () {
    testWidgets('is visible and clickable while currentTurn is null',
        (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);

      expect(current().game?.currentTurn ?? '', isEmpty);
      expect(find.text(strings.bellRoundTitle), findsOneWidget,
          reason: 'visible');

      await tester.tap(find.text(strings.bellRoundTitle));
      await tester.pump();

      final rung = signalR.invocations
          .where((i) => i.method == PlayGameHubEvents.ringBell)
          .toList();
      expect(rung, hasLength(1), reason: 'clickable — RingBell was sent');
    });
  });

  group('B-8 — the countdown survives a same-question NextQuestion repeat',
      () {
    testWidgets(
        'TimerUpdatedSeconds(10) starts the display, and it keeps ticking '
        'through a same-question repeat', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      expect(find.text('00:10'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:09'), findsOneWidget);

      // Same question (id:1, no questionNumber) — a progressive text reveal,
      // exactly as Bell resends it on a real device.
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.nextQuestion,
        _questionJson(
          id: 1,
          answers: [
            {'id': 10, 'text': 'a1', 'textEn': 'a1'},
            {'id': 11, 'text': 'a2', 'textEn': 'a2'},
          ],
        ),
      );
      await tester.pump();

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:08'), findsOneWidget,
          reason: 'the same-question repeat must not have stopped it');
    });

    testWidgets(
        'B-9: the countdown continues through a NEW question arriving after '
        'the timer started', (tester) async {
      // Real-device ordering: TimerUpdatedSeconds lands 5ms before the new
      // question's own NextQuestion — the running timer must survive it.
      await pumpBell(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      expect(find.text('00:10'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:09'), findsOneWidget);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.nextQuestion,
        _questionJson(
          id: 2,
          answers: [
            {'id': 20, 'text': 'b1', 'textEn': 'b1'},
          ],
        ),
      );
      await tester.pump();

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:08'), findsOneWidget,
          reason: 'the new question must not kill the running countdown');
    });

    testWidgets(
        'a new question with no running timer leaves the display untouched',
        (tester) async {
      await pumpBell(tester);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.nextQuestion,
        _questionJson(
          id: 2,
          answers: [
            {'id': 20, 'text': 'b1', 'textEn': 'b1'},
          ],
        ),
      );
      await tester.pump();

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:00'), findsOneWidget,
          reason: 'nothing started — it waits for its own '
              'TimeStarted/TimerUpdatedSeconds');
    });
  });

  group('B-10 — the race countdown freezes when a winner is named', () {
    testWidgets(
        'ChangeTurn freezes the display, and the next TimerUpdatedSeconds '
        'starts the answering countdown', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      expect(find.text('00:10'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:09'), findsOneWidget);

      await changeTurn(tester, _localId);
      // Inside CountdownTimerText.freezeResetDelay: still frozen in place.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('00:09'), findsOneWidget,
          reason: 'frozen the moment the winner was named');
      // UPDATED: past the delay the countdown is disposed and cleared.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:00'), findsOneWidget);

      await timerSeconds(tester, 8);
      expect(find.text('00:08'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:07'), findsOneWidget,
          reason: 'the answering countdown runs from the server value');
    });

    testWidgets('the opponent winning freezes it the same way',
        (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:09'), findsOneWidget);

      await changeTurn(tester, _opponentId);
      // Inside the reset window: still frozen.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('00:09'), findsOneWidget);
      // UPDATED: past it, cleared.
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('00:00'), findsOneWidget);
      expect(find.text(strings.bellRoundTitle), findsNothing,
          reason: 'Bell hidden once the race is decided');
    });
  });

  group('B-10 — GameRestore', () {
    Future<void> restore(
      WidgetTester tester, {
      String currentTurn = '',
      bool? isTimerStarted,
      double? currentTimerValue,
    }) async {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _bellGame(
          currentTurn: currentTurn,
          isTimerStarted: isTimerStarted,
          currentTimerValue: currentTimerValue,
        ),
      );
      await tester.pump();
    }

    testWidgets(
        'no turn + running countdown restores the race — Bell armed, timer '
        'running from the restored value, no TimeStarted needed',
        (tester) async {
      await pumpBell(tester);

      await restore(
        tester,
        isTimerStarted: true,
        currentTimerValue: 9.4628567,
      );

      expect(find.text(strings.bellRoundTitle), findsOneWidget,
          reason: 'Bell visible and armed straight from the snapshot');
      expect(notifier().canRingBell, isTrue);
      expect(find.text('00:09'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:08'), findsOneWidget,
          reason: 'ticking from the restored value');
    });

    testWidgets(
        'a turn in the snapshot restores answering — Bell hidden, chips '
        'available immediately from a genuinely active restored countdown '
        '(BUG-03)', (tester) async {
      await pumpBell(tester);

      await restore(
        tester,
        currentTurn: _localId,
        isTimerStarted: true,
        currentTimerValue: 5,
      );

      expect(find.text(strings.bellRoundTitle), findsNothing);
      expect(find.byType(SelectableChipsBox), findsOneWidget,
          reason: 'the answer area stays up');
      expect(find.text('a1'), findsOneWidget,
          reason: 'my turn + a genuinely active restored countdown unlocks '
              'answering immediately — no TimerUpdatedSeconds required');

      await timerSeconds(tester, 5);
      expect(find.text('a1'), findsOneWidget,
          reason: 'a later TimerUpdatedSeconds still applies normally');
    });

    testWidgets('a snapshot without a running countdown does not arm the '
        'Bell', (tester) async {
      await pumpBell(tester);

      await restore(tester, isTimerStarted: false, currentTimerValue: 9);

      expect(find.text(strings.bellRoundTitle), findsNothing);
      expect(notifier().canRingBell, isFalse);
    });
  });

  // The race countdown reaches the screen before a winner exists, so the
  // ordering the other chip groups use (ChangeTurn first, then the timer)
  // is not the live one. With the race timer running first, the winner's
  // chips used to appear on ChangeTurn itself — before the answering
  // countdown had started.
  group('chips wait for the answering countdown, not the race one', () {
    testWidgets('the race countdown alone shows nobody chips', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);

      await timerSeconds(tester, 10);

      expect(find.byType(SelectableChipsBox), findsOneWidget,
          reason: 'the container stays up, as it always has');
      expect(find.text('a1'), findsNothing);
      expect(find.text('a2'), findsNothing);
    });

    testWidgets('winning the race does not reveal them', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);

      await changeTurn(tester, _localId);

      expect(current().isMyTurn, isTrue, reason: 'I won the race');
      expect(find.text('a1'), findsNothing,
          reason: 'the answering countdown has not started yet');
      expect(find.text('a2'), findsNothing);
    });

    testWidgets('the answering countdown reveals them', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await changeTurn(tester, _localId);
      expect(find.text('a1'), findsNothing);

      await timerSeconds(tester, 30);

      expect(find.text('a1'), findsOneWidget);
      expect(find.text('a2'), findsOneWidget);
    });

    testWidgets('nothing can be submitted in the gap', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await changeTurn(tester, _localId);

      expect(find.text('a1'), findsNothing,
          reason: 'there is nothing to tap — the chips are not rendered');
      expect(signalR.submissions, isEmpty);
    });

    testWidgets('the losing player still sees none of it', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await changeTurn(tester, _opponentId);
      await timerSeconds(tester, 30);

      expect(find.byType(SelectableChipsBox), findsOneWidget);
      expect(find.text('a1'), findsNothing);
    });

    testWidgets('the winner can still answer once revealed', (tester) async {
      await pumpBell(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await changeTurn(tester, _localId);
      await timerSeconds(tester, 30);

      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1));
      expect(signalR.submissions.single.args, ['g1', 10]);
    });
  });
}
