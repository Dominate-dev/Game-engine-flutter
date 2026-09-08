import 'package:coreapp/coreapp.dart';

import '../../domain/game_session_state.dart';
import '../../features/games/domain/entities/created_game.dart';

// Pure merges for lobby / emote payloads. [GameController] owns state.
abstract final class GameSessionReducer {
  static CreatedGame? gameAfterPlayerLeft(
    Map<String, dynamic>? data,
    CreatedGame? parsed,
    CreatedGame? current,
  ) {
    final hasPlayersList =
        data != null && JsonValue.hasField(data, 'players');
    if (hasPlayersList) {
      return parsed;
    }
    final leftId = playerIdFrom(data);
    if (leftId == null || current == null) {
      return current ?? parsed;
    }
    return current.withoutPlayer(leftId);
  }

  static CreatedGame? gameAfterPlayerReady(
    Map<String, dynamic>? data,
    CreatedGame? parsed,
    CreatedGame? current,
  ) {
    if (data != null && JsonValue.hasField(data, 'players')) {
      return parsed;
    }
    return _applyPlayerReady(current, data) ?? parsed;
  }

  static bool shouldStopReadyTimer(
    Map<String, dynamic>? data,
    CreatedGame? game,
  ) {
    if (game?.waitingToBeReadyTimerStart == true) {
      return false;
    }
    if (game?.waitingToBeReadyTimerStart == false) {
      return true;
    }
    if (data == null) {
      return false;
    }
    final start = JsonValue.parseBool(
      JsonValue.field(data, 'waitingToBeReadyTimerStart'),
    );
    return start == false;
  }

  static PlayerEmote? emoteFrom(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final playerId = playerIdFrom(data) ??
        JsonValue.field(data, 'id')?.toString().trim() ??
        '';
    if (playerId.isEmpty) {
      return null;
    }
    return PlayerEmote(
      playerId: playerId,
      imageUrl: _emoteImageUrl(data),
    );
  }

  static String? playerIdFrom(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    for (final key in ['playerId', 'userId', 'leftPlayerId']) {
      final value = JsonValue.field(data, key)?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    // Positional payloads such as PlayerLeft/PlayerReady [playerId, gameId]
    // reach here as {'arg0': playerId} via HubEventPayload.mapFromArgs.
    final arg0 = data['arg0']?.toString().trim() ?? '';
    return arg0.isEmpty ? null : arg0;
  }

  // [ChangeTurn] may send `playerId` or positional `arg0`.
  static String? turnPlayerIdFrom(Map<String, dynamic>? data) {
    final named = playerIdFrom(data);
    if (named != null) {
      return named;
    }
    final arg0 = data?['arg0']?.toString().trim() ?? '';
    return arg0.isEmpty ? null : arg0;
  }

  // [TimerUpdatedSeconds] is positional: `args: [seconds, gameId]`.
  static double? timerValueFrom(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    final raw = data['arg0'] ??
        JsonValue.field(data, 'seconds') ??
        JsonValue.field(data, 'currentTimerValue');
    return JsonValue.parseDouble(raw);
  }

  // [NextRoundStarted] is positional: `args: [roundType, gameId]`.
  static int? roundTypeFrom(Map<String, dynamic>? data) {
    if (data == null) {
      return null;
    }
    return JsonValue.parseInt(data['arg0']) ??
        JsonValue.parseInt(JsonValue.field(data, 'type'));
  }

  static CreatedGame? _applyPlayerReady(
    CreatedGame? game,
    Map<String, dynamic>? data,
  ) {
    if (game == null || data == null) {
      return game;
    }
    if (JsonValue.hasField(data, 'players')) {
      return game;
    }
    final playerId = playerIdFrom(data);
    if (playerId == null) {
      return game;
    }
    final isReady = JsonValue.parseBool(JsonValue.field(data, 'isReady')) ?? true;
    final list = game.players;
    if (list == null) {
      return game;
    }
    return game.copyWith(
      players: [
        for (final player in list)
          if (player.matchesHubUserId(playerId))
            player.copyWith(isReady: isReady)
          else
            player,
      ],
    );
  }

  static String? _emoteImageUrl(Map<String, dynamic> data) {
    for (final key in ['emoji', 'path', 'imageUrl', 'stickerPath', 'url']) {
      final value = JsonValue.field(data, key);
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is Map) {
        final nested = JsonValue.asMap(value);
        for (final nestedKey in ['path', 'imageUrl', 'url']) {
          final nestedValue =
              JsonValue.field(nested, nestedKey)?.toString().trim() ?? '';
          if (nestedValue.isNotEmpty) {
            return nestedValue;
          }
        }
      }
    }
    return null;
  }
}
