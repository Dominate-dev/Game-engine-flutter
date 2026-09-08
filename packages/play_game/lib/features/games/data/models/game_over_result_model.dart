import 'package:coreapp/coreapp.dart';

import '../../domain/entities/game_over_result.dart';
import 'advs_model.dart';
import 'game_json.dart';
import 'game_result_player_model.dart';

abstract final class GameOverResultModel {
  static GameOverResult fromJson(Map<String, dynamic> json) {
    return GameOverResult(
      gameId: GameJson.string(json, 'gameId'),
      isPrivate: GameJson.boolean(json, 'isPrivate'),
      winnerId: GameJson.string(json, 'winnerId'),
      gameResultPlayers: GameJson.list(
        json,
        'gameResultPlayers',
        GameResultPlayerModel.fromJson,
      ),
      afterMatchAdv: AdvsModel.fromField(json, 'afterMatchAdv'),
      isTournamentMatch: GameJson.booleanOrNull(json, 'isTournamentMatch'),
      nextStage: GameJson.stringOrNull(json, 'nextStage'),
      nextStageEn: GameJson.stringOrNull(json, 'nextStageEn'),
    );
  }

  static bool looksLikeGameOver(Map<String, dynamic> json) {
    return JsonValue.hasField(json, 'gameResultPlayers') ||
        JsonValue.hasField(json, 'winnerId');
  }
}
