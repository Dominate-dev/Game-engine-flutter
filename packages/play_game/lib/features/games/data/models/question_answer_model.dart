import '../../domain/entities/question_answer.dart';
import 'game_json.dart';

abstract final class QuestionAnswerModel {
  static QuestionAnswer fromJson(Map<String, dynamic> json) {
    return QuestionAnswer(
      id: GameJson.integerOrNull(json, 'id'),
      text: GameJson.stringOrNull(json, 'text'),
      textEn: GameJson.stringOrNull(json, 'textEn'),
      isSelected: GameJson.boolean(json, 'isSelected'),
    );
  }
}
