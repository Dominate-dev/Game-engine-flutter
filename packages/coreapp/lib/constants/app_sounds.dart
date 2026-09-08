/// Sound assets shipped with coreapp. [AudioService] loads these from
/// [packageName] by default (same rule as [AppAssets] for images/lottie).
///
/// ```dart
/// final audio = ref.read(audioServiceProvider);
/// await audio.start(AppSounds.musicRunning, type: AudioSourceType.music);
/// await audio.start(AppSounds.rightAnswer);
/// await audio.playRightAnswer();
/// ```
abstract final class AppSounds {
  static const packageName = 'coreapp';

  /// Looping background track played while a round/game is in progress.
  static const musicRunning = 'assets/audio/music_running_t30.mp3';

  /// Looping track for the public/private lobby waiting room.
  static const waitingInLobby = 'assets/audio/waiting_in_the_lobby_t30.mp3';

  /// Short ambience while the sudden-death waiting screen is shown.
  static const sdWaitingLobby = 'assets/audio/sd_waiting_lobby.mp3';

  static const answerClickChoice = 'assets/audio/answer_click_choice_t30.mp3';
  static const bellRound = 'assets/audio/bell_round_t30.mp3';
  static const collectingRewardsSd =
      'assets/audio/collecting_rewards_sd_t30.mp3';
  static const exitTheGame = 'assets/audio/exit_the_game_t30.mp3';
  static const getStrike = 'assets/audio/get_strick_t30.mp3';
  static const losingGame = 'assets/audio/losing_game_t30.mp3';
  static const minor = 'assets/audio/minor_t30.mp3';
  static const pass = 'assets/audio/pass_t30.mp3';
  static const raisingLevel = 'assets/audio/raising_level_t30.mp3';
  static const rightAnswer = 'assets/audio/right_answer_t30.mp3';
  static const startRound = 'assets/audio/start_round_t30.mp3';
  static const startTime = 'assets/audio/start_time_t30.mp3';
  static const startingGamerTurn = 'assets/audio/starting_gamer_turn_t30.mp3';
  static const timeOver = 'assets/audio/time_over_t30.mp3';
  static const winningGame = 'assets/audio/winning_game_t30.mp3';
  static const wrongAnswer = 'assets/audio/wrong_answer_t30.mp3';
  static const youFaster = 'assets/audio/you_faster_t30.mp3';
}
