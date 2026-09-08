import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Auction A-3 — answering ownership, score binding and submission.
//
// Ownership comes from AuctionAnswerPhaseStarted.playerId, never from
// isMyTurn: nothing in this repository establishes that ChangeTurn stays
// authoritative once the answer phase begins.

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

Map<String, dynamic> _auctionGame({
  String currentTurn = _localId,
  int makeupTryCount = 0,
  int maxMakeupTryCount = 3,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 2,
      'groupId': 'grp',
      'currentTurn': currentTurn,
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'makeupTryCount': makeupTryCount,
          'maxMakeupTryCount': maxMakeupTryCount,
        },
        {
          'id': _opponentId,
          'playerName': 'them',
          'makeupTryCount': makeupTryCount,
          'maxMakeupTryCount': maxMakeupTryCount,
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
          {'id': 11, 'text': 'a2', 'textEn': 'a2'},
        ],
      },
      'auctionGameMetadata': {
        'phase': 2,
        'currentScore': 0,
        'currentBid': 4,
        'answerTimeout': 8,
      },
    };

void main() {
  late ProviderContainer container;
  late _FakeHubBindings bindings;
  late _FakeSignalRService signalR;

  Future<void> setUpContainer() async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
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

  Future<void> enterAuction({
    String currentTurn = _localId,
    int makeupTryCount = 0,
    int maxMakeupTryCount = 3,
  }) async {
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _auctionGame(
        currentTurn: currentTurn,
        makeupTryCount: makeupTryCount,
        maxMakeupTryCount: maxMakeupTryCount,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> answerPhase(String playerId, int bidValue) async {
    bindings.emit(
      PlayGameHubEvents.auctionAnswerPhaseStarted,
      {'playerId': playerId, 'bidValue': bidValue},
    );
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> scoreUpdate(
    String playerId, {
    int? currentScore,
    int? goalScore,
    int? wrongScore,
  }) async {
    bindings.emit(PlayGameHubEvents.auctionAnswerPhaseScoreUpdate, {
      'playerId': playerId,
      if (currentScore != null) 'currentScore': currentScore,
      if (goalScore != null) 'goalScore': goalScore,
      if (wrongScore != null) 'wrongScore': wrongScore,
    });
    await Future<void>.delayed(Duration.zero);
  }

  group('answering ownership', () {
    test('the named local player owns the answer phase', () async {
      await enterAuction();
      await answerPhase(_localId, 5);

      expect(notifier().isAuctionAnswerer, isTrue);
      expect(current().answeringPlayerId, _localId);
    });

    test('the named opponent means this device does not answer', () async {
      await enterAuction();
      await answerPhase(_opponentId, 5);

      expect(notifier().isAuctionAnswerer, isFalse);
    });

    test('nobody owns it before the phase event', () async {
      await enterAuction();
      expect(notifier().isAuctionAnswerer, isFalse);
    });

    test('an id naming neither seat owns nothing', () async {
      await enterAuction();
      await answerPhase('999', 5);

      expect(current().answeringPlayerId, '999');
      expect(notifier().isAuctionAnswerer, isFalse,
          reason: 'strict identity — no elimination');
    });

    test('ownership does not follow the turn', () async {
      // The turn is mine, the answer phase is theirs: ownership must not flip.
      await enterAuction(currentTurn: _localId);
      await answerPhase(_opponentId, 5);

      expect(current().isMyTurn, isTrue);
      expect(notifier().isAuctionAnswerer, isFalse);
    });

    test('losing the turn does not take the answer phase away', () async {
      await enterAuction(currentTurn: _localId);
      await answerPhase(_localId, 5);

      bindings.emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _opponentId, 'arg1': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().isMyTurn, isFalse);
      expect(notifier().isAuctionAnswerer, isTrue,
          reason: 'AuctionAnswerPhaseStarted is the only source');
    });
  });

  group('the wrong-attempt allowance', () {
    test('the answering player resolves to a seated roster entry', () async {
      await enterAuction();
      await answerPhase(_localId, 5);

      expect(notifier().auctionAnsweringPlayer?.id, _localId);
      expect(notifier().auctionAnsweringPlayer?.maxMakeupTryCount, 3);
    });

    test('selection stays open below the limit', () async {
      await enterAuction(makeupTryCount: 2, maxMakeupTryCount: 3);
      await answerPhase(_localId, 5);

      expect(notifier().isAuctionWrongLimitReached, isFalse);
      expect(notifier().canSubmitAuctionAnswer, isTrue);
      expect(await notifier().submitAuctionAnswer(10), isTrue);
    });

    test('selection closes exactly at the limit', () async {
      await enterAuction(makeupTryCount: 3, maxMakeupTryCount: 3);
      await answerPhase(_localId, 5);

      expect(notifier().isAuctionWrongLimitReached, isTrue);
      expect(notifier().canSubmitAuctionAnswer, isFalse);
      expect(await notifier().submitAuctionAnswer(10), isFalse);
      expect(signalR.submissions, isEmpty);
    });

    test('it stays closed past the limit', () async {
      await enterAuction(makeupTryCount: 4, maxMakeupTryCount: 3);
      await answerPhase(_localId, 5);

      expect(notifier().canSubmitAuctionAnswer, isFalse);
    });

    test('a GameUpdated moves the count — the client never increments it',
        () async {
      await enterAuction(makeupTryCount: 0, maxMakeupTryCount: 3);
      await answerPhase(_localId, 5);
      expect(current().me?.makeupTryCount, 0);

      await notifier().submitAuctionAnswer(10);
      expect(current().me?.makeupTryCount, 0,
          reason: 'a submission never bumps it locally');

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _auctionGame(makeupTryCount: 3, maxMakeupTryCount: 3),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().me?.makeupTryCount, 3, reason: 'the server moved it');
      expect(notifier().canSubmitAuctionAnswer, isFalse);
    });

    test('the limit follows the answering player, not this device', () async {
      // The opponent is answering and has spent their allowance; this device
      // was never able to answer anyway.
      await enterAuction(makeupTryCount: 3, maxMakeupTryCount: 3);
      await answerPhase(_opponentId, 5);

      expect(notifier().auctionAnsweringPlayer?.id, _opponentId);
      expect(notifier().isAuctionWrongLimitReached, isTrue);
      expect(notifier().canSubmitAuctionAnswer, isFalse);
    });

    test('a missing limit leaves selection open', () async {
      await enterAuction(makeupTryCount: 5, maxMakeupTryCount: 0);
      await answerPhase(_localId, 5);

      expect(notifier().isAuctionWrongLimitReached, isFalse,
          reason: 'no limit sent — the round is not locked on a missing value');
      expect(await notifier().submitAuctionAnswer(10), isTrue);
    });

    test('an unseated answering id has no allowance to check', () async {
      await enterAuction();
      await answerPhase('999', 5);

      expect(notifier().auctionAnsweringPlayer, isNull);
      expect(notifier().isAuctionWrongLimitReached, isFalse);
      expect(notifier().canSubmitAuctionAnswer, isFalse,
          reason: 'blocked by ownership, not by the allowance');
    });

    test('wrongScore stays the authoritative auction wrong count', () async {
      await enterAuction(makeupTryCount: 1, maxMakeupTryCount: 3);
      await answerPhase(_localId, 5);
      await scoreUpdate(_localId, wrongScore: 2);

      expect(current().wrongScore, 2, reason: 'displayed count');
      expect(current().me?.makeupTryCount, 1,
          reason: 'the roster counter is separate and not overwritten');
    });
  });

  group('goalScore binding', () {
    test('bidValue becomes the goal', () async {
      await enterAuction();
      await answerPhase(_localId, 7);

      expect(current().goalScore, 7);
    });

    test('a later score update may restate the goal', () async {
      await enterAuction();
      await answerPhase(_localId, 7);
      await scoreUpdate(_localId, currentScore: 2, goalScore: 7);

      expect(current().goalScore, 7);
      expect(current().currentScore, 2);
    });
  });

  group('currentScore and wrongScore', () {
    test('both come from the score update', () async {
      await enterAuction();
      await answerPhase(_localId, 5);
      await scoreUpdate(_localId, currentScore: 3, wrongScore: 2);

      expect(current().currentScore, 3);
      expect(current().wrongScore, 2);
    });

    test('successive updates advance the score', () async {
      await enterAuction();
      await answerPhase(_localId, 5);
      await scoreUpdate(_localId, currentScore: 1);
      await scoreUpdate(_localId, currentScore: 2);
      await scoreUpdate(_localId, currentScore: 3);

      expect(current().currentScore, 3);
    });

    test('a penalty never moves the wrong count', () async {
      await enterAuction();
      await answerPhase(_localId, 5);
      await scoreUpdate(_localId, wrongScore: 1);

      bindings.emit(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 2},
      );
      bindings.emit(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 2},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().wrongScore, 1,
          reason: 'AuctionAnswerPhaseScoreUpdate is authoritative');
    });

    test('reaching the goal is recorded, never acted on locally', () async {
      await enterAuction();
      await answerPhase(_localId, 3);
      await scoreUpdate(_localId, currentScore: 3, goalScore: 3);

      expect(current().currentScore, 3);
      expect(current().goalScore, 3);
      expect(current().auctionResult, AuctionResult.none,
          reason: 'only the server announces the outcome');
    });
  });

  group('answer submission', () {
    test('the answering player can submit', () async {
      await enterAuction();
      await answerPhase(_localId, 5);

      expect(await notifier().submitAuctionAnswer(10), isTrue);
      expect(signalR.submissions, hasLength(1));
      expect(signalR.submissions.single.args, ['g1', 10],
          reason: 'the existing positional SubmitAnswer encoding');
    });

    test('the non-answering player cannot submit', () async {
      await enterAuction();
      await answerPhase(_opponentId, 5);

      expect(await notifier().submitAuctionAnswer(10), isFalse);
      expect(signalR.submissions, isEmpty);
    });

    test('nobody can submit before the phase event', () async {
      await enterAuction();

      expect(await notifier().submitAuctionAnswer(10), isFalse);
      expect(signalR.submissions, isEmpty);
    });

    test('holding the turn does not grant submission', () async {
      await enterAuction(currentTurn: _localId);
      await answerPhase(_opponentId, 5);

      expect(current().isMyTurn, isTrue);
      expect(await notifier().submitAuctionAnswer(10), isFalse);
    });

    test('several answers can be submitted for one question', () async {
      await enterAuction();
      await answerPhase(_localId, 3);

      expect(await notifier().submitAuctionAnswer(10), isTrue);
      expect(await notifier().submitAuctionAnswer(11), isTrue);

      expect(signalR.submissions, hasLength(2),
          reason: 'auction answers are not one-shot like WDYK');
    });

    test('a failed dispatch reports false and sends nothing', () async {
      await enterAuction();
      await answerPhase(_localId, 5);
      signalR.connected = false;

      expect(await notifier().submitAuctionAnswer(10), isFalse);
      expect(signalR.submissions, isEmpty);
    });
  });

  group('no state moves before the server confirms', () {
    test('submitting changes no auction state', () async {
      await enterAuction();
      await answerPhase(_localId, 5);
      final before = current();

      await notifier().submitAuctionAnswer(10);

      final after = current();
      expect(after.currentScore, before.currentScore);
      expect(after.wrongScore, before.wrongScore);
      expect(after.goalScore, 5);
      expect(after.auctionPhase, AuctionPhase.answering);
      expect(after.auctionResult, AuctionResult.none);
    });

    test('the score moves only when the update arrives', () async {
      await enterAuction();
      await answerPhase(_localId, 5);
      await notifier().submitAuctionAnswer(10);
      expect(current().currentScore, 0, reason: 'restored metadata value');

      await scoreUpdate(_localId, currentScore: 1);

      expect(current().currentScore, 1);
    });

    test('submitting does not disturb the timer', () async {
      await enterAuction();
      await answerPhase(_localId, 5);
      bindings.emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        {'arg0': 10, 'arg1': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);

      await notifier().submitAuctionAnswer(10);

      expect(current().game?.currentTimerValue, 10);
      expect(current().game?.isTimerStarted, isTrue,
          reason: 'still running: the countdown TimerUpdatedSeconds started is '
              'left exactly as it was — submitting is not a resolution');
    });

    test('the WDYK submit path is untouched', () async {
      await enterAuction(currentTurn: _opponentId);
      await answerPhase(_localId, 5);

      // WDYK's own guard is isMyTurn, and it is not mine.
      expect(await notifier().submitAnswer(10), isFalse);
      expect(await notifier().submitAuctionAnswer(10), isTrue,
          reason: 'the auction guard is independent');
    });
  });
}
