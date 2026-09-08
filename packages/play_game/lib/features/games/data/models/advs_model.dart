import '../../domain/entities/advs.dart';
import 'game_json.dart';

abstract final class AdvsModel {
  static Advs fromJson(Map<String, dynamic> json) {
    return Advs(
      id: GameJson.string(json, 'id'),
      title: GameJson.stringOrNull(json, 'title'),
      description: GameJson.stringOrNull(json, 'description'),
      type: GameJson.integer(json, 'type'),
      advData: GameJson.stringOrNull(json, 'advData'),
      referencesData: GameJson.stringOrNull(json, 'referencesData'),
      startDate: GameJson.stringOrNull(json, 'startDate'),
      endDate: GameJson.stringOrNull(json, 'endDate'),
      timeOutInSeconds: GameJson.integer(json, 'timeOutInSeconds'),
      visibilityCount: GameJson.integerOrNull(json, 'visibilityCount'),
      isLandscape: GameJson.boolean(json, 'isLandscape'),
    );
  }

  static Advs? fromField(Map<String, dynamic> json, String key) {
    final raw = GameJson.mapOrNull(json, key);
    if (raw == null) {
      return null;
    }
    return fromJson(raw);
  }
}
