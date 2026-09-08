import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Auction A-1 — domain, reducer and event routing.
//
// Payload shapes are the A-0 spec lock, not the T30 reference:
//   AuctionBiddingPhaseStarted     [gameId]           — no playerId
//   AuctionAnswerPhaseStarted      {playerId, bidValue}
//   AuctionAnswerPhaseScoreUpdate  {playerId, currentScore, goalScore,
//                                   wrongScore}
//   PlayerWon/LostAuctionRound     [playerId, gameId]
//
// Reduction must be order-independent, so several cases deliberately deliver
// events in the "wrong" order.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async => true;

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
  int? phase,
  int? currentScore,
  int? currentBid,
  String? latestBidder,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 2,
      'groupId': 'grp',
      'currentTurn': _localId,
      'currentQuestion': {
        'id': 1682,
        'text': 'q',
        'textEn': 'q',
        'type': 1,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
      if (phase != null)
        'auctionGameMetadata': {
          'phase': phase,
          'currentScore': currentScore ?? 0,
          'currentBid': currentBid ?? 0,
          'latestBidder': latestBidder,
          'answerTimeout': 8,
        },
    };

void main() {
  late ProviderContainer container;
  late _FakeHubBindings bindings;

  Future<void> setUpContainer() async {
    SharedPreferences.setMockInitialValues({'user_id': _localId});
    final prefs = await SharedPrefsService.init();
    final signalR = _FakeSignalRService();
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

  Future<void> enterAuction({int? phase}) async {
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _auctionGame(phase: phase),
    );
    await Future<void>.delayed(Duration.zero);
  }

  group('AuctionPhase', () {
    test('maps the confirmed ids', () {
      expect(AuctionPhase.fromId(1), AuctionPhase.bidding);
      expect(AuctionPhase.fromId(2), AuctionPhase.answering);
    });

    test('an unknown or missing id stays unresolved', () {
      expect(AuctionPhase.fromId(0), isNull);
      expect(AuctionPhase.fromId(3), isNull);
      expect(AuctionPhase.fromId(null), isNull);
    });
  });

  group('initial auction state', () {
    test('every auction field starts absent', () {
      final state = current();
      expect(state.auctionPhase, isNull);
      expect(state.answeringPlayerId, isNull);
      expect(state.goalScore, isNull);
      expect(state.currentScore, isNull);
      expect(state.wrongScore, isNull);
      expect(state.auctionResult, AuctionResult.none);
    });
  });

  group('AuctionBiddingPhaseStarted', () {
    test('[gameId] sets the bidding phase', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.auctionBiddingPhaseStarted,
        {'arg0': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().auctionPhase, AuctionPhase.bidding);
    });

    test('it clears everything the previous answer phase produced', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 5},
      );
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {
          'playerId': _localId,
          'currentScore': 3,
          'goalScore': 5,
          'wrongScore': 1,
        },
      );
      bindings.emit(
        PlayGameHubEvents.playerWonAuctionRound,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);
      expect(current().currentScore, 3);

      bindings.emit(
        PlayGameHubEvents.auctionBiddingPhaseStarted,
        {'arg0': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);

      final state = current();
      expect(state.auctionPhase, AuctionPhase.bidding);
      expect(state.answeringPlayerId, isNull);
      expect(state.goalScore, isNull);
      expect(state.currentScore, isNull);
      expect(state.wrongScore, isNull);
      expect(state.auctionResult, AuctionResult.none);
    });

    test('it names no player, so it never touches the turn', () async {
      await enterAuction();
      final turnBefore = current().game?.currentTurn;

      bindings.emit(
        PlayGameHubEvents.auctionBiddingPhaseStarted,
        {'arg0': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().game?.currentTurn, turnBefore);
      expect(current().isMyTurn, isTrue, reason: 'ChangeTurn owns the turn');
    });
  });

  group('AuctionAnswerPhaseStarted', () {
    test('names the answering player and the goal', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _opponentId, 'bidValue': 7},
      );
      await Future<void>.delayed(Duration.zero);

      final state = current();
      expect(state.auctionPhase, AuctionPhase.answering);
      expect(state.answeringPlayerId, _opponentId);
      expect(state.goalScore, 7);
    });

    test('the local player can be the answering player', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 3},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().answeringPlayerId, _localId);
    });

    test('a payload missing playerId or bidValue changes nothing', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'bidValue': 7},
      );
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId},
      );
      await Future<void>.delayed(Duration.zero);

      final state = current();
      expect(state.auctionPhase, isNull);
      expect(state.answeringPlayerId, isNull);
      expect(state.goalScore, isNull);
    });

    test('an unseated playerId is still recorded, never reassigned', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': '999', 'bidValue': 4},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().answeringPlayerId, '999',
          reason: 'recorded as sent — never resolved to a seat by elimination');
    });
  });

  group('AuctionAnswerPhaseScoreUpdate', () {
    test('applies current, goal and wrong scores', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {
          'playerId': _localId,
          'currentScore': 3,
          'goalScore': 7,
          'wrongScore': 2,
        },
      );
      await Future<void>.delayed(Duration.zero);

      final state = current();
      expect(state.currentScore, 3);
      expect(state.goalScore, 7);
      expect(state.wrongScore, 2);
    });

    test('wrongScore is taken from the server, not counted locally', () async {
      await enterAuction();
      // Two penalties, then a score update that disagrees with the count.
      bindings.emit(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 2},
      );
      bindings.emit(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 2},
      );
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {'playerId': _localId, 'wrongScore': 5},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().wrongScore, 5, reason: 'the server value wins');
    });

    test('a score arriving before the phase event is not lost', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {'playerId': _localId, 'currentScore': 1, 'goalScore': 4},
      );
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 4},
      );
      await Future<void>.delayed(Duration.zero);

      final state = current();
      expect(state.currentScore, 1, reason: 'order-independent');
      expect(state.goalScore, 4);
      expect(state.auctionPhase, AuctionPhase.answering);
    });

    test('a partial payload updates only the fields it carries', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {
          'playerId': _localId,
          'currentScore': 2,
          'goalScore': 6,
          'wrongScore': 1,
        },
      );
      await Future<void>.delayed(Duration.zero);

      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {'playerId': _localId, 'currentScore': 3},
      );
      await Future<void>.delayed(Duration.zero);

      final state = current();
      expect(state.currentScore, 3);
      expect(state.goalScore, 6, reason: 'kept');
      expect(state.wrongScore, 1, reason: 'kept');
    });

    test('a payload with no score fields changes nothing', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {'playerId': _localId},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().currentScore, isNull);
      expect(current().goalScore, isNull);
    });

    test('the opponent score update is applied too', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {'playerId': _opponentId, 'currentScore': 2, 'goalScore': 5},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().currentScore, 2);
    });
  });

  group('PlayerWon / PlayerLostAuctionRound', () {
    test('a won round is recorded from the positional payload', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.playerWonAuctionRound,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().auctionResult, AuctionResult.won);
    });

    test('a lost round is recorded', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.playerLostAuctionRound,
        {'arg0': _opponentId, 'arg1': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().auctionResult, AuctionResult.lost);
    });

    test('an opponent loss is never inverted into a local win', () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.playerLostAuctionRound,
        {'arg0': _opponentId, 'arg1': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().auctionResult, AuctionResult.lost,
          reason: 'recorded as sent, never mirrored for the other player');
    });

    test('a payload with no playerId changes nothing', () async {
      await enterAuction();
      bindings.emit(PlayGameHubEvents.playerLostAuctionRound, null);
      await Future<void>.delayed(Duration.zero);

      expect(current().auctionResult, AuctionResult.none);
    });
  });

  group('Penalty during auction', () {
    test('it changes no auction state — the loss threshold is unknown',
        () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 1},
      );
      bindings.emit(
        PlayGameHubEvents.penalty,
        {'playerId': _localId, 'type': 2},
      );
      await Future<void>.delayed(Duration.zero);

      final state = current();
      expect(state.auctionResult, AuctionResult.none,
          reason: 'PlayerLostAuctionRound is the authoritative outcome');
      expect(state.wrongScore, isNull, reason: 'ScoreUpdate owns the count');
      expect(state.auctionPhase, isNull);
    });

    test('an unreadable penalty payload is tolerated', () async {
      await enterAuction();
      bindings.emit(PlayGameHubEvents.penalty, {'type': 9});
      await Future<void>.delayed(Duration.zero);

      expect(current().auctionResult, AuctionResult.none);
    });
  });

  group('GameRestore and GameUpdated', () {
    test('phase 1 restores the bidding phase', () async {
      await enterAuction(phase: 1);
      expect(current().phase, GamePhase.auction);
      expect(current().auctionPhase, AuctionPhase.bidding);
    });

    test('phase 2 restores the answering phase and the score', () async {
      await enterAuction(phase: 2);
      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _auctionGame(phase: 2, currentScore: 4),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().auctionPhase, AuctionPhase.answering);
      expect(current().currentScore, 4);
    });

    test('an unknown phase leaves the recorded phase alone', () async {
      await enterAuction(phase: 2);
      expect(current().auctionPhase, AuctionPhase.answering);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _auctionGame(phase: 99),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().auctionPhase, AuctionPhase.answering,
          reason: 'an unrecognised phase is not guessed');
    });

    test('a GameUpdated does not wipe the running answer state', () async {
      await enterAuction(phase: 2);
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 6},
      );
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {'playerId': _localId, 'currentScore': 2, 'wrongScore': 1},
      );
      await Future<void>.delayed(Duration.zero);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _auctionGame(phase: 2, currentScore: 2),
      );
      await Future<void>.delayed(Duration.zero);

      final state = current();
      expect(state.answeringPlayerId, _localId, reason: 'carried through');
      expect(state.goalScore, 6, reason: 'carried through');
      expect(state.wrongScore, 1, reason: 'carried through');
    });

    test('a game with no auction metadata leaves auction state untouched',
        () async {
      await enterAuction();
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 2},
      );
      await Future<void>.delayed(Duration.zero);

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _auctionGame(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().auctionPhase, AuctionPhase.answering);
      expect(current().goalScore, 2);
    });
  });

  group('NextRoundStarted is the reset boundary', () {
    /// Drives a round to the end of its answer phase, so there is real
    /// previous-round state to reset.
    Future<void> populatePreviousRound() async {
      await enterAuction(phase: 2);
      bindings.emit(
        PlayGameHubEvents.playerBidded,
        {'playerId': _opponentId, 'bidValue': 4},
      );
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 4},
      );
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {
          'playerId': _localId,
          'currentScore': 3,
          'goalScore': 4,
          'wrongScore': 2,
        },
      );
      bindings.emit(
        PlayGameHubEvents.playerWonAuctionRound,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> nextRoundStarted(int roundType) async {
      bindings.emit(
        PlayGameHubEvents.nextRoundStarted,
        HubEventPayload.mapFromArgs([roundType, 'g1']),
      );
      await Future<void>.delayed(Duration.zero);
    }

    test('the previous round really was populated', () async {
      await populatePreviousRound();

      final state = current();
      expect(state.currentBid, 4);
      expect(state.currentScore, 3);
      expect(state.goalScore, 4);
      expect(state.wrongScore, 2);
      expect(state.answeringPlayerId, _localId);
      expect(state.auctionResult, AuctionResult.won);
      expect(state.auctionPhase, AuctionPhase.answering);
      expect(state.game?.currentQuestion, isNotNull);
      expect(state.game?.currentTurn, isNotEmpty);
    });

    test(
        'R-09: populated Auction state survives RoundFinished into '
        'GamePhase.finishRound completely unchanged (intentionally '
        'retained — showPhase carries every one of these fields through '
        'as state.X regardless of the new phase), and still resets '
        'correctly once NextRoundStarted actually fires — the reset '
        'boundary is NextRoundStarted, not the finishRound phase change',
        () async {
      await populatePreviousRound();

      bindings.emit(PlayGameHubEvents.roundFinished, null);
      await Future<void>.delayed(Duration.zero);

      final duringFinishRound = current();
      expect(duringFinishRound.phase, GamePhase.finishRound, reason: 'sanity');
      expect(duringFinishRound.currentBid, 4);
      expect(duringFinishRound.currentScore, 3);
      expect(duringFinishRound.goalScore, 4);
      expect(duringFinishRound.wrongScore, 2);
      expect(duringFinishRound.answeringPlayerId, _localId);
      expect(duringFinishRound.auctionResult, AuctionResult.won);
      expect(duringFinishRound.auctionPhase, AuctionPhase.answering);

      await nextRoundStarted(2);

      final afterNextRound = current();
      expect(afterNextRound.currentBid, isNull);
      expect(afterNextRound.currentScore, isNull);
      expect(afterNextRound.goalScore, isNull);
      expect(afterNextRound.wrongScore, isNull);
      expect(afterNextRound.answeringPlayerId, isNull);
      expect(afterNextRound.auctionResult, AuctionResult.none);
      expect(afterNextRound.auctionPhase, isNull);
    });

    test('every round-scoped value is reset immediately', () async {
      await populatePreviousRound();

      await nextRoundStarted(2);

      final state = current();
      expect(state.currentBid, isNull);
      expect(state.currentScore, isNull);
      expect(state.goalScore, isNull);
      expect(state.wrongScore, isNull);
      expect(state.answeringPlayerId, isNull);
      expect(state.auctionResult, AuctionResult.none);
      expect(state.auctionPhase, isNull);
      expect(state.isBiding, isTrue, reason: 'raising is open again');
      expect(state.game?.currentQuestion, isNull, reason: 'answers cleared');
      expect(state.game?.currentTurn, isEmpty,
          reason: 'Native clears isTurnPlaying here');
      expect(state.isMyTurn, isFalse);
      expect(state.isOpponentTurn, isFalse);
    });

    test('the reset happens on the event, not on a later GameUpdated',
        () async {
      await populatePreviousRound();
      await nextRoundStarted(2);

      // Nothing else has arrived yet, and the state is already clean.
      expect(current().lastEventName, PlayGameHubEvents.nextRoundStarted);
      expect(current().auctionPhase, isNull);
      expect(current().currentBid, isNull);
    });

    test('the new round then runs its normal bidding flow', () async {
      await populatePreviousRound();
      await nextRoundStarted(2);
      expect(current().phase, GamePhase.auction);

      // The server opens the new question.
      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _auctionGame(phase: 1),
      );
      bindings.emit(
        PlayGameHubEvents.auctionBiddingPhaseStarted,
        {'arg0': 'g1'},
      );
      bindings.emit(
        PlayGameHubEvents.changeTurn,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().auctionPhase, AuctionPhase.bidding);
      expect(current().isMyTurn, isTrue);
      expect(notifier().canBid, isTrue);
      expect(notifier().auctionMinBid, 1, reason: 'bidding starts from 1');

      bindings.emit(
        PlayGameHubEvents.playerBidded,
        {'playerId': _localId, 'bidValue': 2},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().currentBid, 2);
    });

    test('a round change to another type resets auction state too', () async {
      await populatePreviousRound();

      await nextRoundStarted(3); // bell

      expect(current().phase, GamePhase.bell);
      expect(current().auctionPhase, isNull);
      expect(current().currentBid, isNull);
      expect(current().answeringPlayerId, isNull);
      expect(current().auctionResult, AuctionResult.none);
    });

    test('a WDYK round is reset the same way, with no auction leakage',
        () async {
      await populatePreviousRound();

      await nextRoundStarted(1);

      expect(current().phase, GamePhase.wdyk);
      expect(current().game?.currentQuestion, isNull);
      expect(current().game?.currentTurn, isEmpty);
      expect(current().auctionPhase, isNull);
      expect(current().wrongScore, isNull);
    });

    test('the roster and match score survive the reset', () async {
      await populatePreviousRound();

      await nextRoundStarted(2);

      expect(current().me?.id, _localId,
          reason: 'seating is not round-scoped');
      expect(current().opponent?.id, _opponentId);
      expect(current().game?.id, 'g1');
    });
  });

  group('routing keeps existing rounds untouched', () {
    test('auction events do not disturb the game or the timer', () async {
      await enterAuction(phase: 1);
      bindings.emit(
        PlayGameHubEvents.timerUpdatedSeconds,
        {'arg0': 10, 'arg1': 'g1'},
      );
      await Future<void>.delayed(Duration.zero);
      final timerBefore = current().game?.currentTimerValue;

      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseStarted,
        {'playerId': _localId, 'bidValue': 3},
      );
      bindings.emit(
        PlayGameHubEvents.auctionAnswerPhaseScoreUpdate,
        {'playerId': _localId, 'currentScore': 1},
      );
      await Future<void>.delayed(Duration.zero);

      expect(current().game?.currentTimerValue, timerBefore);
      expect(current().game?.isTimerStarted, isTrue,
          reason: 'no auction event starts or stops the timer — the flag is '
              'the one TimerUpdatedSeconds set, carried through untouched');
      expect(current().phase, GamePhase.auction);
    });

    test('a WDYK game is unaffected by the auction routing', () async {
      notifier().applySessionEvent(PlayGameHubEvents.gameStarted, {
        'id': 'g1',
        'status': 3,
        'type': 1,
        'players': [
          {'id': _localId, 'playerName': 'me'},
          {'id': _opponentId, 'playerName': 'them'},
        ],
      });
      await Future<void>.delayed(Duration.zero);

      expect(current().phase, GamePhase.wdyk);
      expect(current().auctionPhase, isNull);
      expect(current().auctionResult, AuctionResult.none);
    });
  });
}
