import 'package:flutter_test/flutter_test.dart';
import 'package:play_game/play_game.dart';

// currentTurn names one player, or ALLOW_ALL for both. Anything else must
// fail safe and let neither act. Identity comparison itself stays strict.

const _localId = '47';
const _opponentId = '211403';

GamePlayer _player(String id) => GamePlayer(
      id: id,
      playerName: 'p$id',
      penalty: 0,
      points: 0,
      isReady: false,
      makeupTryCount: 0,
      maxMakeupTryCount: 0,
    );

GameSessionState _state({String? currentTurn, bool seatOpponent = true}) {
  return GameSessionState(
    phase: GamePhase.wdyk,
    game: CreatedGame(
      id: 'g1',
      status: 3,
      mode: 1,
      currentTimerValue: 0,
      groupId: 'grp',
      isPrivate: false,
      showInterests: false,
      multipleInterests: false,
      type: 1,
      currentTurn: currentTurn,
    ),
    me: _player(_localId),
    opponent: seatOpponent ? _player(_opponentId) : null,
  );
}

void main() {
  group('ALLOW_ALL', () {
    test('lets both players act', () {
      final state = _state(currentTurn: CreatedGame.allowAllTurn);
      expect(state.isMyTurn, isTrue);
      expect(state.isOpponentTurn, isTrue);
    });

    test('is matched exactly, with surrounding whitespace tolerated', () {
      expect(_state(currentTurn: ' ALLOW_ALL ').isMyTurn, isTrue);
    });

    test('the constant is the literal hub value', () {
      expect(CreatedGame.allowAllTurn, 'ALLOW_ALL');
    });
  });

  group('a named player id', () {
    test('lets only the local player act', () {
      final state = _state(currentTurn: _localId);
      expect(state.isMyTurn, isTrue);
      expect(state.isOpponentTurn, isFalse);
    });

    test('lets only the opponent act', () {
      final state = _state(currentTurn: _opponentId);
      expect(state.isMyTurn, isFalse);
      expect(state.isOpponentTurn, isTrue);
    });

    test('tolerates numeric formatting the way identity matching does', () {
      final state = _state(currentTurn: ' 47 ');
      expect(state.isMyTurn, isTrue);
      expect(state.isOpponentTurn, isFalse);
    });
  });

  group('unknown values fail safe', () {
    test('an unrecognised sentinel lets neither player act', () {
      for (final turn in ['ALLOW_NONE', 'allow_all', 'ALLOWALL', '900']) {
        final state = _state(currentTurn: turn);
        expect(state.isMyTurn, isFalse, reason: turn);
        expect(state.isOpponentTurn, isFalse, reason: turn);
      }
    });

    test('null and empty let neither player act', () {
      for (final turn in [null, '', '   ']) {
        final state = _state(currentTurn: turn);
        expect(state.isMyTurn, isFalse);
        expect(state.isOpponentTurn, isFalse);
      }
    });

    test('no game means neither player acts', () {
      const state = GameSessionState(phase: GamePhase.wdyk);
      expect(state.isMyTurn, isFalse);
      expect(state.isOpponentTurn, isFalse);
    });

    test('an unseated opponent never holds the turn', () {
      final state = _state(
        currentTurn: CreatedGame.allowAllTurn,
        seatOpponent: false,
      );
      expect(state.isMyTurn, isTrue);
      expect(state.isOpponentTurn, isFalse);
    });
  });

  group('identity helpers stay strict', () {
    test('ALLOW_ALL is not a player identity', () {
      expect(_player(_localId).matchesHubUserId(CreatedGame.allowAllTurn),
          isFalse);
      expect(playerIdsEqual(_localId, CreatedGame.allowAllTurn), isFalse);
    });
  });
}
