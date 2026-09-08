import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A1 — WDYK answers are single-choice in 1v1, so one question accepts one
// SubmitAnswer. These drive the real screen because the guard lives in
// _WdykRoundScreenState, not in GameController.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  List<({String method, List<Object?>? args})> get submissions => invocations
      .where((i) => i.method == PlayGameHubEvents.submitAnswer)
      .toList();

  // Drives invoke()s return the way a real disconnected hub would.
  bool connected = true;

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

Map<String, dynamic> _questionJson({
  required int id,
  required List<Map<String, dynamic>> answers,
}) =>
    {
      'id': id,
      'text': 'q$id',
      'textEn': 'q$id',
      'questionNumber': id,
      'roundTotalQuestionsCount': 5,
      'answers': answers,
    };

Map<String, dynamic> _roundJson({
  String currentTurn = _localId,
  int questionId = 1,
  List<Map<String, dynamic>>? answers,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 1,
      'groupId': 'grp',
      'currentTurn': currentTurn,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
      'currentQuestion': _questionJson(
        id: questionId,
        answers: answers ??
            [
              {'id': 10, 'text': 'a1', 'textEn': 'a1'},
              {'id': 11, 'text': 'a2', 'textEn': 'a2'},
            ],
      ),
    };

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  Future<void> pumpRound(
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

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WdykRoundScreen()),
      ),
    );
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _roundJson(currentTurn: currentTurn),
    );
    await tester.pump();
    // Answering opens only once a countdown is running (shared rule).
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.timerUpdatedSeconds,
      HubEventPayload.mapFromArgs([30, 'g1']),
    );
    await tester.pump();
  }

  testWidgets('the first selection submits exactly once', (tester) async {
    await pumpRound(tester);
    expect(find.text('a1'), findsOneWidget);

    await tester.tap(find.text('a1'));
    await tester.pump();

    expect(signalR.submissions, hasLength(1));
    expect(signalR.submissions.single.args, ['g1', 10]);
  });

  testWidgets('a repeated tap on the same answer submits nothing more',
      (tester) async {
    await pumpRound(tester);
    await tester.tap(find.text('a1'));
    await tester.pump();
    await tester.tap(find.text('a1'));
    await tester.pump();

    expect(signalR.submissions, hasLength(1));
  });

  testWidgets('a different answer on the same question submits nothing more',
      (tester) async {
    await pumpRound(tester);
    await tester.tap(find.text('a1'));
    await tester.pump();
    await tester.tap(find.text('a2'));
    await tester.pump();

    expect(signalR.submissions, hasLength(1));
    expect(signalR.submissions.single.args, ['g1', 10]);
  });

  testWidgets('a new question accepts a submission again', (tester) async {
    await pumpRound(tester);
    await tester.tap(find.text('a1'));
    await tester.pump();
    expect(signalR.submissions, hasLength(1));

    notifier().applySharedRoundEvent(
      PlayGameHubEvents.nextQuestion,
      _questionJson(
        id: 2,
        answers: [
          {'id': 20, 'text': 'b1', 'textEn': 'b1'},
          {'id': 21, 'text': 'b2', 'textEn': 'b2'},
        ],
      ),
    );
    await tester.pump();

    // A new question arrives locked; its own countdown opens it.
    expect(find.text('b1'), findsNothing);
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.timerUpdatedSeconds,
      HubEventPayload.mapFromArgs([30, 'g1']),
    );
    await tester.pump();

    await tester.tap(find.text('b1'));
    await tester.pump();

    expect(signalR.submissions, hasLength(2));
    expect(signalR.submissions.last.args, ['g1', 20]);
  });

  testWidgets('no answers are offered while it is the opponent turn',
      (tester) async {
    await pumpRound(tester, currentTurn: _opponentId);

    expect(find.text('a1'), findsNothing);
    expect(find.text('a2'), findsNothing);
    expect(signalR.submissions, isEmpty);
  });

  testWidgets('losing the turn withdraws the answers', (tester) async {
    await pumpRound(tester);
    expect(find.text('a1'), findsOneWidget);

    notifier().applySharedRoundEvent(
      PlayGameHubEvents.changeTurn,
      {'playerId': _opponentId},
    );
    await tester.pump();

    expect(find.text('a1'), findsNothing);
    expect(signalR.submissions, isEmpty);
  });

  // W-ACTION: a dispatch that never left must not leave the answer locked.
  group('a failed dispatch releases the answer guard', () {
    testWidgets('the chip can be tapped again after a failed submit',
        (tester) async {
      await pumpRound(tester);
      signalR.connected = false;

      await tester.tap(find.text('a1'));
      await tester.pump();
      expect(signalR.submissions, isEmpty, reason: 'nothing dispatched');

      signalR.connected = true;
      await tester.tap(find.text('a1'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1),
          reason: 'the guard was released, so the retry went out');
    });

    testWidgets('a failed submit leaves a running timer running',
        (tester) async {
      await pumpRound(tester);

      // A real countdown first: TimeStarted arms the timer and
      // TimerUpdatedSeconds is the only thing that sets it running.
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.timeStarted,
        HubEventPayload.mapFromArgs(['', 'g1']),
      );
      await tester.pump();
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('00:07'), findsOneWidget, reason: 'the timer is live');

      signalR.connected = false;
      await tester.tap(find.text('a1'));
      await tester.pump();
      expect(signalR.submissions, isEmpty, reason: 'nothing dispatched');

      final game = container.read(gameControllerProvider).game;
      expect(game?.isTimerStarted, isTrue,
          reason: 'a dispatch that never left must not stop the timer');
      expect(game?.currentTimerValue, 10,
          reason: 'and must not rewrite the seconds the server gave');
      expect(find.text('00:07'), findsOneWidget,
          reason: 'no restart — the countdown carries on where it was');

      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('00:03'), findsOneWidget,
          reason: 'the countdown is still advancing');
    });

    testWidgets('a successful submit keeps the guard closed', (tester) async {
      await pumpRound(tester);

      await tester.tap(find.text('a1'));
      await tester.pump();
      await tester.tap(find.text('a2'));
      await tester.pump();

      expect(signalR.submissions, hasLength(1),
          reason: 'guard held until a server event releases it');
    });
  });
}
