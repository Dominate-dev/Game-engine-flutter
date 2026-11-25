import 'package:coreapp/coreapp.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Judge mode copy, in the app language. Kept apart from [PlayGameStrings] so
/// Judge mode stays a self-contained flow.
abstract class JudgeStrings {
  const JudgeStrings();

  static const JudgeStrings english = _EnJudgeStrings();
  static const JudgeStrings arabic = _ArJudgeStrings();

  static JudgeStrings forLanguage(String? languageCode) =>
      AppLanguage.isArabic(AppLanguage.normalize(languageCode))
      ? arabic
      : english;

  String get title;
  String get setupHint;
  String get player1;
  String get player2;
  String get namesMustDiffer;
  String get startGame;
  String get preparing;
  String get startTimer;
  String get rightNotListed;
  String get wrong;
  String get pass;
  String turnOf(String name);
  String get whoRang;
  String rang(String name);
  String get whoBids;
  String get bid;
  String get confirmBid;
  String bidOf(String name, int value);
  String scoreOf(int score, int goal);
  String didMakeIt(String name);
  String get yes;
  String get no;
  String pointTo(String name);
  String get noAnswersLeft;
  String roundName(int roundType);
  String questionCount(String count);
  String correctFor(String name);
  String strikeFor(String name);
  String timeUpFor(String name);
  String passFor(String name);
  String winner(String name);
  String get gameEnded;
  String get points;
  String get strikes;
  String get correct;
  String get done;
  String get exit;
  String get exitConfirm;
  String get couldNotStart;
}

class _EnJudgeStrings extends JudgeStrings {
  const _EnJudgeStrings();
  @override
  String get title => 'Judge mode';
  @override
  String get setupHint =>
      'Two players answer out loud. You record what happens.';
  @override
  String get player1 => 'Player 1 name';
  @override
  String get player2 => 'Player 2 name';
  @override
  String get namesMustDiffer => 'Use two different names';
  @override
  String get startGame => 'Start game';
  @override
  String get preparing => 'Preparing the game…';
  @override
  String get startTimer => 'Start timer';
  @override
  String get rightNotListed => 'Right, not listed';
  @override
  String get wrong => 'Wrong';
  @override
  String get pass => 'Pass';
  @override
  String turnOf(String name) => "$name's turn";
  @override
  String get whoRang => 'Who rang first?';
  @override
  String rang(String name) => name;
  @override
  String get whoBids => 'Who takes the bid?';
  @override
  String get bid => 'Bid';
  @override
  String get confirmBid => 'Confirm bid';
  @override
  String bidOf(String name, int value) => '$name bids $value';
  @override
  String scoreOf(int score, int goal) => '$score of $goal';
  @override
  String didMakeIt(String name) => 'Did $name make the bid?';
  @override
  String get yes => 'Yes';
  @override
  String get no => 'No';
  @override
  String pointTo(String name) => 'Point to $name';
  @override
  String get noAnswersLeft => 'All listed answers given';
  @override
  String roundName(int roundType) => switch (roundType) {
    1 => 'What do you know?',
    2 => 'Auction',
    3 => 'Bell',
    4 => 'Comeback',
    5 => 'Tie breaker',
    6 => 'Impossible',
    _ => '',
  };
  @override
  String questionCount(String count) => count;
  @override
  String correctFor(String name) => '$name: correct';
  @override
  String strikeFor(String name) => '$name: wrong';
  @override
  String timeUpFor(String name) =>
      name.isEmpty ? 'Time is up' : '$name: time is up';
  @override
  String passFor(String name) => '$name passed';
  @override
  String winner(String name) => '$name wins';
  @override
  String get gameEnded => 'The game has ended';
  @override
  String get points => 'Points';
  @override
  String get strikes => 'Strikes';
  @override
  String get correct => 'Correct';
  @override
  String get done => 'Done';
  @override
  String get exit => 'Exit';
  @override
  String get exitConfirm => 'End this judge game?';
  @override
  String get couldNotStart => 'The game could not start. Try again.';
}

class _ArJudgeStrings extends JudgeStrings {
  const _ArJudgeStrings();
  @override
  String get title => 'وضع الحكم';
  @override
  String get setupHint => 'لاعبان يجيبان بصوت عالٍ، وأنت تسجّل ما يحدث.';
  @override
  String get player1 => 'اسم اللاعب الأول';
  @override
  String get player2 => 'اسم اللاعب الثاني';
  @override
  String get namesMustDiffer => 'اكتب اسمين مختلفين';
  @override
  String get startGame => 'ابدأ اللعبة';
  @override
  String get preparing => 'جارٍ تجهيز اللعبة…';
  @override
  String get startTimer => 'ابدأ المؤقت';
  @override
  String get rightNotListed => 'صحيحة وغير موجودة';
  @override
  String get wrong => 'خطأ';
  @override
  String get pass => 'باس';
  @override
  String turnOf(String name) => 'دور $name';
  @override
  String get whoRang => 'من ضغط الجرس أولًا؟';
  @override
  String rang(String name) => name;
  @override
  String get whoBids => 'من يأخذ المزايدة؟';
  @override
  String get bid => 'المزايدة';
  @override
  String get confirmBid => 'تأكيد المزايدة';
  @override
  String bidOf(String name, int value) => '$name يزايد بـ $value';
  @override
  String scoreOf(int score, int goal) => '$score من $goal';
  @override
  String didMakeIt(String name) => 'هل حقق $name المزايدة؟';
  @override
  String get yes => 'نعم';
  @override
  String get no => 'لا';
  @override
  String pointTo(String name) => 'نقطة لـ $name';
  @override
  String get noAnswersLeft => 'قيلت كل الإجابات الموجودة';
  @override
  String roundName(int roundType) => switch (roundType) {
    1 => 'ماذا تعرف؟',
    2 => 'المزاد',
    3 => 'الجرس',
    4 => 'التعويض',
    5 => 'كسر التعادل',
    6 => 'المستحيل',
    _ => '',
  };
  @override
  String questionCount(String count) => count;
  @override
  String correctFor(String name) => '$name: صحيحة';
  @override
  String strikeFor(String name) => '$name: خطأ';
  @override
  String timeUpFor(String name) =>
      name.isEmpty ? 'انتهى الوقت' : '$name: انتهى الوقت';
  @override
  String passFor(String name) => '$name استخدم الباس';
  @override
  String winner(String name) => 'الفائز $name';
  @override
  String get gameEnded => 'انتهت اللعبة';
  @override
  String get points => 'النقاط';
  @override
  String get strikes => 'الأخطاء';
  @override
  String get correct => 'الصحيحة';
  @override
  String get done => 'تم';
  @override
  String get exit => 'خروج';
  @override
  String get exitConfirm => 'هل تريد إنهاء لعبة الحكم؟';
  @override
  String get couldNotStart => 'تعذّر بدء اللعبة. حاول مرة أخرى.';
}

final judgeStringsProvider = Provider<JudgeStrings>(
  (ref) => JudgeStrings.forLanguage(ref.watch(appLanguageProvider)),
);
