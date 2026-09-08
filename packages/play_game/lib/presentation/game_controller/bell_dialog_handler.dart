part of 'game_controller.dart';

/// Every Bell overlay is 1500ms except the start-time overlay (below) and
/// the round intro, which reuses [showRoundIntro]'s existing 2000ms.
const _bellShortDialogMs = 1500;

/// `TimeStarted`'s own overlay — same duration as WDYK's and Auction's.
const _bellLongDialogMs = 2000;

/// Bell (round 3) overlays.
///
/// These share the round dialog queue and its lifecycle rules with WDYK and
/// Auction — ownership here comes from the Bell contract: the race result is
/// `ChangeTurn`, the same field WDYK's turn already uses, so identity checks
/// reuse [GameController.isCurrentUser] / `_isMinePlayerId` exactly as WDYK
/// and Auction already do. Nothing here mutates state — dialogs are
/// presentation only; B-1's reducer already owns every transition.
extension BellDialogHandler on GameController {
  /// `TimeStarted` — the same overlay WDYK's and Auction's own
  /// `onTimeStarted` already show for this event. Presentation only: B-1's
  /// reducer independently arms `bellArmed` off the same raw `TimeStarted`
  /// event through the separate state pipeline, so nothing here decides
  /// when the Bell becomes clickable.
  void onBellTimeStarted(
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    _enqueueRoundDialog(
      GamePhase.bell,
      showDialog,
      RoundLottieDialog(
        timer: _bellLongDialogMs,
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

  /// `ChangeTurn` is the race result. While racing, a named winner shows
  /// "fastest"; once a turn already existed (no race), it is the ordinary
  /// WDYK-style turn dialog. `bellPhase` is read here — before the shared
  /// reducer applies this same event — because the dialog listener always
  /// runs synchronously ahead of the reducer's stream-delivered update, so
  /// it still reflects the pre-result phase.
  void onBellChangeTurn(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final playerId = GameSessionReducer.turnPlayerIdFrom(data);
    if (playerId == null || playerId.isEmpty) {
      // An explicit reset — the race clears silently, same as WDYK/Auction.
      return;
    }
    final isMine = _isMinePlayerId(playerId);
    if (isMine == null) {
      return;
    }
    final wasRacing = bellPhase == BellPhase.racing;
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    final text = wasRacing
        ? (isMine ? strings.youAreFastest : strings.opponentIsFastest)
        : _playerNameForId(playerId);
    if (text.isEmpty) {
      return;
    }
    // Only the plain turn overlay (a ChangeTurn outside a race) gets the
    // turn wording; the fastest-racer copy above is a different overlay and
    // is left exactly as it is. `text` is still the resolved player name at
    // this point, so the empty-name guard above is unchanged.
    final label = wasRacing
        ? text
        : strings.turnOverlayText(isMine: isMine, playerName: text);
    _enqueueRoundDialog(
      GamePhase.bell,
      showDialog,
      RoundLottieDialog(
        text: label,
        timer: _bellShortDialogMs,
        // Winning the race and a plain turn handoff are different moments,
        // and the copy above already branches on the same flag.
        sound: wasRacing ? AppSounds.youFaster : AppSounds.startingGamerTurn,
        lottie: const AppLottieView.circularBlue(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// `CorrectAnswer` — T30 does not branch on playerId, so this is shown to
  /// both clients unconditionally. No `isMyTurn` / ownership check.
  void onBellCorrectAnswer(
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    _enqueueRoundDialog(
      GamePhase.bell,
      showDialog,
      RoundLottieDialog(
        text: strings.correctAnswer,
        timer: _bellShortDialogMs,
        sound: AppSounds.rightAnswer,
        lottie: const AppLottieView.correctAnswer(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// `Penalty` — `type` 1 timeout, 2 wrong. Bell has no strike row: both
  /// types show their own plain overlay instead (unlike WDYK's strike dots,
  /// and unlike Auction, which shows nothing for a wrong answer).
  ///
  /// Both are answer-result overlays, like `CorrectAnswer` — shown to both
  /// clients unconditionally (B-6). `playerId` names who the penalty
  /// happened to, not who may watch it; it plays no part in visibility.
  void onBellPenalty(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final type = TypePenalty.fromId(_penaltyTypeFrom(data));
    if (type == null) {
      AppLogger.log(
        'GameController — bell ${PlayGameHubEvents.penalty} type unresolved '
        '| data: $data',
      );
      return;
    }
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    final dialog = switch (type) {
      TypePenalty.wrongAnswer => RoundLottieDialog(
          text: strings.wrongAnswer,
          timer: _bellShortDialogMs,
          sound: AppSounds.wrongAnswer,
          lottie: const AppLottieView.wrongAnswer(
            width: double.infinity,
            height: 300,
            fit: BoxFit.contain,
          ),
        ),
      TypePenalty.timeout => RoundLottieDialog(
          text: strings.timeout,
          timer: _bellShortDialogMs,
          sound: AppSounds.timeOver,
          lottie: const AppLottieView.circularRed(
            width: double.infinity,
            height: 300,
            fit: BoxFit.contain,
          ),
        ),
    };
    _enqueueRoundDialog(GamePhase.bell, showDialog, dialog);
  }

  /// `PlayerAnswered` — reveals the chosen text to both players, the same
  /// unconditional rule WDYK and Auction already use for this event.
  void onBellPlayerAnswered(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final text = _answeredTextFromData(data);
    if (text.isEmpty) {
      return;
    }
    _enqueueRoundDialog(
      GamePhase.bell,
      showDialog,
      PlayerAnsweredDialog(answer: text, timer: _bellShortDialogMs),
    );
  }
}
