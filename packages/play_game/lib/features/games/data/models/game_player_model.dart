import '../../domain/entities/game_player.dart';
import 'game_json.dart';

abstract final class GamePlayerModel {
  static GamePlayer fromJson(Map<String, dynamic> json) {
    final id = GameJson.string(json, 'id');
    final userId = GameJson.stringOrNull(json, 'userId');
    return GamePlayer(
      id: id.isNotEmpty ? id : (userId ?? ''),
      userId: userId,
      playerName: GameJson.string(json, 'playerName'),
      profileImageUrl: GameJson.stringOrNull(json, 'profileImageUrl'),
      penalty: GameJson.integer(json, 'penalty'),
      points: GameJson.integer(json, 'points'),
      passes: GameJson.integer(json, 'passes'),
      isReady: GameJson.boolean(json, 'isReady'),
      makeupTryCount: GameJson.integer(json, 'makeupTryCount'),
      maxMakeupTryCount: GameJson.integer(json, 'maxMakeupTryCount'),
      isBot: GameJson.boolean(json, 'isBot'),
    );
  }
}
