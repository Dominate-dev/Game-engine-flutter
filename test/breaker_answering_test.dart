import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Breaker (round 5) — confirmed to share Comeback's exact eligibility,
// submission and restore behavior (native: "almost the same screen"). This
// file proves the same GameController mechanism (canSubmitComebackAnswer /
// submitComebackAnswer / comebackAnswerLocked) activates correctly for
// GamePhase.breaker — it does not re-derive Comeback's own coverage, which
// stays in comeback_answering_test.dart, unmodified.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];
  bool connected = true;

  List<({String method, List<Object?>? args})> get submissions => invocations
      .where((i) => i.method == PlayGameHubEvents.submitAnswer)
      .toList();

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

  void emit(String name, Map<String, dynamic>? data) {
    _events.add(GameHubEvent(name: name, data: data));
  }

  @override
  void bindAll() {}

  @override
  void bindEvents(Iterable<String> eventNames) {}

  @override
  void dispose() {
    _events.close();
  }
}

Map<String, dynamic> _breakerGame({
  String currentTurn = '',
  int myTryCount = 0,
  int myMaxTryCount = 3,
  int opponentTryCount = 0,
  int opponentMaxTryCount = 3,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 5, // GameType.breaker
      'groupId': 'grp',
      'currentTurn': currentTurn,
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
      'currentQuestion': {
        'id': 1,
        'text': 'q',
        'textEn': 'q',
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
    };

void main() {
  late ProviderContainer container;
  late _FakeHubBindings bindings;
  late _FakeSignalRService signalR;

  Future<void> setUpContainer() async {
    SharedPreferences.setMockInitialValues({'user_id': _localId});
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    bindings = _FakeHubBindings(signalR);
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider.overrideWithValue(bindings),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(sub.close);
  }

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  setUp(() async => setUpContainer());

  Future<void> enterBreaker({
    String currentTurn = '',
    int myTryCount = 0,
    int myMaxTryCount = 3,
    int opponentTryCount = 0,
    int opponentMaxTryCount = 3,
  }) async {
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _breakerGame(
        currentTurn: currentTurn,
        myTryCount: myTryCount,
        myMaxTryCount: myMaxTryCount,
        opponentTryCount: opponentTryCount,
        opponentMaxTryCount: opponentMaxTryCount,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> emit(String name, Map<String, dynamic>? data) async {
    bindings.emit(name, data);
    await Future<void>.delayed(Duration.zero);
  }

  test('GameStarted(type: 5) routes to GamePhase.breaker', () async {
    await enterBreaker();
    expect(current().phase, GamePhase.breaker);
  });

  group('eligibility — tries, never turn', () {
    test('my tries available → can submit', () async {
      await enterBreaker(myTryCount: 1, myMaxTryCount: 3);
      expect(notifier().canSubmitComebackAnswer, isTrue);
    });

    test('my tries exhausted → cannot submit', () async {
      await enterBreaker(myTryCount: 3, myMaxTryCount: 3);
      expect(notifier().canSubmitComebackAnswer, isFalse);
    });

    test("my eligibility is independent of the opponent's tries", () async {
      await enterBreaker(
        myTryCount: 0,
        myMaxTryCount: 3,
        opponentTryCount: 3,
        opponentMaxTryCount: 3,
      );
      expect(notifier().canSubmitComebackAnswer, isTrue);
    });

    test('currentTurn naming the opponent does not block my submission',
        () async {
      await enterBreaker(currentTurn: _opponentId, myTryCount: 0);

      expect(current().isMyTurn, isFalse);
      expect(notifier().canSubmitComebackAnswer, isTrue,
          reason: 'Breaker has no turn gate — tries are the only gate, '
              'confirmed identical to Comeback');
    });

    test('a later GameUpdated reflects the server tryCount with no local '
        'counter', () async {
      await enterBreaker(myTryCount: 0, myMaxTryCount: 3);
      expect(notifier().canSubmitComebackAnswer, isTrue);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _breakerGame(myTryCount: 3, myMaxTryCount: 3),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().me?.makeupTryCount, 3);
      expect(notifier().canSubmitComebackAnswer, isFalse);
    });

    test('a Comeback phase does not accidentally grant Breaker eligibility '
        'and vice versa is not required to conflict', () async {
      // Sanity: canSubmitComebackAnswer only ever activates for the phase
      // actually reduced into state — not some other unrelated phase.
      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        {..._breakerGame(myTryCount: 0), 'type': 3}, // Bell
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().phase, isNot(GamePhase.breaker));
      expect(notifier().canSubmitComebackAnswer, isFalse);
    });
  });

  group('submission', () {
    test('tries available → the hub call is dispatched', () async {
      await enterBreaker(myTryCount: 0, myMaxTryCount: 3);

      final sent = await notifier().submitComebackAnswer(10);

      expect(sent, isTrue);
      expect(signalR.submissions, hasLength(1));
      expect(signalR.submissions.single.args, ['g1', 10],
          reason: 'the same SubmitAnswer(gameId, answerId) encoding');
    });

    test('tries exhausted → the hub call is never made', () async {
      await enterBreaker(myTryCount: 3, myMaxTryCount: 3);

      final sent = await notifier().submitComebackAnswer(10);

      expect(sent, isFalse);
      expect(signalR.submissions, isEmpty);
    });

    test('a submission never increments the local tryCount', () async {
      await enterBreaker(myTryCount: 0, myMaxTryCount: 3);

      await notifier().submitComebackAnswer(10);

      expect(current().me?.makeupTryCount, 0);
    });
  });

  group('timeout lock (comebackAnswerLocked, shared with Comeback)', () {
    test('Penalty(type: 1) locks answering even with tries remaining',
        () async {
      await enterBreaker(myTryCount: 0, myMaxTryCount: 3);
      expect(notifier().canSubmitComebackAnswer, isTrue);

      await emit(PlayGameHubEvents.penalty, {'playerId': _localId, 'type': 1});

      expect(current().comebackAnswerLocked, isTrue);
      expect(notifier().canSubmitComebackAnswer, isFalse);
    });

    test('Penalty(type: 2, wrong) does not lock answering', () async {
      await enterBreaker(myTryCount: 0, myMaxTryCount: 3);

      await emit(PlayGameHubEvents.penalty, {'playerId': _localId, 'type': 2});

      expect(current().comebackAnswerLocked, isFalse);
      expect(notifier().canSubmitComebackAnswer, isTrue);
    });

    test('a genuine new question clears the lock when tries remain',
        () async {
      await enterBreaker(myTryCount: 0, myMaxTryCount: 3);
      await emit(PlayGameHubEvents.penalty, {'playerId': _localId, 'type': 1});
      expect(notifier().canSubmitComebackAnswer, isFalse);

      await emit(PlayGameHubEvents.nextQuestion, {
        'id': 2,
        'text': 'q2',
        'textEn': 'q2',
        'answers': [
          {'id': 20, 'text': 'b1', 'textEn': 'b1'},
        ],
      });

      expect(current().comebackAnswerLocked, isFalse);
      expect(notifier().canSubmitComebackAnswer, isTrue);
    });
  });

  group('timer (CorrectAnswer/Penalty do not freeze it — shared with '
      'Comeback)', () {
    test('TimerUpdatedSeconds(10) → Penalty → timer remains running',
        () async {
      await enterBreaker();
      await emit(PlayGameHubEvents.timeStarted, null);
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );
      expect(current().game?.isTimerStarted, isTrue);

      await emit(PlayGameHubEvents.penalty, {'playerId': _localId, 'type': 2});

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'Penalty must not freeze the Breaker timer');
      expect(current().game?.currentTimerValue, 10);
    });

    test('TimerUpdatedSeconds(10) → CorrectAnswer → timer remains running',
        () async {
      await enterBreaker();
      await emit(PlayGameHubEvents.timeStarted, null);
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );

      await emit(
        PlayGameHubEvents.correctAnswer,
        {'arg0': 'answer', 'arg1': 'answer en', 'arg2': _localId},
      );

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'CorrectAnswer must not freeze the Breaker timer');
      expect(current().game?.currentTimerValue, 10);
    });

    test('progressive NextQuestion for the same id does not kill an '
        'already-running timer', () async {
      await enterBreaker();
      await emit(PlayGameHubEvents.timeStarted, null);
      await emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );

      for (final text in ['q', 'qu', 'que']) {
        await emit(PlayGameHubEvents.nextQuestion, {
          'id': 1,
          'text': text,
          'textEn': text,
          'answers': [
            {'id': 10, 'text': 'a1', 'textEn': 'a1'},
          ],
        });
      }

      expect(current().game?.isTimerStarted, isTrue);
      expect(current().game?.currentQuestion?.displayText(isArabic: false),
          'que');
    });
  });

  group('GameRestore', () {
    test('restore mid-question with tries remaining preserves the ability '
        'to answer', () async {
      await enterBreaker(myTryCount: 1, myMaxTryCount: 3);
      await emit(PlayGameHubEvents.penalty, {'playerId': _localId, 'type': 1});
      expect(notifier().canSubmitComebackAnswer, isFalse);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _breakerGame(myTryCount: 1, myMaxTryCount: 3),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().comebackAnswerLocked, isFalse,
          reason: 'no server field reports "locked at timeout" — a '
              'restore always comes back unlocked, same as Comeback');
      expect(notifier().canSubmitComebackAnswer, isTrue);
    });

    test('restore after attempts are exhausted remains locked', () async {
      await enterBreaker(myTryCount: 3, myMaxTryCount: 3);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _breakerGame(myTryCount: 3, myMaxTryCount: 3),
      );
      await Future<void>.delayed(Duration.zero);

      expect(notifier().canSubmitComebackAnswer, isFalse);
    });

    test('restore does not gate answering on currentTurn', () async {
      await enterBreaker(myTryCount: 0, myMaxTryCount: 3);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _breakerGame(currentTurn: _opponentId, myTryCount: 0),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().isMyTurn, isFalse);
      expect(notifier().canSubmitComebackAnswer, isTrue);
    });
  });
}
