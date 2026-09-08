import 'package:flutter_test/flutter_test.dart';
import 'package:play_game/play_game.dart';

// Domain enum mapping. Every alias asserted here is one the repository
// declares explicitly; no hub payload shape is assumed.

void main() {
  group('GameType.fromId', () {
    test('maps the declared round ids', () {
      expect(GameType.fromId(1), GameType.wdyk);
      expect(GameType.fromId(2), GameType.auction);
      expect(GameType.fromId(3), GameType.bell);
      expect(GameType.fromId(4), GameType.comeBack);
      expect(GameType.fromId(5), GameType.breaker);
    });

    test('unknown or null id yields null rather than a default round', () {
      expect(GameType.fromId(0), isNull);
      expect(GameType.fromId(99), isNull);
      expect(GameType.fromId(null), isNull);
    });

    test('each type exposes its matching phase', () {
      expect(GameType.wdyk.phase, GamePhase.wdyk);
      expect(GameType.auction.phase, GamePhase.auction);
      expect(GameType.bell.phase, GamePhase.bell);
      expect(GameType.comeBack.phase, GamePhase.comeBack);
      expect(GameType.breaker.phase, GamePhase.breaker);
    });
  });

  group('StatusGame.fromId', () {
    test('maps the declared status ids', () {
      expect(StatusGame.fromId(1), StatusGame.waitingPlayers);
      expect(StatusGame.fromId(2), StatusGame.isReady);
      expect(StatusGame.fromId(3), StatusGame.inProgress);
      expect(StatusGame.fromId(4), StatusGame.ended);
    });

    test('unknown or null id yields null', () {
      expect(StatusGame.fromId(0), isNull);
      expect(StatusGame.fromId(5), isNull);
      expect(StatusGame.fromId(null), isNull);
    });
  });

  group('TypePenalty.fromId', () {
    test('maps the declared penalty ids', () {
      expect(TypePenalty.fromId(1), TypePenalty.timeout);
      expect(TypePenalty.fromId(2), TypePenalty.wrongAnswer);
    });

    test('unknown or null id yields null', () {
      expect(TypePenalty.fromId(0), isNull);
      expect(TypePenalty.fromId(3), isNull);
      expect(TypePenalty.fromId(null), isNull);
    });
  });

  group('GamePhase.fromHubValue', () {
    test('resolves every declared textual alias', () {
      expect(GamePhase.fromHubValue('waiting'), GamePhase.waiting);
      expect(GamePhase.fromHubValue('wait'), GamePhase.waiting);
      expect(GamePhase.fromHubValue('lobby'), GamePhase.lobbyPlay);
      expect(GamePhase.fromHubValue('lobbyPlay'), GamePhase.lobbyPlay);
      expect(GamePhase.fromHubValue('lobby_play'), GamePhase.lobbyPlay);
      expect(GamePhase.fromHubValue('playLobby'), GamePhase.lobbyPlay);
      expect(GamePhase.fromHubValue('wdyk'), GamePhase.wdyk);
      expect(GamePhase.fromHubValue('whatDoYouKnow'), GamePhase.wdyk);
      expect(GamePhase.fromHubValue('what_do_you_know'), GamePhase.wdyk);
      expect(GamePhase.fromHubValue('auction'), GamePhase.auction);
      expect(GamePhase.fromHubValue('bell'), GamePhase.bell);
      expect(GamePhase.fromHubValue('comeBack'), GamePhase.comeBack);
      expect(GamePhase.fromHubValue('come_back'), GamePhase.comeBack);
      expect(GamePhase.fromHubValue('breaker'), GamePhase.breaker);
      expect(GamePhase.fromHubValue('finish'), GamePhase.finishRound);
      expect(GamePhase.fromHubValue('finishRound'), GamePhase.finishRound);
      expect(GamePhase.fromHubValue('finish_round'), GamePhase.finishRound);
    });

    test('aliases are case and whitespace insensitive', () {
      expect(GamePhase.fromHubValue('  AUCTION  '), GamePhase.auction);
      expect(GamePhase.fromHubValue('BeLl'), GamePhase.bell);
    });

    test('falls back to a numeric round type', () {
      expect(GamePhase.fromHubValue(1), GamePhase.wdyk);
      expect(GamePhase.fromHubValue('2'), GamePhase.auction);
      expect(GamePhase.fromHubValue(5), GamePhase.breaker);
    });

    test('null, empty and unrecognised values yield null', () {
      expect(GamePhase.fromHubValue(null), isNull);
      expect(GamePhase.fromHubValue(''), isNull);
      expect(GamePhase.fromHubValue('   '), isNull);
      expect(GamePhase.fromHubValue('somethingElse'), isNull);
      expect(GamePhase.fromHubValue(99), isNull);
    });
  });

  group('GamePhase.fromHubEvent', () {
    test('game-over events resolve to no phase', () {
      for (final event in PlayGameHubEvents.gameOverEvents) {
        expect(
          GamePhase.fromHubEvent(event),
          isNull,
          reason: '$event must not select a round phase',
        );
      }
    });

    test('every auction event resolves to the auction phase', () {
      for (final event in PlayGameHubEvents.auctionEvents) {
        expect(
          GamePhase.fromHubEvent(event),
          GamePhase.auction,
          reason: '$event should route to auction',
        );
      }
    });

    test('roundFinished resolves to the finish phase', () {
      expect(
        GamePhase.fromHubEvent(PlayGameHubEvents.roundFinished),
        GamePhase.finishRound,
      );
    });

    test('nextRoundStarted yields no phase; the round type decides it', () {
      expect(
        GamePhase.fromHubEvent(PlayGameHubEvents.nextRoundStarted),
        isNull,
      );
    });

    test('an unrelated event name yields no phase', () {
      expect(GamePhase.fromHubEvent('SomeUnknownEvent'), isNull);
    });
  });
}
