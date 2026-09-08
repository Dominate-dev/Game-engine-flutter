import '../../domain/entities/current_question.dart';
import 'game_json.dart';
import 'question_answer_model.dart';

abstract final class CurrentQuestionModel {
  static CurrentQuestion fromJson(Map<String, dynamic> json) {
    return CurrentQuestion(
      id: GameJson.integer(json, 'id'),
      text: GameJson.stringOrNull(json, 'text'),
      textEn: GameJson.stringOrNull(json, 'textEn'),
      description: GameJson.stringOrNull(json, 'description'),
      type: GameJson.integer(json, 'type'),
      image: GameJson.stringOrNull(json, 'image'),
      video: GameJson.stringOrNull(json, 'video'),
      audio: GameJson.stringOrNull(json, 'audio'),
      answers: GameJson.list(json, 'answers', QuestionAnswerModel.fromJson),
      maxCorrectAnswersCount:
          GameJson.integerOrNull(json, 'maxCorrectAnswersCount'),
      questionNumber: GameJson.integerOrNull(json, 'questionNumber'),
      roundTotalQuestionsCount:
          GameJson.integerOrNull(json, 'roundTotalQuestionsCount'),
    );
  }
}
