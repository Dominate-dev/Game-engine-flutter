import 'play_game_strings.dart';

class EnPlayGameStrings extends PlayGameStrings {
  const EnPlayGameStrings();

  @override
  String get waitingTitle => 'Waiting';

  @override
  String get searchingPlayers =>
      'Searching for a player,\nplease wait a little…';

  @override
  String get exitTheGame => 'Exit the game';

  @override
  String get areYouSureYouWantToGoOut => 'Are you sure you want to exit?';

  @override
  String get generalGame => 'General game';

  @override
  String get playerVersusPlayer => 'Player vs Player';

  @override
  String get iAmReady => "I'm Ready";

  @override
  String get playerReplaceHint =>
      "The player will be replaced if they don't click I'm ready";

  @override
  String get readyCountdownHint => "Click I'm ready before\nthe countdown ends";

  @override
  String get pitchNumber => 'Field number';

  @override
  String get waitingForPlayer => 'Waiting for\nplayer to join';

  @override
  String get roundPrefix => 'Round';

  @override
  String get codeCopied => 'Code copied';

  @override
  String shareGameMessage(String code) {
    return '⚽🔥 I\'m at the field waiting for you!\n'
        '😍⚽🎮 Let\'s jump in and enjoy the most exciting match!\n'
        'Use this code to join me now:\n'
        '🔹 [$code] 🔹\n'
        'Or click the link:';
  }

  @override
  String get shareSheetTitle => 'Share with';

  @override
  String get pass => 'Pass';

  @override
  String get passAlert => 'Warning! You can use\nthe pass button only once';

  @override
  String get report => 'Report';

  @override
  String reportEmailSubject(String questionId) {
    return 'There is an error in question number: $questionId';
  }

  @override
  String get result => 'Result';

  @override
  String get roundHeading => 'Round: What do you know?';

  @override
  String get auctionRoundHeading => 'Round: Auction';

  @override
  String get bellRoundHeading => 'Round: Bell';

  @override
  String get comeBackRoundHeading => 'Round: Comeback';

  @override
  String get breakerRoundHeading => 'Round: Tiebreaker';

  @override
  String get bidding => 'Bidding';

  @override
  String get takeTheTurn => 'Take the turn';

  @override
  String get chooseTheNumberOfAnswers => 'Choose the number of answers';

  @override
  String get choose => 'Choose';

  @override
  String get howManyAnswersPrefix => 'How many answers can you answer in';

  @override
  String get secondAuction => 'seconds?';

  @override
  String get numberOfAttempts => 'Number of attempts: ';

  @override
  String get strike => 'Strike';

  @override
  String get timeout => 'Timeout';

  @override
  String get startTimer => 'Start Timer';

  @override
  @override
  String get startIncreasing => 'Start\nIncreasing';

  @override
  String get skip => 'Skip';

  @override
  String get correctAnswer => 'Correct Answer';

  @override
  String correctAnswerMessage(String playerName) =>
      '$playerName answered correctly';

  @override
  String get wrongAnswer => 'Wrong Answer';

  @override
  String get youAreFastest => 'You’re\nthe fastest!';

  @override
  String get opponentIsFastest => 'He’s\nthe fastest!';

  @override
  String get yourTurnNowLabel => 'Your turn\nnow';

  @override
  String get turnLabel => 'Turn';

  @override
  String attemptsWarning(int count) {
    if (count == 1) {
      return 'Warning! You have only\none attempt to answer';
    }
    return 'Warning! You have $count\nattempts left to answer';
  }

  @override
  String get lobbyPlayTitle => 'Play lobby';

  @override
  String get lobbyPrivateTitle => 'Private lobby';

  @override
  String get wdykRoundTitle => 'What do you know';

  @override
  String get auctionRoundTitle => 'Auction';

  @override
  String get bellRoundTitle => 'Bell';

  @override
  String get comeBackRoundTitle => 'Come Back';

  @override
  String get breakerRoundTitle => 'Tiebreaker';

  @override
  String get finishRoundTitle => 'Finish round';

  @override
  String get readyGameTitle => 'Get ready,\nthe next round will start soon';

  @override
  String get winTitle => "You're the Winner!";

  @override
  String get winMessage => 'Congratulations!\nYou won the challenge';

  @override
  String get rewards => 'Rewards';

  @override
  String get collectRewards => 'Collect rewards';

  @override
  String get lossTitle => 'You lost';

  @override
  String get lossMessage => 'Better luck next time.';

  @override
  String get goodLuck => 'Good luck';

  @override
  String get theGameIsOver => 'The game is over';

  @override
  String get back => 'Back';

  @override
  String get soundEffects => 'Sound effects';

  @override
  String get music => 'Music';

  @override
  String get save => 'Save';

  @override
  String get owned => 'Owned';

  @override
  String get buying => 'Buying';

  @override
  String get buy => 'Buy';

  @override
  String get areYouSureYouWantToBuy => 'Are you sure you want to buy?';

  @override
  String get confirm => 'Confirm';

  @override
  String get interests => 'Interests';

  @override
  String get wrongGameCode => 'This game does not exist';

  @override
  String get creatorTerminatedGame => 'Creator has terminated the game';
}
