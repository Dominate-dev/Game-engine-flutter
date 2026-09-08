import 'package:equatable/equatable.dart';

import 'question_answer.dart';

class CurrentQuestion extends Equatable {
  const CurrentQuestion({
    required this.id,
    required this.type,
    required this.answers,
    this.text,
    this.textEn,
    this.description,
    this.image,
    this.video,
    this.audio,
    this.maxCorrectAnswersCount,
    this.questionNumber,
    this.roundTotalQuestionsCount,
  });

  final int id;
  final String? text;
  final String? textEn;
  final String? description;
  final int type;
  final String? image;
  final String? video;
  final String? audio;
  final List<QuestionAnswer> answers;
  final int? maxCorrectAnswersCount;
  final int? questionNumber;
  final int? roundTotalQuestionsCount;

  String displayText({required bool isArabic}) {
    if (isArabic) {
      return (text ?? textEn ?? '').trim();
    }
    return (textEn ?? text ?? '').trim();
  }

  // Hub `questionNumber` / `roundTotalQuestionsCount` — e.g. `1/5`.
  String get countLabel {
    if (questionNumber != null && roundTotalQuestionsCount != null) {
      return '$questionNumber/$roundTotalQuestionsCount';
    }
    return '';
  }

  @override
  List<Object?> get props => [id];
}
