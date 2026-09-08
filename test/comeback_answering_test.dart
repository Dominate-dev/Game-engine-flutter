import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Comeback C-2 — tries-based answer eligibility and submission.
//
// Unlike Bell/WDYK, both players may answer concurrently: eligibility comes
// from each player's own makeupTryCount/maxMakeupTryCount, never from
// currentTurn — confirmed contract, C-1.

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

Map<String, dynamic> _comebackGame({
  String currentTurn = '',
  int myTryCount = 0,
  int myMaxTryCount = 3,
  int opponentTryCount = 0,
  int opponentMaxTryCount = 3,
  int type = 4,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': type,
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
        'type': 1,
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

  Future<void> enterComeback({
    String currentTurn = '',
    int myTryCount = 0,
    int myMaxTryCount = 3,
    int opponentTryCount = 0,
    int opponentMaxTryCount = 3,
    int type = 4,
  }) async {
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _comebackGame(
        currentTurn: currentTurn,
        myTryCount: myTryCount,
        myMaxTryCount: myMaxTryCount,
        opponentTryCount: opponentTryCount,
        opponentMaxTryCount: opponentMaxTryCount,
        type: type,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  group('eligibility', () {
    test('my tries available → can submit', () async {
      await enterComeback(myTryCount: 1, myMaxTryCount: 3);
      expect(notifier().canSubmitComebackAnswer, isTrue);
    });

    test('my tries exhausted → cannot submit', () async {
      await enterComeback(myTryCount: 3, myMaxTryCount: 3);
      expect(notifier().canSubmitComebackAnswer, isFalse);
    });

    test("my eligibility is independent of the opponent's tries", () async {
      await enterComeback(
        myTryCount: 0,
        myMaxTryCount: 3,
        opponentTryCount: 3,
        opponentMaxTryCount: 3,
      );
      expect(notifier().canSubmitComebackAnswer, isTrue,
          reason: 'the opponent being locked out does not touch mine');
      expect(current().opponent?.makeupTryCount, 3);
    });

    test('the opponent exhausting tries while mine remain does not lock me',
        () async {
      await enterComeback(myTryCount: 1, myMaxTryCount: 3);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _comebackGame(
          myTryCount: 1,
          myMaxTryCount: 3,
          opponentTryCount: 3,
          opponentMaxTryCount: 3,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(notifier().canSubmitComebackAnswer, isTrue);
    });

    test('currentTurn naming the opponent does not block my submission',
        () async {
      await enterComeback(
        currentTurn: _opponentId,
        myTryCount: 0,
        myMaxTryCount: 3,
      );

      expect(current().isMyTurn, isFalse);
      expect(notifier().canSubmitComebackAnswer, isTrue,
          reason: 'Comeback has no turn gate — tries are the only gate');
    });

    test(
        'a later GameUpdated reflects the server tryCount with no local '
        'counter', () async {
      await enterComeback(myTryCount: 0, myMaxTryCount: 3);
      expect(notifier().canSubmitComebackAnswer, isTrue);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _comebackGame(myTryCount: 3, myMaxTryCount: 3),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().me?.makeupTryCount, 3, reason: 'the server moved it');
      expect(notifier().canSubmitComebackAnswer, isFalse);
    });

    test('a non-Comeback phase does not use this action', () async {
      // Same tries data but a Bell-typed round (type 3) — the Comeback
      // guard must not accidentally open answering for Bell/WDYK/Auction.
      await enterComeback(myTryCount: 0, myMaxTryCount: 3, type: 3);

      expect(current().phase, isNot(GamePhase.comeBack));
      expect(notifier().canSubmitComebackAnswer, isFalse);
    });
  });

  Future<void> emit(String name, Map<String, dynamic>? data) async {
    bindings.emit(name, data);
    await Future<void>.delayed(Duration.zero);
  }

  group('timeout lock', () {
    test('Penalty(type: 1) locks answering even with tries remaining',
        () async {
      await enterComeback(myTryCount: 0, myMaxTryCount: 3);
      expect(notifier().canSubmitComebackAnswer, isTrue);

      await emit(PlayGameHubEvents.penalty, {'playerId': _localId, 'type': 1});

      expect(current().comebackAnswerLocked, isTrue);
      expect(notifier().canSubmitComebackAnswer, isFalse,
          reason: 'a timeout locks beyond what the tries count covers');
    });

    test('Penalty(type: 2, wrong) does not lock answering', () async {
      await enterComeback(myTryCount: 0, myMaxTryCount: 3);

      await emit(PlayGameHubEvents.penalty, {'playerId': _localId, 'type': 2});

      expect(current().comebackAnswerLocked, isFalse);
      expect(notifier().canSubmitComebackAnswer, isTrue);
    });

    test('submitComebackAnswer dispatches nothing while locked', () async {
      await enterComeback(myTryCount: 0, myMaxTryCount: 3);
      await emit(PlayGameHubEvents.penalty, {'playerId': _localId, 'type': 1});

      final sent = await notifier().submitComebackAnswer(10);

      expect(sent, isFalse);
      expect(signalR.submissions, isEmpty);
    });

    test('a genuine new question clears the lock when tries remain',
        () async {
      await enterComeback(myTryCount: 0, myMaxTryCount: 3);
      await emit(PlayGameHubEvents.penalty, {'playerId': _localId, 'type': 1});
      expect(notifier().canSubmitComebackAnswer, isFalse);

      await emit(PlayGameHubEvents.nextQuestion, {
        'id': 2,
        'text': 'q2',
        'textEn': 'q2',
        'type': 1,
        'answers': [
          {'id': 20, 'text': 'b1', 'textEn': 'b1'},
        ],
      });

      expect(current().comebackAnswerLocked, isFalse);
      expect(notifier().canSubmitComebackAnswer, isTrue);
    });

    test('a same-question NextQuestion repeat does not clear the lock',
        () async {
      await enterComeback(myTryCount: 0, myMaxTryCount: 3);
      await emit(PlayGameHubEvents.penalty, {'playerId': _localId, 'type': 1});

      // Same id/questionNumber as the question already current.
      await emit(PlayGameHubEvents.nextQuestion, {
        'id': 1,
        'text': 'q',
        'textEn': 'q',
        'type': 1,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      });

      expect(current().comebackAnswerLocked, isTrue,
          reason: 'not a genuinely new question');
      expect(notifier().canSubmitComebackAnswer, isFalse);
    });

    test('exhausted tries lock answering with no Penalty involved', () async {
      await enterComeback(myTryCount: 3, myMaxTryCount: 3);

      expect(current().comebackAnswerLocked, isFalse,
          reason: 'the tries count is the gate here, not the timeout flag');
      expect(notifier().canSubmitComebackAnswer, isFalse);
    });

    test('a NextRoundStarted reset clears any lingering lock', () async {
      await enterComeback(myTryCount: 0, myMaxTryCount: 3);
      await emit(PlayGameHubEvents.penalty, {'playerId': _localId, 'type': 1});
      expect(current().comebackAnswerLocked, isTrue);

      await emit(PlayGameHubEvents.nextRoundStarted, {'arg0': 4, 'arg1': 'g1'});

      expect(current().comebackAnswerLocked, isFalse);
    });
  });

  group('C-4.1 — GameRestore', () {
    test('restore mid-question with tries remaining preserves the ability '
        'to answer', () async {
      await enterComeback(myTryCount: 1, myMaxTryCount: 3);
      await emit(PlayGameHubEvents.penalty, {'playerId': _localId, 'type': 1});
      expect(notifier().canSubmitComebackAnswer, isFalse,
          reason: 'locked by the timeout, precondition for this test');

      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _comebackGame(myTryCount: 1, myMaxTryCount: 3),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().comebackAnswerLocked, isFalse,
          reason: 'no server field reports "locked at timeout" — a '
              'restore always comes back unlocked');
      expect(notifier().canSubmitComebackAnswer, isTrue,
          reason: 'attempts remain, so answering is available again');
    });

    test('restore after attempts are exhausted remains locked', () async {
      await enterComeback(myTryCount: 3, myMaxTryCount: 3);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _comebackGame(myTryCount: 3, myMaxTryCount: 3),
      );
      await Future<void>.delayed(Duration.zero);

      expect(notifier().canSubmitComebackAnswer, isFalse,
          reason: 'the tries count alone still gates this — restore does '
              'not grant extra attempts');
    });

    test('restore followed by a genuine new question resumes normal flow',
        () async {
      await enterComeback(myTryCount: 3, myMaxTryCount: 3);
      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _comebackGame(myTryCount: 3, myMaxTryCount: 3),
      );
      await Future<void>.delayed(Duration.zero);
      expect(notifier().canSubmitComebackAnswer, isFalse);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _comebackGame(myTryCount: 0, myMaxTryCount: 3)
          ..['currentQuestion'] = {
            'id': 2,
            'text': 'q2',
            'textEn': 'q2',
            'type': 1,
            'answers': [
              {'id': 20, 'text': 'b1', 'textEn': 'b1'},
            ],
          },
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().me?.makeupTryCount, 0);
      expect(notifier().canSubmitComebackAnswer, isTrue);
    });

    test('restore does not gate answering on currentTurn', () async {
      await enterComeback(myTryCount: 0, myMaxTryCount: 3);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _comebackGame(
          currentTurn: _opponentId,
          myTryCount: 0,
          myMaxTryCount: 3,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().isMyTurn, isFalse);
      expect(notifier().canSubmitComebackAnswer, isTrue);
    });
  });

  group('submission', () {
    test('tries available → the hub call is dispatched', () async {
      await enterComeback(myTryCount: 0, myMaxTryCount: 3);

      final sent = await notifier().submitComebackAnswer(10);

      expect(sent, isTrue);
      expect(signalR.submissions, hasLength(1));
      expect(signalR.submissions.single.args, ['g1', 10],
          reason: 'the existing positional SubmitAnswer encoding');
    });

    test('tries exhausted → the hub call is never made', () async {
      await enterComeback(myTryCount: 3, myMaxTryCount: 3);

      final sent = await notifier().submitComebackAnswer(10);

      expect(sent, isFalse);
      expect(signalR.submissions, isEmpty);
    });

    test('a submission never increments the local tryCount', () async {
      await enterComeback(myTryCount: 0, myMaxTryCount: 3);

      await notifier().submitComebackAnswer(10);

      expect(current().me?.makeupTryCount, 0,
          reason: 'only the server, via GameUpdated, moves the count');
    });

    test('a failed dispatch reports false and sends nothing', () async {
      await enterComeback(myTryCount: 0, myMaxTryCount: 3);
      signalR.connected = false;

      expect(await notifier().submitComebackAnswer(10), isFalse);
      expect(signalR.submissions, isEmpty);
    });
  });
}
