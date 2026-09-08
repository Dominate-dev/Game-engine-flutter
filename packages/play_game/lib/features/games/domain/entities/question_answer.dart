import 'package:equatable/equatable.dart';

class QuestionAnswer extends Equatable {
  const QuestionAnswer({
    this.id,
    this.text,
    this.textEn,
    this.isSelected = false,
  });

  final int? id;
  final String? text;
  final String? textEn;
  final bool isSelected;

  String displayText({required bool isArabic}) {
    if (isArabic) {
      return (text ?? textEn ?? '').trim();
    }
    return (textEn ?? text ?? '').trim();
  }

  QuestionAnswer copyWith({bool? isSelected}) {
    return QuestionAnswer(
      id: id,
      text: text,
      textEn: textEn,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  List<Object?> get props => [id, text, isSelected];
}
