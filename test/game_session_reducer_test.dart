import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:play_game/play_game.dart';
// Not exported from the package barrel; imported by path rather than widening it.
import 'package:play_game/presentation/game_controller/game_session_reducer.dart';

// Pure merge helpers. Inputs are constructed here, so no hub payload shape is
// assumed — these fix the merge contract for maps the caller supplies.

GamePlayer _player({
  required String id,
  String? userId,
  bool isReady = false,
}) =>
    GamePlayer(
      id: id,
      userId: userId,
      playerName: 'p$id',
      penalty: 0,
      points: 0,
      isReady: isReady,
      makeupTryCount: 0,
      maxMakeupTryCount: 3,
    );

CreatedGame _game({
  List<GamePlayer>? players,
  bool? waitingToBeReadyTimerStart,
}) =>
    CreatedGame(
      id: 'g1',
      status: 2,
      mode: 0,
      currentTimerValue: 0,
      groupId: 'grp',
      isPrivate: false,
      showInterests: false,
      multipleInterests: false,
      type: 1,
      players: players,
      waitingToBeReadyTimerStart: waitingToBeReadyTimerStart,
    );

void main() {
  group('playerIdFrom', () {
    test('reads the documented keys in priority order', () {
      expect(GameSessionReducer.playerIdFrom({'playerId': '47'}), '47');
      expect(GameSessionReducer.playerIdFrom({'userId': '48'}), '48');
      expect(GameSessionReducer.playerIdFrom({'leftPlayerId': '49'}), '49');
    });

    test('playerId wins when several keys are present', () {
      final id = GameSessionReducer.playerIdFrom({
        'playerId': '47',
        'userId': '48',
        'leftPlayerId': '49',
      });
      expect(id, '47');
    });

    test('accepts PascalCase keys', () {
      expect(GameSessionReducer.playerIdFrom({'PlayerId': '47'}), '47');
    });

    test('trims surrounding whitespace', () {
      expect(GameSessionReducer.playerIdFrom({'playerId': '  47 '}), '47');
    });

    test('null map, empty values and unrelated keys yield null', () {
      expect(GameSessionReducer.playerIdFrom(null), isNull);
      expect(GameSessionReducer.playerIdFrom({'playerId': ''}), isNull);
      expect(GameSessionReducer.playerIdFrom({'playerId': '   '}), isNull);
      expect(GameSessionReducer.playerIdFrom({'other': '47'}), isNull);
    });

    test('numeric values are accepted and stringified', () {
      expect(GameSessionReducer.playerIdFrom({'playerId': 47}), '47');
    });

    // S9c: PlayerLeft/PlayerReady arrive as positional [playerId, gameId],
    // which HubEventPayload normalises to {'arg0': …}. Reading only the named
    // keys yielded null, so those events resolved to no player at all.
    test('resolves the id from a positional payload', () {
      final positional = HubEventPayload.mapFromArgs(['47', 'g1']);
      expect(GameSessionReducer.playerIdFrom(positional), '47');
    });

    test('positional and map-shaped payloads resolve to the same id', () {
      final positional = HubEventPayload.mapFromArgs(['211403', 'g1']);
      expect(
        GameSessionReducer.playerIdFrom(positional),
        GameSessionReducer.playerIdFrom({'playerId': '211403'}),
      );
    });

    test('a named key still wins over the positional argument', () {
      final id = GameSessionReducer.playerIdFrom({
        'playerId': '47',
        'arg0': '211403',
      });
      expect(id, '47');
    });

    test('an empty positional argument yields null', () {
      expect(GameSessionReducer.playerIdFrom({'arg0': ''}), isNull);
      expect(GameSessionReducer.playerIdFrom({'arg0': '   '}), isNull);
    });
  });

  group('turnPlayerIdFrom', () {
    test('prefers a named id over the positional argument', () {
      final id = GameSessionReducer.turnPlayerIdFrom({
        'playerId': '47',
        'arg0': '99',
      });
      expect(id, '47');
    });

    test('falls back to the positional argument', () {
      expect(GameSessionReducer.turnPlayerIdFrom({'arg0': '99'}), '99');
    });

    test('null map and empty positional argument yield null', () {
      expect(GameSessionReducer.turnPlayerIdFrom(null), isNull);
      expect(GameSessionReducer.turnPlayerIdFrom({'arg0': ''}), isNull);
      expect(GameSessionReducer.turnPlayerIdFrom({}), isNull);
    });
  });

  group('timerValueFrom', () {
    test('reads the positional argument first', () {
      expect(GameSessionReducer.timerValueFrom({'arg0': 12}), 12.0);
    });

    test('falls back to named seconds, then currentTimerValue', () {
      expect(GameSessionReducer.timerValueFrom({'seconds': 8}), 8.0);
      expect(
        GameSessionReducer.timerValueFrom({'currentTimerValue': 5.5}),
        5.5,
      );
    });

    test('parses numeric strings', () {
      expect(GameSessionReducer.timerValueFrom({'arg0': '7.5'}), 7.5);
    });

    test('null map and unparseable values yield null', () {
      expect(GameSessionReducer.timerValueFrom(null), isNull);
      expect(GameSessionReducer.timerValueFrom({}), isNull);
      expect(GameSessionReducer.timerValueFrom({'arg0': 'abc'}), isNull);
    });
  });

  group('roundTypeFrom', () {
    test('reads the positional argument first', () {
      expect(GameSessionReducer.roundTypeFrom({'arg0': 3}), 3);
    });

    test('falls back to a named type', () {
      expect(GameSessionReducer.roundTypeFrom({'type': 2}), 2);
    });

    test('null map and unparseable values yield null', () {
      expect(GameSessionReducer.roundTypeFrom(null), isNull);
      expect(GameSessionReducer.roundTypeFrom({}), isNull);
      expect(GameSessionReducer.roundTypeFrom({'arg0': 'abc'}), isNull);
    });
  });

  group('emoteFrom', () {
    test('builds an emote from a player id and image key', () {
      final emote = GameSessionReducer.emoteFrom({
        'playerId': '47',
        'path': 'stickers/a.png',
      });
      expect(emote, isNotNull);
      expect(emote!.playerId, '47');
      expect(emote.imageUrl, 'stickers/a.png');
    });

    test('accepts each documented image key', () {
      for (final key in ['emoji', 'path', 'imageUrl', 'stickerPath', 'url']) {
        final emote = GameSessionReducer.emoteFrom({
          'playerId': '47',
          key: 'img/$key.png',
        });
        expect(emote?.imageUrl, 'img/$key.png', reason: 'key $key');
      }
    });

    test('reads a nested image object', () {
      final emote = GameSessionReducer.emoteFrom({
        'playerId': '47',
        'emoji': {'path': 'nested/a.png'},
      });
      expect(emote?.imageUrl, 'nested/a.png');
    });

    test('falls back to an id key when no player id key is present', () {
      final emote = GameSessionReducer.emoteFrom({'id': '47'});
      expect(emote?.playerId, '47');
    });

    test('an emote without an image is still produced', () {
      final emote = GameSessionReducer.emoteFrom({'playerId': '47'});
      expect(emote, isNotNull);
      expect(emote!.imageUrl, isNull);
    });

    test('null map or no identifiable player yields null', () {
      expect(GameSessionReducer.emoteFrom(null), isNull);
      expect(GameSessionReducer.emoteFrom({}), isNull);
      expect(GameSessionReducer.emoteFrom({'path': 'a.png'}), isNull);
    });
  });

  group('shouldStopReadyTimer', () {
    test('a running timer flag on the game keeps the timer running', () {
      final game = _game(waitingToBeReadyTimerStart: true);
      expect(GameSessionReducer.shouldStopReadyTimer(null, game), isFalse);
    });

    test('a stopped timer flag on the game stops the timer', () {
      final game = _game(waitingToBeReadyTimerStart: false);
      expect(GameSessionReducer.shouldStopReadyTimer(null, game), isTrue);
    });

    test('the game flag wins over the payload', () {
      final game = _game(waitingToBeReadyTimerStart: true);
      final stop = GameSessionReducer.shouldStopReadyTimer(
        {'waitingToBeReadyTimerStart': false},
        game,
      );
      expect(stop, isFalse);
    });

    test('falls back to the payload when the game has no flag', () {
      expect(
        GameSessionReducer.shouldStopReadyTimer(
          {'waitingToBeReadyTimerStart': false},
          null,
        ),
        isTrue,
      );
      expect(
        GameSessionReducer.shouldStopReadyTimer(
          {'waitingToBeReadyTimerStart': true},
          null,
        ),
        isFalse,
      );
    });

    test('no game and no payload does not stop the timer', () {
      expect(GameSessionReducer.shouldStopReadyTimer(null, null), isFalse);
      expect(GameSessionReducer.shouldStopReadyTimer({}, null), isFalse);
    });
  });

  group('gameAfterPlayerLeft', () {
    test('a payload carrying a players list replaces the game wholesale', () {
      final parsed = _game(players: [_player(id: '47')]);
      final current = _game(players: [_player(id: '47'), _player(id: '48')]);
      final result = GameSessionReducer.gameAfterPlayerLeft(
        {'players': <dynamic>[]},
        parsed,
        current,
      );
      expect(result, same(parsed));
    });

    test('without a players list the named player is removed', () {
      final current = _game(players: [_player(id: '47'), _player(id: '48')]);
      final result = GameSessionReducer.gameAfterPlayerLeft(
        {'playerId': '48'},
        null,
        current,
      );
      expect(result?.players?.map((p) => p.id), ['47']);
    });

    test('removal matches on the account userId too', () {
      final current = _game(
        players: [_player(id: 'guid-1', userId: '47'), _player(id: '48')],
      );
      final result = GameSessionReducer.gameAfterPlayerLeft(
        {'playerId': '47'},
        null,
        current,
      );
      expect(result?.players?.map((p) => p.id), ['48']);
    });

    test('an unknown player id leaves the roster unchanged', () {
      final current = _game(players: [_player(id: '47'), _player(id: '48')]);
      final result = GameSessionReducer.gameAfterPlayerLeft(
        {'playerId': '999'},
        null,
        current,
      );
      expect(result?.players?.map((p) => p.id), ['47', '48']);
    });

    test('no identifiable player keeps the current game', () {
      final current = _game(players: [_player(id: '47')]);
      final result =
          GameSessionReducer.gameAfterPlayerLeft({}, null, current);
      expect(result, same(current));
    });
  });

  group('gameAfterPlayerReady', () {
    test('a payload carrying a players list replaces the game wholesale', () {
      final parsed = _game(players: [_player(id: '47', isReady: true)]);
      final current = _game(players: [_player(id: '47')]);
      final result = GameSessionReducer.gameAfterPlayerReady(
        {'players': <dynamic>[]},
        parsed,
        current,
      );
      expect(result, same(parsed));
    });

    test('marks only the named player ready', () {
      final current = _game(players: [_player(id: '47'), _player(id: '48')]);
      final result = GameSessionReducer.gameAfterPlayerReady(
        {'playerId': '48'},
        null,
        current,
      );
      final byId = {for (final p in result!.players!) p.id: p.isReady};
      expect(byId, {'47': false, '48': true});
    });

    test('an explicit isReady false unsets the flag', () {
      final current = _game(players: [_player(id: '47', isReady: true)]);
      final result = GameSessionReducer.gameAfterPlayerReady(
        {'playerId': '47', 'isReady': false},
        null,
        current,
      );
      expect(result?.players?.single.isReady, isFalse);
    });

    test('an unknown player id leaves ready flags unchanged', () {
      final current = _game(players: [_player(id: '47')]);
      final result = GameSessionReducer.gameAfterPlayerReady(
        {'playerId': '999'},
        null,
        current,
      );
      expect(result?.players?.single.isReady, isFalse);
    });

    test('no current game falls back to the parsed game', () {
      final parsed = _game(players: [_player(id: '47')]);
      final result = GameSessionReducer.gameAfterPlayerReady(
        {'playerId': '47'},
        parsed,
        null,
      );
      expect(result, same(parsed));
    });
  });
}
