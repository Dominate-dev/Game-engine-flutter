part of 'game_controller.dart';

/// Auction overlay durations from the reference
/// (`docs/tasks/auction-round-workflow.md`, section 5). Dialog lifetimes only —
/// the match countdown is server-driven and untouched by any of this.
const _auctionLongDialogMs = 2000; // start increasing
const _auctionShortDialogMs = 1500; // turn, correct, wrong, timeout, reveal

/// Auction (round 2) overlays.
///
/// These share the round dialog queue and its lifecycle rules with WDYK, but
/// none of WDYK's business rules: ownership here comes from the auction
/// contract — `AuctionAnswerPhaseStarted.playerId` for the answering player,
/// and the event's own `playerId` for penalties.
extension AuctionDialogHandler on GameController {
  /// "Start increasing" — the legacy `startIncreasing()`: circular-blue
  /// lottie, 2000ms, shown only to the player who may actually raise.
  ///
  /// Driven from the reduced bidding state rather than straight off
  /// `AuctionBiddingPhaseStarted`, so it never depends on whether the screen's
  /// event listener runs before or after the reducer.
  void showAuctionStartIncreasing(
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    if (!canBid) {
      return;
    }
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    _enqueueRoundDialog(
      GamePhase.auction,
      showDialog,
      RoundLottieDialog(
        text: strings.startIncreasing,
        timer: _auctionLongDialogMs,
        sound: AppSounds.startingGamerTurn,
        lottie: const AppLottieView.circularBlue(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// `TimeStarted` — the app's established time-start overlay, shown on both
  /// devices because the countdown starts for the round, not for a player.
  ///
  /// Same widget, copy, sound and 2000ms the WDYK path already uses; nothing
  /// new is introduced. It is an overlay only — the countdown itself is driven
  /// by `TimerUpdatedSeconds` and is untouched here.
  void onAuctionTimeStarted(
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    _enqueueRoundDialog(
      GamePhase.auction,
      showDialog,
      RoundLottieDialog(
        timer: _auctionLongDialogMs,
        text: strings.startTimer,
        marginTop: 80,
        sound: AppSounds.startTime,
        lottie: const AppLottieView.timer(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// `ChangeTurn [playerId, gameId]` — "your turn" / "their turn", named.
  /// Shown on both devices because the overlay names whoever holds the turn.
  void onAuctionChangeTurn(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final playerId = (data?['playerId'] ?? data?['arg0'])?.toString() ?? '';
    final playerName = _playerNameFromData(data);
    if (playerName.isEmpty) {
      return;
    }
    // Same turn overlay as WDYK's, and it reads the same way here. Name
    // source and the empty-name guard above are unchanged.
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    _enqueueRoundDialog(
      GamePhase.auction,
      showDialog,
      RoundLottieDialog(
        text: strings.turnOverlayText(
          isMine: isCurrentUser(playerId),
          playerName: playerName,
        ),
        timer: _auctionShortDialogMs,
        sound: AppSounds.startingGamerTurn,
        lottie: const AppLottieView.circularBlue(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// `Penalty {playerId, type}` — only a timeout (1) raises an overlay.
  ///
  /// A wrong answer (2) shows nothing in Auction: the answering flow carries
  /// on, and `AuctionAnswerPhaseScoreUpdate` reports the count. It is shown
  /// only on the device of the player the payload names — nothing in the
  /// auction contract asks for the watcher to see it.
  void onAuctionPenalty(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    final playerId = GameSessionReducer.playerIdFrom(data) ?? '';
    final type = TypePenalty.fromId(_penaltyTypeFrom(data));
    final isMine = _isMinePlayerId(playerId);
    if (type == null || isMine == null) {
      AppLogger.log(
        'GameController — auction ${PlayGameHubEvents.penalty} unresolved | '
        'data: $data',
      );
      return;
    }
    if (type == TypePenalty.wrongAnswer || !isMine) {
      return;
    }
    _enqueueRoundDialog(
      GamePhase.auction,
      showDialog,
      RoundLottieDialog(
        text: strings.timeout,
        timer: _auctionShortDialogMs,
        sound: AppSounds.timeOver,
        lottie: const AppLottieView.circularRed(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// `PlayerLostAuctionRound [playerId, gameId]` — the timeout overlay, with
  /// Native's wording rule: a countdown still showing time means the round
  /// finished, a countdown at zero means it timed out.
  ///
  /// The check reads the last server timer value, which is this repository's
  /// nearest equivalent of Native's `timeToDisplay`; the display itself is not
  /// readable from here. It is read before any reset, so the answer does not
  /// depend on whether the reducer ran first.
  void onAuctionRoundLost(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final playerId = GameSessionReducer.playerIdFrom(data) ?? '';
    final isMine = _isMinePlayerId(playerId);
    if (isMine == null) {
      _logAuctionPayload(
        PlayGameHubEvents.playerLostAuctionRound,
        data,
        'player unresolved',
      );
      return;
    }
    if (!isMine) {
      return;
    }
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    final secondsLeft = _s.game?.currentTimerValue ?? 0;
    _enqueueRoundDialog(
      GamePhase.auction,
      showDialog,
      RoundLottieDialog(
        text: secondsLeft > 0 ? strings.finishRoundTitle : strings.timeout,
        timer: _auctionShortDialogMs,
        sound: AppSounds.losingGame,
        lottie: const AppLottieView.circularRed(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  // Same payload/treatment as onAuctionRoundLost, but winning has no
  // "timed out" case, so there is no wording branch to mirror.
  void onAuctionRoundWon(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final playerId = GameSessionReducer.playerIdFrom(data) ?? '';
    final isMine = _isMinePlayerId(playerId);
    if (isMine == null) {
      _logAuctionPayload(
        PlayGameHubEvents.playerWonAuctionRound,
        data,
        'player unresolved',
      );
      return;
    }
    if (!isMine) {
      return;
    }
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    _enqueueRoundDialog(
      GamePhase.auction,
      showDialog,
      RoundLottieDialog(
        text: strings.finishRoundTitle,
        timer: _auctionShortDialogMs,
        sound: AppSounds.winningGame,
        lottie: const AppLottieView.circularGreen(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// `CorrectAnswer` — no overlay. Like a wrong answer, Auction reports the
  /// outcome through `AuctionAnswerPhaseScoreUpdate` (currentScore/
  /// goalScore), not a dialog.
  void onAuctionCorrectAnswer(
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {}

  /// `PlayerAnswered` — the reference shows the chosen text to **both**
  /// players, so this one is deliberately not ownership-gated.
  void onAuctionPlayerAnswered(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final text = _answeredTextFromData(data);
    if (text.isEmpty) {
      return;
    }
    _enqueueRoundDialog(
      GamePhase.auction,
      showDialog,
      PlayerAnsweredDialog(answer: text, timer: _auctionShortDialogMs),
    );
  }
}
