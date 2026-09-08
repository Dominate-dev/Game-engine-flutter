import 'play_game_strings.dart';

class ArPlayGameStrings extends PlayGameStrings {
  const ArPlayGameStrings();

  @override
  String get waitingTitle => 'الانتظار';

  @override
  String get searchingPlayers => 'جاري البحث عن لاعب، انتظر قليلا من فضلك…';

  @override
  String get exitTheGame => 'خروج من اللعبة';

  @override
  String get areYouSureYouWantToGoOut =>
      'هل انت متأكد من انك تريد الخروج؟';

  @override
  String get generalGame => 'لعبة عامة';

  @override
  String get playerVersusPlayer => 'لاعب ضد لاعب';

  @override
  String get iAmReady => 'أنا مستعد';

  @override
  String get playerReplaceHint => 'سيتم استبدال اللاعب\nاذا لم يضغط انا مستعد';

  @override
  String get readyCountdownHint => 'اضغط انا مستعد\nقبل انتهاء العد التنازلي';

  @override
  String get pitchNumber => 'رقم الملعب';

  @override
  String get waitingForPlayer => 'بانتظار دخول\nاللاعب';

  @override
  String get roundPrefix => 'الجولة';

  @override
  String get codeCopied => 'تم نسخ الرمز';

  @override
  String shareGameMessage(String code) {
    return '⚽🔥 أنا في الملعب بانتظارك!\n'
        '😍⚽🎮 يلا ندخل الملعب ونستمتع بأقوى مباراة!\n'
        'استخدم هذا الكود وانضم إلي الآن:\n'
        '🔹 [$code] 🔹\n'
        'أو اضغط على الرابط:';
  }

  @override
  String get shareSheetTitle => 'مشاركة عبر';

  @override
  String get pass => 'باس';

  @override
  String get passAlert => 'انتبه! يمكنك استعمال زر باس مرة واحدة فقط';

  @override
  String get report => 'ابلاغ';

  @override
  String reportEmailSubject(String questionId) {
    return ' يوجد خطأ في السؤال رقم : $questionId';
  }

  @override
  String get result => 'النتيجة';

  @override
  String get roundHeading => 'جولة: ماذا تعرف؟';

  @override
  String get auctionRoundHeading => 'جولة: المزاد';

  @override
  String get bellRoundHeading => 'جولة: الجرس';

  @override
  String get comeBackRoundHeading => 'جولة: التعويض';

  @override
  String get breakerRoundHeading => 'جولة: كسر التعادل';

  @override
  String get bidding => 'مزاودة';

  @override
  String get takeTheTurn => 'خذ الدور';

  @override
  String get chooseTheNumberOfAnswers => 'اختر عدد الاجابات';

  @override
  String get choose => 'اختيار';

  @override
  String get howManyAnswersPrefix => 'كم اجابة تستطيع الاجابة عليها في';

  @override
  String get secondAuction => 'ثانية؟';

  @override
  String get numberOfAttempts => 'عدد محاولاتك: ';

  @override
  String get strike => 'سترايك';

  @override
  String get timeout => 'إنتهى الوقت';

  @override
  String get startTimer => 'بدأ الوقت';

  @override
  @override
  String get startIncreasing => 'ابدأ المزايدة';

  @override
  String get skip => 'تخطي';

  @override
  String get correctAnswer => 'اجابة صحيحة';

  @override
  String correctAnswerMessage(String playerName) =>
      'أجاب $playerName اجابة صحيحة';

  @override
  String get wrongAnswer => 'إجابة خاطئة';

  @override
  String get youAreFastest => 'انت الأسرع!';

  @override
  String get opponentIsFastest => 'هو الأسرع!';

  @override
  String get yourTurnNowLabel => 'دورك\nالآن';

  @override
  String get turnLabel => 'دور';

  @override
  String attemptsWarning(int count) {
    if (count == 1) {
      return 'انتبه! لديك محاوله فقط للاجابه';
    }
    if (count == 2) {
      return 'انتبه! لديك محاولتين  فقط للإجابة';
    }
    return 'انتبه! لديك $count محاولات فقط للاجابه';
  }

  @override
  String get lobbyPlayTitle => 'لوبي اللعب';

  @override
  String get lobbyPrivateTitle => 'لوبي خاص';

  @override
  String get wdykRoundTitle => 'ماذا تعرف';

  @override
  String get auctionRoundTitle => 'المزاد';

  @override
  String get bellRoundTitle => 'الجرس';

  @override
  String get comeBackRoundTitle => 'جولة التعويض';

  @override
  String get breakerRoundTitle => 'جولة كسر التعادل';

  @override
  String get finishRoundTitle => 'انتهت الجولة';

  @override
  String get readyGameTitle => 'إستعد, ستبدأ الجولة التالية بعد قليل';

  @override
  String get winTitle => 'انت الفائز!';

  @override
  String get winMessage => 'تهانينا! ، لقد فزت في التحدي';

  @override
  String get rewards => 'المكافآت';

  @override
  String get collectRewards => 'اجمع المكافآت';

  @override
  String get lossTitle => 'لقد خسرت';

  @override
  String get lossMessage => 'حظاً أوفر في المرة القادمة.';

  @override
  String get goodLuck => 'حظاً أوفر';

  @override
  String get theGameIsOver => 'تم انهاء اللعبة';

  @override
  String get back => 'رجوع';

  @override
  String get soundEffects => 'المؤثرات الصوتية';

  @override
  String get music => 'الموسيقى';

  @override
  String get save => 'حفظ';

  @override
  String get owned => 'أملكها';

  @override
  String get buying => 'الشراء';

  @override
  String get buy => 'شراء';

  @override
  String get areYouSureYouWantToBuy => 'هل انت متاكد من انك تريد الشراء';

  @override
  String get confirm => 'تأكيد';

  @override
  String get interests => 'الاهتمامات';

  @override
  String get wrongGameCode => 'هذه اللعبة غير موجودة';

  @override
  String get creatorTerminatedGame => 'قام مُنشئ الملعب بإنهاء اللعبة';
}
