import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// JudgeController against hand-built payloads in the shapes the server sends
// (docs/JUDGE_MODE_SPEC.md): what each judge tap dispatches, and how each
// event moves the judge's screen.

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];
  bool accept = true;

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    invocations.add((method: methodName, args: args));
    return accept;
  }

  @override
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) => () {};

  @override
  void reattachEventHandlers() {}

  List<Object?>? lastArgs(String method) =>
      invocations.lastWhere((i) => i.method == method).args;

  int count(String method) =>
      invocations.where((i) => i.method == method).length;
}

class _FakeHubBindings extends PlayGameHubBindings {
  _FakeHubBindings(super.signalR);

  final _events = StreamController<GameHubEvent>.broadcast(sync: true);

  @override
  Stream<GameHubEvent> get stream => _events.stream;

  @override
  void bindAll() {}

  @override
  void bindEvents(Iterable<String> eventNames) {}

  void emit(String name, [Map<String, dynamic>? data]) =>
      _events.add(GameHubEvent(name: name, data: data));

  @override
  void dispose() {
    _events.close();
  }
}

const _gameId = '11111111-2222-3333-4444-555555555555';
const _otherGameId = '99999999-2222-3333-4444-555555555555';
const _p1 = '471';
const _p2 = '472';

Map<String, dynamic> _player(
  String id,
  String name, {
  int points = 0,
  int penalty = 0,
  int passes = 1,
}) => {
  'id': id,
  'playerName': name,
  'points': points,
  'penalty': penalty,
  'passes': passes,
  'isReady': true,
};

Map<String, dynamic> _question(
  int id, {
  List<int> answers = const [1, 2, 3],
  int number = 1,
}) => {
  'id': id,
  'text': 'سؤال $id',
  'textEn': 'Question $id',
  'type': 1,
  'answers': [
    for (final a in answers)
      {'id': id * 10 + a, 'text': 'ج$a', 'textEn': 'A$a'},
  ],
  'maxCorrectAnswersCount': 100,
  'questionNumber': number,
  'roundTotalQuestionsCount': 5,
};

Map<String, dynamic> _game({
  int mode = 3,
  int status = 1,
  int type = 1,
  bool withPlayers = false,
  Map<String, dynamic>? question,
  String? currentTurn,
  Map<String, dynamic>? auction,
}) => {
  'id': _gameId,
  'mode': mode,
  'status': status,
  'type': type,
  'groupId': 'grp',
  'players': withPlayers
      ? [_player(_p1, 'Ali'), _player(_p2, 'Sara')]
      : <Object>[],
  if (question != null) 'currentQuestion': question,
  if (currentTurn != null) 'currentTurn': currentTurn,
  if (auction != null) 'auctionGameMetadata': auction,
  HubEventPayload.gameIdKey: _gameId,
};

