import 'package:flutter_test/flutter_test.dart';
import 'package:play_game/play_game.dart';
// Data-layer models are no longer exported from the package barrel (A3);
// imported by path rather than widening it.
import 'package:play_game/features/games/data/models/created_game_model.dart';
import 'package:play_game/features/games/data/models/game_over_result_model.dart';

// Payload shape DETECTION and partial-merge behaviour.
//
// The maps below are constructed by the test, not sampled from the hub. These
// assert how the client classifies and merges a map it is handed; they do NOT
// assert that the backend sends any particular shape — that remains EXTERNAL
// VERIFICATION REQUIRED.

CreatedGame _game({
  String id = 'g1',
  int status = 1,
  int type = 1,
  double currentTimerValue = 0,
  String? currentTurn,
  List<GamePlayer>? players,
}) =>
    CreatedGame(
      id: id,
      status: status,
      mode: 0,
      currentTimerValue: currentTimerValue,
      groupId: 'grp',
      isPrivate: false,
      showInterests: false,
      multipleInterests: false,
      type: type,
      currentTurn: currentTurn,
      players: players,
    );

void main() {
  group('CreatedGameModel.looksLikeCreatedGame', () {
    test('accepts maps carrying any game-shaped key', () {
      for (final key in [
        'id',
        'players',
        'currentQuestion',
        'currentTimerValue',
        'currentTurn',
        'status',
      ]) {
        expect(
          CreatedGameModel.looksLikeCreatedGame({key: 'x'}),
          isTrue,
          reason: 'key $key should identify a game payload',
        );
      }
    });

    test('rejects a map with no game-shaped key', () {
      expect(CreatedGameModel.looksLikeCreatedGame({'unrelated': 1}), isFalse);
      expect(CreatedGameModel.looksLikeCreatedGame({}), isFalse);
    });

    test('a bare question payload is not treated as a game', () {
      final question = {'answers': <dynamic>[], 'questionNumber': 2};
      expect(CreatedGameModel.looksLikeCurrentQuestion(question), isTrue);
      expect(CreatedGameModel.looksLikeCreatedGame(question), isFalse);
    });

    test('a game that also carries question keys is still a game', () {
      final gameWithQuestion = {
        'answers': <dynamic>[],
        'status': 3,
        'groupId': 'grp',
      };
      expect(
        CreatedGameModel.looksLikeCurrentQuestion(gameWithQuestion),
        isFalse,
      );
      expect(
        CreatedGameModel.looksLikeCreatedGame(gameWithQuestion),
        isTrue,
      );
    });

    test('detection accepts PascalCase keys', () {
      expect(CreatedGameModel.looksLikeCreatedGame({'Status': 3}), isTrue);
    });
  });

  group('CreatedGameModel.merge', () {
    test('with no previous game the payload is parsed wholesale', () {
      final merged = CreatedGameModel.merge(null, {'id': 'g9', 'status': 3});
      expect(merged.id, 'g9');
      expect(merged.status, 3);
    });

    test('keys absent from the payload keep their previous values', () {
      final previous = _game(id: 'g1', status: 2, type: 4, currentTurn: '47');
      final merged = CreatedGameModel.merge(previous, {'status': 3});
      expect(merged.status, 3, reason: 'present key overlays');
      expect(merged.id, 'g1', reason: 'absent key preserved');
      expect(merged.type, 4, reason: 'absent key preserved');
      expect(merged.currentTurn, '47', reason: 'absent key preserved');
    });

    test('an explicit empty currentTurn clears the previous turn', () {
      final previous = _game(currentTurn: '47');
      final merged = CreatedGameModel.merge(previous, {'currentTurn': ''});
      // '' is the established "nobody may act" sentinel — same meaning as
      // null everywhere downstream.
      expect(merged.currentTurn, '');
    });

    test('a non-empty currentTurn replaces the previous turn', () {
      final previous = _game(currentTurn: '47');
      final merged =
          CreatedGameModel.merge(previous, {'currentTurn': '211403'});
      expect(merged.currentTurn, '211403');
    });

    test('a present key overlays even when its value is falsy', () {
      final previous = _game(status: 3);
      final merged = CreatedGameModel.merge(previous, {'status': 0});
      expect(merged.status, 0);
    });

    test('a players list in the payload replaces the roster', () {
      final previous = _game(
        players: [
          const GamePlayer(
            id: '47',
            playerName: 'a',
            penalty: 0,
            points: 0,
            isReady: false,
            makeupTryCount: 0,
            maxMakeupTryCount: 3,
          ),
        ],
      );
      final merged = CreatedGameModel.merge(previous, {
        'players': [
          {'id': '48', 'playerName': 'b'},
        ],
      });
      expect(merged.players?.map((p) => p.id), ['48']);
    });

    test('a negative timer value does not overwrite the previous one', () {
      final previous = _game(currentTimerValue: 12);
      final merged =
          CreatedGameModel.merge(previous, {'currentTimerValue': -1});
      expect(merged.currentTimerValue, 12);
    });

    test('a zero timer value does overwrite', () {
      final previous = _game(currentTimerValue: 12);
      final merged =
          CreatedGameModel.merge(previous, {'currentTimerValue': 0});
      expect(merged.currentTimerValue, 0);
    });

    test('merging an empty payload preserves the previous game', () {
      final previous = _game(id: 'g1', status: 2, type: 4);
      final merged = CreatedGameModel.merge(previous, {});
      expect(merged.id, 'g1');
      expect(merged.status, 2);
      expect(merged.type, 4);
    });
  });

  group('GameOverResultModel.looksLikeGameOver', () {
    test('accepts maps carrying either game-over key', () {
      expect(
        GameOverResultModel.looksLikeGameOver({'winnerId': '47'}),
        isTrue,
      );
      expect(
        GameOverResultModel.looksLikeGameOver({'gameResultPlayers': <dynamic>[]}),
        isTrue,
      );
    });

    test('accepts PascalCase keys', () {
      expect(
        GameOverResultModel.looksLikeGameOver({'WinnerId': '47'}),
        isTrue,
      );
    });

    test('rejects an unrelated map', () {
      expect(GameOverResultModel.looksLikeGameOver({'status': 3}), isFalse);
      expect(GameOverResultModel.looksLikeGameOver({}), isFalse);
    });
  });
}
