/// Hub method and event names for Play — keep game-specific names here, not in coreapp.
/// Duplicate Kotlin aliases that share the same hub string were collapsed.
///
/// Screen [listenHubEvents]: [waitingScreenEvents], [lobbyScreenEvents],
/// [hostScreenEvents], [auctionScreenEvents].
/// [GameController] stream: [sessionEvents] + [sharedRoundEvents]
/// (question/timer/turn/finish — shared by every round).
abstract final class PlayGameHubEvents {
  // Client → server methods
  static const createGame = 'CreateGame';
  static const submitAnswer = 'SubmitAnswer';
  static const pass = 'Pass';
  static const joinRandomGame = 'JoinRandomGame';
  static const readyForGame = 'ReadyForGame';
  static const leaveGame = 'LeaveGame';
  static const bid = 'Bid';
  static const ringBell = 'RingBell';
  static const startJudgeGame = 'StartJudgeGame';
  static const startGameTimer = 'StartGameTimer';
  static const judgeSubmitAnswer = 'JudgeSubmitAnswer';
  static const sendEmoji = 'SendEmoji';
  static const auctionConfirmResult = 'AuctionConfirmResult';
  static const checkPlayerGame = 'CheckPlayerGame';
  static const judgeBid = 'JudgeBid';
  static const judgeRingBell = 'JudgeRingBell';
  static const createPrivateGame = 'CreatePrivateGame';
  static const joinPrivateGame = 'JoinPrivateGame';

  // Server → client events
  static const gameJoined = 'GameJoined';
  static const playerLeft = 'PlayerLeft';
  static const gameCreated = 'GameCreated';
  static const gameUpdated = 'GameUpdated';
  static const playerReady = 'PlayerReady';
  static const gameStarted = 'GameStarted';
  static const changeTurn = 'ChangeTurn';
  static const penalty = 'Penalty';
  static const correctAnswer = 'CorrectAnswer';
  static const playerPassed = 'PlayerPassed';
  static const playerAnswered = 'PlayerAnswered';
  static const nextQuestion = 'NextQuestion';
  static const timerUpdatedSeconds = 'TimerUpdatedSeconds';
  static const gameOver = 'GameOver';
  static const gameFinished = 'GameFinished';
  static const timeStarted = 'TimeStarted';
  static const roundFinished = 'RoundFinished';
  static const playerEmoted = 'PlayerEmoted';
  static const gameRestore = 'GameRestore';
  static const showAuctionConfirmationDialog = 'ShowAuctionConfirmationDialog';
  static const nextRoundStarted = 'NextRoundStarted';
  static const auctionBiddingPhaseStarted = 'AuctionBiddingPhaseStarted';
  static const playerBidded = 'PlayerBidded';
  static const auctionAnswerPhaseStarted = 'AuctionAnswerPhaseStarted';
  static const playerLostAuctionRound = 'PlayerLostAuctionRound';
  static const auctionAnswerPhaseScoreUpdate = 'AuctionAnswerPhaseScoreUpdate';
  static const playerWonAuctionRound = 'PlayerWonAuctionRound';
  static const wrongGameCode = 'WrongGameCode';
  static const gameTerminated = 'GameTerminated';
  static const showResults = 'ShowResults';
  static const wrongAnswer = 'WrongAnswer';
  static const questionOver = 'QuestionOver';
  static const startQuestionDiscussion = 'StartQuestionDiscussion';
  static const toggleQuestionVisibleChanged = 'ToggleQuestionVisibleChanged';
  static const error = 'Error';

  /// Phase / result routing — [GameController] only, not screens.
  static const sessionEvents = <String>{
    gameJoined,
    gameCreated,
    gameUpdated,
    gameStarted,
    gameOver,
    gameFinished,
    gameTerminated,
    gameRestore,
  };

  /// [WaitingScreen.listenHubEvents]
  static const waitingScreenEvents = <String>[
    gameUpdated,
    gameRestore,
    gameFinished,
    error,
  ];