Map<String, dynamic> _args(List<Object?> values) => {
  for (var i = 0; i < values.length; i++) 'arg$i': values[i],
};

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;
  late _FakeHubBindings hub;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'user_id': '47',
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    hub = _FakeHubBindings(signalR);
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider.overrideWithValue(hub),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(judgeControllerProvider, (_, __) {});
    addTearDown(sub.close);
  });

  JudgeController judge() => container.read(judgeControllerProvider.notifier);
  JudgeState current() => container.read(judgeControllerProvider);

  Future<void> startedGame({
    int type = 1,
    Map<String, dynamic>? question,
  }) async {
    await judge().create();
    hub.emit(PlayGameHubEvents.gameCreated, _game());
    await judge().start('Ali', 'Sara', const []);
    hub.emit(
      PlayGameHubEvents.gameStarted,
      _game(
        status: 3,
        type: type,
        withPlayers: true,
        question: question ?? _question(10),
        currentTurn: _p1,
      ),
    );
  }

  group('setup', () {
    test('creates a Judge game and waits for the names', () async {
      await judge().create();
      expect(signalR.lastArgs(PlayGameHubEvents.createGame), [3]);

      hub.emit(PlayGameHubEvents.gameCreated, _game());
      expect(current().stage, JudgeStage.naming);
      expect(current().gameId, _gameId);
    });

    test('ignores a game created for another mode', () async {
      await judge().create();
      hub.emit(PlayGameHubEvents.gameCreated, _game(mode: 1));
      expect(current().stage, JudgeStage.creating);
    });

    test('starts with the two names and no interests', () async {
      await judge().create();
      hub.emit(PlayGameHubEvents.gameCreated, _game());
      await judge().start(' Ali ', 'Sara', const []);
      expect(signalR.lastArgs(PlayGameHubEvents.startJudgeGame), [
        _gameId,
        'Ali',
        'Sara',
        null,
      ]);
      expect(current().stage, JudgeStage.starting);
    });

    test('passes the host interests through', () async {
      await judge().create();
      hub.emit(PlayGameHubEvents.gameCreated, _game());
      await judge().start('Ali', 'Sara', const [7]);
      expect(signalR.lastArgs(PlayGameHubEvents.startJudgeGame)![3], [7]);
    });

    test(
      'a game that cannot start goes back to the names, marked failed',
      () async {
        await judge().create();
        hub.emit(PlayGameHubEvents.gameCreated, _game());
        await judge().start('Ali', 'Sara', const []);
        hub.emit(PlayGameHubEvents.gameFinished, _args([true]));
        expect(current().stage, JudgeStage.naming);
        expect(current().failed, isTrue);
      },
    );

    test('GameStarted opens round one with no clock running', () async {
      await startedGame();
      expect(current().stage, JudgeStage.playing);
      expect(current().round, JudgeRound.wdyk);
      expect(current().timerRunning, isFalse);
      expect(current().players.map((p) => p.playerName), ['Ali', 'Sara']);
    });
  });

  group('What do you know', () {
    test('the timer starts on the judge and runs on the server time', () async {
      await startedGame();
      await judge().startTimer();
      expect(signalR.lastArgs(PlayGameHubEvents.startGameTimer), [_gameId]);

      hub.emit(PlayGameHubEvents.changeTurn, _args([_p2, _gameId]));
      hub.emit(PlayGameHubEvents.timerUpdatedSeconds, _args([31, _gameId]));
      expect(current().turn, _p2);
      expect(current().timerRunning, isTrue);
    });

    test('GameUpdated does not move the turn', () async {
      await startedGame();
      hub.emit(PlayGameHubEvents.changeTurn, _args([_p2, _gameId]));
      hub.emit(
        PlayGameHubEvents.gameUpdated,
        _game(status: 3, withPlayers: true, currentTurn: _p1),
      );
      expect(current().turn, _p2);
    });

    test('an answer goes out once per listed id, for the seat named', () async {
      await startedGame();
      await judge().answer(101, _p1);
      await judge().answer(101, _p1);
      expect(signalR.count(PlayGameHubEvents.judgeSubmitAnswer), 1);
      expect(signalR.lastArgs(PlayGameHubEvents.judgeSubmitAnswer), [
        _gameId,
        101,
        _p1,
      ]);

      await judge().answer(JudgeController.wrongAnswerId, _p1);
      await judge().answer(JudgeController.wrongAnswerId, _p1);
      expect(signalR.count(PlayGameHubEvents.judgeSubmitAnswer), 3);
    });

    test('an answer that never left can be sent again', () async {
      await startedGame();
      signalR.accept = false;
      await judge().answer(101, _p1);
      signalR.accept = true;
      await judge().answer(101, _p1);
      expect(signalR.count(PlayGameHubEvents.judgeSubmitAnswer), 2);
    });

    test('a strike is shown and stops the clock', () async {
      await startedGame();
      hub.emit(PlayGameHubEvents.timerUpdatedSeconds, _args([31, _gameId]));
      hub.emit(PlayGameHubEvents.penalty, {
        'playerId': _p1,
        'type': 2,
        HubEventPayload.gameIdKey: _gameId,
      });
      expect(current().lastCall?.kind, JudgeCallKind.wrong);
      expect(current().lastCall?.playerId, _p1);
      expect(current().timerRunning, isFalse);
    });

    test(
      'after a call the controls wait for the next turn, not offer Start timer',
      () async {
        await startedGame();
        hub.emit(PlayGameHubEvents.timerUpdatedSeconds, _args([31, _gameId]));
        hub.emit(
          PlayGameHubEvents.correctAnswer,
          _args(['أحمر', 'Red', _p1, _gameId]),
        );
        expect(current().awaiting, isTrue);
        expect(current().timerRunning, isFalse);

        hub.emit(PlayGameHubEvents.changeTurn, _args([_p2, _gameId]));
        expect(current().awaiting, isTrue);
        hub.emit(PlayGameHubEvents.timerUpdatedSeconds, _args([31, _gameId]));
        expect(current().awaiting, isFalse);
        expect(current().timerRunning, isTrue);
      },
    );

    test(
      'a question that ends after a call opens Start timer for the next one',
      () async {
        await startedGame();
        hub.emit(PlayGameHubEvents.penalty, {
          'playerId': _p1,
          'type': 2,
          HubEventPayload.gameIdKey: _gameId,
        });
        expect(current().awaiting, isTrue);
        hub.emit(PlayGameHubEvents.nextQuestion, {
          ..._question(11, number: 2),
          HubEventPayload.gameIdKey: _gameId,
        });
        expect(current().awaiting, isFalse);
        expect(current().timerRunning, isFalse);
      },
    );

    test('a new question waits for the judge to start the clock', () async {
      await startedGame();
      hub.emit(PlayGameHubEvents.timerUpdatedSeconds, _args([31, _gameId]));
      hub.emit(PlayGameHubEvents.nextQuestion, {
        ..._question(11, number: 2),
        HubEventPayload.gameIdKey: _gameId,
      });
      expect(current().game?.currentQuestion?.id, 11);
      expect(current().timerRunning, isFalse);
    });

    test("another game's events are ignored", () async {
      await startedGame();
      hub.emit(PlayGameHubEvents.changeTurn, _args([_p2, _otherGameId]));
      expect(current().turn, _p1);
    });
  });

  group('Auction', () {
    Future<void> inAuction() async {
      await startedGame();
      hub.emit(PlayGameHubEvents.nextRoundStarted, _args([2, _gameId]));
      hub.emit(PlayGameHubEvents.nextQuestion, {
        ..._question(20),
        HubEventPayload.gameIdKey: _gameId,
      });
      hub.emit(PlayGameHubEvents.auctionBiddingPhaseStarted, _args([_gameId]));
    }

    test('one bid for the chosen seat, never zero', () async {
      await inAuction();
      expect(current().auctionStep, JudgeAuctionStep.bidding);

      await judge().bid(_p2, 0);
      expect(signalR.count(PlayGameHubEvents.judgeBid), 0);

      await judge().bid(_p2, 3);
      expect(signalR.lastArgs(PlayGameHubEvents.judgeBid), [
        {'gameId': _gameId, 'playerId': _p2, 'bidValue': 3},
      ]);
    });

    test('answering, then the judge confirms the result', () async {
      await inAuction();
      hub.emit(PlayGameHubEvents.auctionAnswerPhaseStarted, {
        'playerId': _p2,
        'bidValue': 3,
        HubEventPayload.gameIdKey: _gameId,
      });
      expect(current().auctionStep, JudgeAuctionStep.answering);
      expect(current().bidderId, _p2);

      hub.emit(PlayGameHubEvents.auctionAnswerPhaseScoreUpdate, {
        'playerId': _p2,
        'currentScore': 2,
        'goalScore': 3,
        'wrongScore': 1,
        HubEventPayload.gameIdKey: _gameId,
      });
      expect(current().auctionScore, 2);
      expect(current().auctionWrong, 1);

      hub.emit(
        PlayGameHubEvents.showAuctionConfirmationDialog,
        _args([_gameId]),
      );
      expect(current().auctionStep, JudgeAuctionStep.confirming);
      await judge().confirmAuction(madeIt: true);
      expect(signalR.lastArgs(PlayGameHubEvents.auctionConfirmResult), [
        _gameId,
        true,
      ]);
    });

    test('a confirmation is not sent outside its step', () async {
      await inAuction();
      await judge().confirmAuction(madeIt: false);
      expect(signalR.count(PlayGameHubEvents.auctionConfirmResult), 0);
    });
  });

  group('Bell', () {
    test(
      'the ring window opens on each question and closes on a ring',
      () async {
        await startedGame();
        hub.emit(PlayGameHubEvents.nextRoundStarted, _args([3, _gameId]));
        hub.emit(PlayGameHubEvents.nextQuestion, {
          ..._question(30),
          HubEventPayload.gameIdKey: _gameId,
        });
        expect(current().turn, isEmpty);

        await judge().ringBell(_p2);
        expect(signalR.lastArgs(PlayGameHubEvents.judgeRingBell), [
          _gameId,
          _p2,
        ]);

        hub.emit(PlayGameHubEvents.changeTurn, _args([_p2, _gameId]));
        await judge().ringBell(_p1);
        expect(signalR.count(PlayGameHubEvents.judgeRingBell), 1);
      },
    );
  });

  group('Makeup and Breaker', () {
    test(
      'a point goes to the seat with a listed answer, or not-listed when none is left',
      () async {
        await startedGame();
        hub.emit(PlayGameHubEvents.nextRoundStarted, _args([4, _gameId]));
        expect(current().turn, CreatedGame.allowAllTurn);

        hub.emit(PlayGameHubEvents.nextQuestion, {
          ..._question(40, answers: [1]),
          HubEventPayload.gameIdKey: _gameId,
        });
        await judge().pointTo(_p2);
        expect(signalR.lastArgs(PlayGameHubEvents.judgeSubmitAnswer), [
          _gameId,
          401,
          _p2,
        ]);

        hub.emit(PlayGameHubEvents.nextQuestion, {
          ..._question(41, answers: []),
          HubEventPayload.gameIdKey: _gameId,
        });
        await judge().pointTo(_p1);
        expect(signalR.lastArgs(PlayGameHubEvents.judgeSubmitAnswer), [
          _gameId,
          JudgeController.notListedAnswerId,
          _p1,
        ]);
      },
    );
  });

  group('end and reconnect', () {
    test(
      'GameOver shows the result and nothing after it moves the screen',
      () async {
        await startedGame();
        hub.emit(PlayGameHubEvents.gameOver, {
          'gameId': _gameId,
          'winnerId': _p2,
          'gameResultPlayers': [
            {
              'playerId': _p1,
              'points': 2,
              'strikes': 1,
              'correctAnswersCount': 3,
            },
            {
              'playerId': _p2,
              'points': 4,
              'strikes': 0,
              'correctAnswersCount': 5,
            },
          ],
          HubEventPayload.gameIdKey: _gameId,
        });
        expect(current().stage, JudgeStage.finished);
        expect(current().nameOf(current().result!.winnerId), 'Sara');

        hub.emit(PlayGameHubEvents.changeTurn, _args([_p1, _gameId]));
        expect(current().turn, _p1); // unchanged from GameStarted
        await judge().leave();
        expect(signalR.count(PlayGameHubEvents.leaveGame), 0);
      },
    );

    test('a restore mid-auction rebuilds the step from the snapshot', () async {
      await startedGame();
      hub.emit(
        PlayGameHubEvents.gameRestore,
        _game(
          status: 3,
          type: 2,
          withPlayers: true,
          question: _question(50),
          currentTurn: _p1,
          auction: {
            'currentBid': 4,
            'currentScore': 1,
            'phase': 3,
            'answerTimeout': 30,
            'latestBidder': _p1,
          },
        ),
      );
      expect(current().round, JudgeRound.auction);
      expect(current().auctionStep, JudgeAuctionStep.confirming);
      expect(current().bidderId, _p1);
      expect(current().bid, 4);
    });

    test('leaving tells the server once the game exists', () async {
      await startedGame();
      await judge().leave();
      expect(signalR.lastArgs(PlayGameHubEvents.leaveGame), [_gameId]);
    });
  });
}
