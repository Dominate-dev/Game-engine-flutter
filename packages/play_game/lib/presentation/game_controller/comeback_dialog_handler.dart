part of 'game_controller.dart';

/// Comeback overlay durations from the reference
/// (`docs/tasks/comeback-round-workflow.md`, section 5). Dialog lifetimes
/// only — the match countdown is server-driven and untouched by any of this.
const _comebackShortDialogMs = 1500; // correct (me), wrong (me), timeout
const _comebackLongDialogMs = 2000; // correct (opponent)

/// Comeback (round 4) overlays — also used by Breaker (round 5), which is
/// confirmed to share this exact dialog lifecycle.
///
/// Both players may answer concurrently — ownership here is never
/// turn-based, only identity-based, the same [GameController.isCurrentUser] /
/// `_isMinePlayerId` matching every other round already uses. Nothing here
/// mutates state — dialogs are presentation only; C-2's `canSubmitComebackAnswer`
/// already owns eligibility. Every dialog below is enqueued against `_s.phase`
/// itself, not a hardcoded `GamePhase.comeBack`, so the queue's dequeue-time
/// re-check (`_s.phase != phase`) is correct whichever of the two rounds is
/// actually active.
extension ComebackDialogHandler on GameController {
  /// `TimeStarted` — the same Start Timer overlay WDYK/Bell/Auction already
  /// show for this event, now confirmed for Comeback (and Breaker) too:
  /// native `GameControllerFragment.startTimer()` plays `start_time_t30`,
  /// shows the timer Lottie for 2000ms, and only then sets
  /// `_isStartTimer = true` (what gates chip binding/visibility on the
  /// native side). Presentation only — the shared round content derives
  /// "question ready to reveal" independently, from the same `TimeStarted`
  /// event plus this same 2000ms window, not from this dialog's own
  /// lifecycle.
  void onComebackTimeStarted(
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    _enqueueRoundDialog(
      _s.phase,
      showDialog,
      RoundLottieDialog(
        timer: _comebackLongDialogMs,
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

  // CorrectAnswer shows the answer itself, attributed only when it was not
  // this device's (unlike Bell, which shows the same unconditional dialog to
  // both).
  void onComebackCorrectAnswer(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final playerId = _correctAnswerPlayerIdFrom(data);
    final isMine = _isMinePlayerId(playerId);
    if (isMine == null) {
      AppLogger.log(
        'GameController — comeback ${PlayGameHubEvents.correctAnswer} '
        'player unresolved | data: $data',
      );
      return;
    }
    final strings =
    PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    // The answer bar carries the text itself, so an unreadable payload has
    // nothing to show — same guard every other PlayerAnsweredDialog site uses.
    final answer = _answeredTextFromData(data);
    if (answer.isEmpty) {
      AppLogger.log(
        'GameController — comeback ${PlayGameHubEvents.correctAnswer} '
        'answer text missing | data: $data',
      );
      return;
    }
    if (isMine) {
      _enqueueRoundDialog(
        _s.phase,
        showDialog,
        RoundLottieDialog(
          text: strings.correctAnswer,
          timer: _comebackShortDialogMs,
          sound: AppSounds.rightAnswer,
          lottie: const AppLottieView.correctAnswer(
            width: double.infinity,
            height: 300,
            fit: BoxFit.contain,
          ),
        ),
      );
      return;
    }
    final name = _playerNameForId(playerId);
    if (name.isEmpty) {
      return;
    }
    _enqueueRoundDialog(
      _s.phase,
      showDialog,
      PlayerAnsweredDialog(
        answer: answer,
        playerName: name,
        timer: _comebackLongDialogMs,
      ),
    );
  }

  /// `Penalty` — `type` 1 timeout (both players, matching the reference's
  /// unqualified description), `type` 2 wrong (the player it happened to
  /// only — the reference is explicit the other player sees nothing).
  void onComebackPenalty(
    Map<String, dynamic>? data,
    Future<void> Function({required Widget child, bool barrierDismissible})
        showDialog,
  ) {
    final type = TypePenalty.fromId(_penaltyTypeFrom(data));
    if (type == null) {
      AppLogger.log(
        'GameController — comeback ${PlayGameHubEvents.penalty} type '
        'unresolved | data: $data',
      );
      return;
    }
    final strings =
        PlayGameStrings.forLanguage(ref.read(appLanguageProvider));
    if (type == TypePenalty.timeout) {
      _enqueueRoundDialog(
        _s.phase,
        showDialog,
        RoundLottieDialog(
          text: strings.timeout,
          timer: _comebackShortDialogMs,
          sound: AppSounds.timeOver,
          lottie: const AppLottieView.circularRed(
            width: double.infinity,
            height: 300,
            fit: BoxFit.contain,
          ),
        ),
      );
      return;
    }
    final playerId = GameSessionReducer.playerIdFrom(data) ?? '';
    final isMine = _isMinePlayerId(playerId);
    if (isMine != true) {
      return;
    }
    _enqueueRoundDialog(
      _s.phase,
      showDialog,
      RoundLottieDialog(
        text: strings.wrongAnswer,
        timer: _comebackShortDialogMs,
        sound: AppSounds.wrongAnswer,
        lottie: const AppLottieView.wrongAnswer(
          width: double.infinity,
          height: 300,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
