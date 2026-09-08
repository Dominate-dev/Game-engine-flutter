import 'package:flutter_test/flutter_test.dart';
import 'package:play_game/play_game.dart';

// Identity matching primitives. These assert the comparison contract only.
//
// IMPORTANT: which hub field carries which identity (game-player id vs account
// id) is EXTERNAL VERIFICATION REQUIRED and is deliberately NOT encoded here.
// These tests fix the behaviour of the comparison itself, not the meaning of
// the values compared.

GamePlayer _player({required String id, String? userId}) => GamePlayer(
      id: id,
      userId: userId,
      playerName: 'p',
      penalty: 0,
      points: 0,
      isReady: false,
      makeupTryCount: 0,
      maxMakeupTryCount: 3,
    );

GameOverResult _gameOver({required String winnerId}) => GameOverResult(
      gameId: 'g1',
      isPrivate: false,
      winnerId: winnerId,
      gameResultPlayers: const [],
    );

void main() {
  group('playerIdsEqual', () {
    test('equal ids match', () {
      expect(playerIdsEqual('47', '47'), isTrue);
    });

    test('surrounding whitespace is ignored on either side', () {
      expect(playerIdsEqual(' 47 ', '47'), isTrue);
      expect(playerIdsEqual('47', ' 47 '), isTrue);
    });

    test('numerically equal ids match despite formatting', () {
      expect(playerIdsEqual('007', '7'), isTrue);
    });

    test('different ids do not match', () {
      expect(playerIdsEqual('47', '211403'), isFalse);
    });

    test('empty or null on either side never matches', () {
      expect(playerIdsEqual(null, '47'), isFalse);
      expect(playerIdsEqual('47', null), isFalse);
      expect(playerIdsEqual('', '47'), isFalse);
      expect(playerIdsEqual('47', ''), isFalse);
      expect(playerIdsEqual('   ', '47'), isFalse);
    });

    test('non-numeric ids compare exactly, not numerically', () {
      const guid = 'a3f1c2d4-0000-4aaa-bbbb-000000000001';
      expect(playerIdsEqual(guid, guid), isTrue);
      expect(playerIdsEqual(guid, 'a3f1c2d4'), isFalse);
    });

    test('ids beyond int range still compare exactly', () {
      const long = '118257441539724769068';
      expect(playerIdsEqual(long, long), isTrue);
      expect(playerIdsEqual(long, '118257441539724769069'), isFalse);
    });
  });

  group('GamePlayer.matchesHubUserId', () {
    test('matches on the player id', () {
      expect(_player(id: '47').matchesHubUserId('47'), isTrue);
    });

    test('matches on the account userId when ids differ', () {
      final player = _player(id: 'guid-1', userId: '47');
      expect(player.matchesHubUserId('47'), isTrue);
    });

    test('does not match an unrelated id', () {
      final player = _player(id: 'guid-1', userId: '47');
      expect(player.matchesHubUserId('211403'), isFalse);
    });

    test('null candidate never matches', () {
      expect(_player(id: '47', userId: '47').matchesHubUserId(null), isFalse);
    });

    test('a player without userId still matches on id alone', () {
      expect(_player(id: '47').matchesHubUserId('47'), isTrue);
      expect(_player(id: '47').matchesHubUserId('99'), isFalse);
    });
  });

  group('GameOverResult.isWinner', () {
    test('true when the winnerId is the given user', () {
      expect(_gameOver(winnerId: '47').isWinner('47'), isTrue);
    });

    test('false for a different user', () {
      expect(_gameOver(winnerId: '47').isWinner('211403'), isFalse);
    });

    test('false for a null or empty user id', () {
      expect(_gameOver(winnerId: '47').isWinner(null), isFalse);
      expect(_gameOver(winnerId: '47').isWinner(''), isFalse);
    });

    test('false, and does not throw, when no winner was named', () {
      expect(_gameOver(winnerId: '').isWinner('47'), isFalse);
    });
  });

  group('GameOverResult.hasKnownWinner', () {
    test('true when a winner is named', () {
      expect(_gameOver(winnerId: '47').hasKnownWinner, isTrue);
    });

    test('false for an empty or whitespace-only winnerId', () {
      expect(_gameOver(winnerId: '').hasKnownWinner, isFalse);
      expect(_gameOver(winnerId: '   ').hasKnownWinner, isFalse);
    });

    // The distinction this getter exists for: isWinner() returning false
    // cannot by itself tell "nobody won" apart from "you did not win".
    test('separates an unknown outcome from a defeat', () {
      final unknown = _gameOver(winnerId: '');
      expect(unknown.hasKnownWinner, isFalse);
      expect(unknown.isWinner('47'), isFalse);

      final lost = _gameOver(winnerId: '211403');
      expect(lost.hasKnownWinner, isTrue);
      expect(lost.isWinner('47'), isFalse);
    });

    // R-13 (final audit): isWinner previously compared with raw `==`
    // instead of playerIdsEqual, so formatting drift playerIdsEqual
    // tolerates (whitespace, numeric-string variants) was treated as "not
    // the winner" — a real risk, since winnerId is hub-JSON-sourced
    // (GameJson.string, no trim/normalization) while callers' userId is
    // prefs-sourced, the exact hub-vs-prefs mismatch class playerIdsEqual
    // exists for. GameSessionState.winnerPlayer already compared this same
    // winnerId safely via GamePlayer.matchesHubUserId — isWinner was the
    // one place still comparing it raw. Fixed to use playerIdsEqual, same
    // as every other identity comparison in this codebase.
    test(
      'whitespace in winnerId now matches, the same as playerIdsEqual',
      () {
        expect(playerIdsEqual(' 47 ', '47'), isTrue);
        expect(_gameOver(winnerId: ' 47 ').isWinner('47'), isTrue);
      },
    );

    test(
      'a numerically-equal but differently-formatted winnerId now matches '
      'too',
      () {
        expect(_gameOver(winnerId: '007').isWinner('7'), isTrue);
      },
    );

    test('a genuinely different winnerId still does not match', () {
      expect(_gameOver(winnerId: '47').isWinner('211403'), isFalse);
    });
  });
}
