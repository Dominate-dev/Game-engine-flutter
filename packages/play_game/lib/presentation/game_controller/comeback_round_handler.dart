part of 'game_controller.dart';

/// Comeback (round 4) — a limited-try catch-up.
///
/// Unlike Bell/WDYK, both players may answer concurrently: eligibility comes
/// from each player's own `makeupTryCount` / `maxMakeupTryCount`, never from
/// `currentTurn` (C-1 confirmed contract — T30's PvP UI does not hide chips
/// by turn).
///
/// Breaker (round 5) is confirmed to share this exact behavior — the native
/// reference describes it as "almost the same screen" as Comeback — so this
/// extension deliberately serves both rounds rather than being duplicated
/// under a Breaker-specific name. Comeback remains the source of truth;
/// every phase check below is widened to `comeBack || breaker`, never
/// renamed or restructured.
extension ComebackRoundHandler on GameController {
  /// Whether this device's own player may submit an answer right now.
  ///
  /// Server-authoritative and per-player, the same shape as Auction's
  /// `isAuctionWrongLimitReached` — the opponent's count never affects this,
  /// and `currentTurn` is deliberately not consulted. A timeout additionally
  /// locks this beyond what the tries count alone covers, matching the
  /// native `adapter.isClickable = false; timeOut()` pairing — cleared only
  /// by a genuine new question, never by this getter or by a dialog.
  bool get canSubmitComebackAnswer {
    if (_s.phase != GamePhase.comeBack && _s.phase != GamePhase.breaker) {
      return false;
    }
    if (_s.comebackAnswerLocked) {
      return false;
    }
    final me = _s.me;
    if (me == null) {
      return false;
    }
    return me.makeupTryCount < me.maxMakeupTryCount;
  }

  /// Submits one Comeback/Breaker answer. Same hub method and positional
  /// encoding every other round's submit already uses — only the guard
  /// differs.
  Future<bool> submitComebackAnswer(int answerId) async {
    if (!canSubmitComebackAnswer) {
      return false;
    }
    final gameId = _s.game?.id ?? '';
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.submitAnswer} (comeback) '
      '| gameId: $gameId | answerId: $answerId',
    );
    return ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.submitAnswer,
          args: [gameId, answerId],
        );
  }
}
