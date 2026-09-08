import '../../domain/entities/game_result_player.dart';
import 'game_json.dart';

abstract final class GameResultPlayerModel {
  static GameResultPlayer fromJson(Map<String, dynamic> json) {
    return GameResultPlayer(
      playerId: GameJson.string(json, 'playerId'),
      points: GameJson.integer(json, 'points'),
      strikes: GameJson.integer(json, 'strikes'),
      correctAnswersCount: GameJson.integer(json, 'correctAnswersCount'),
      wrongAnswersCount: GameJson.integer(json, 'wrongAnswersCount'),
      answersSpeed: GameJson.decimal(json, 'answersSpeed'),
      winningCoins: GameJson.integer(json, 'winningCoins'),
      winningXp: GameJson.integer(json, 'winningXP'),
      playerName: GameJson.stringOrNull(json, 'playerName'),
      profile: GameJson.stringOrNull(json, 'profile'),
      profileImageUrl: GameJson.stringOrNull(json, 'profileImageUrl'),
    );
  }
}