  /// [LobbyPlayGameScreen.listenHubEvents]
  static const lobbyScreenEvents = <String>[
    playerReady,
    gameUpdated,
    playerLeft,
    gameRestore,
    gameStarted,
    playerEmoted,
    gameFinished,
  ];

  /// [LobbyPrivateGameScreen.listenHubEvents] — the shared lobby set plus
  /// [wrongGameCode], which only a private *join* can produce. Kept off
  /// [lobbyScreenEvents] so the public lobby does not bind an event it can
  /// never receive.
  static const privateLobbyScreenEvents = <String>[
    ...lobbyScreenEvents,
    wrongGameCode,
  ];

  /// [GameControllerScreen] stays mounted — emotes, self-leave, and the round
  /// dialogs. State-only names live in [sessionEvents] / [sharedRoundEvents]
  /// and reach [GameController] through [PlayGameHubBindings]; listing one
  /// here too would apply it twice.
  static const hostScreenEvents = <String>[
    playerEmoted,
    playerLeft,
    changeTurn,
    penalty,
    timeStarted,
    playerPassed,
    playerAnswered,
    correctAnswer,
  ];

  /// Every round — handled in [GameController], not copied on each screen.
  static const sharedRoundEvents = <String>{
    changeTurn,
    penalty,
    correctAnswer,
    playerPassed,
    playerAnswered,
    nextQuestion,
    timerUpdatedSeconds,
    timeStarted,
    roundFinished,
    nextRoundStarted,
    wrongAnswer,
    questionOver,
    startQuestionDiscussion,
    toggleQuestionVisibleChanged,
    showResults,
    error,
  };

  /// Auction-only state, reduced in [GameController]. `Penalty` is absent on
  /// purpose: it already arrives through [sharedRoundEvents], and routing it
  /// twice would apply it twice.
  static const auctionRoundEvents = <String>{
    auctionBiddingPhaseStarted,
    playerBidded,
    auctionAnswerPhaseStarted,
    auctionAnswerPhaseScoreUpdate,
    playerWonAuctionRound,
    playerLostAuctionRound,
  };

  /// Extra names for [AuctionRoundScreen.listenHubEvents].
  static const auctionScreenEvents = <String>[
    auctionBiddingPhaseStarted,
    playerBidded,
    auctionAnswerPhaseStarted,
    auctionAnswerPhaseScoreUpdate,
    playerLostAuctionRound,
    playerWonAuctionRound,
    showAuctionConfirmationDialog,
  ];

  /// Bound once for the plugin lifetime. Invoke methods are not listed.
  static const lifetimeEvents = <String>[
    gameJoined,
    gameCreated,
    gameUpdated,
    playerReady,
    playerLeft,
    playerEmoted,
    gameStarted,
    gameRestore,
    changeTurn,
    penalty,
    correctAnswer,
    playerPassed,
    playerAnswered,
    nextQuestion,
    timerUpdatedSeconds,
    gameOver,
    gameFinished,
    timeStarted,
    roundFinished,
    showAuctionConfirmationDialog,
    nextRoundStarted,
    auctionBiddingPhaseStarted,
    playerBidded,
    auctionAnswerPhaseStarted,
    playerLostAuctionRound,
    auctionAnswerPhaseScoreUpdate,
    playerWonAuctionRound,
    wrongGameCode,
    gameTerminated,
    showResults,
    wrongAnswer,
    questionOver,
    startQuestionDiscussion,
    toggleQuestionVisibleChanged,
    error,
  ];

  static const gameOverEvents = <String>{
    gameOver,
    gameFinished,
    gameTerminated,
  };

  static const auctionEvents = <String>{
    auctionBiddingPhaseStarted,
    playerBidded,
    auctionAnswerPhaseStarted,
    auctionAnswerPhaseScoreUpdate,
    playerLostAuctionRound,
    playerWonAuctionRound,
    showAuctionConfirmationDialog,
  };
}
