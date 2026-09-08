part of 'game_controller.dart';

/// Bell (round 3) — buzz race, then the winner answers chips.
///
/// The race result is `ChangeTurn`, the same shared field WDYK's turn already
/// uses — so "who is answering" is `GameSessionState.isMyTurn` /
/// `isOpponentTurn`, not a second identity field. The one thing Bell alone
/// needs is [GameSessionState.bellArmed]: whether the button may be tapped
/// right now, which no existing field represents.
extension BellRoundHandler on GameController {
  /// Idle (waiting for `TimeStarted`), Racing (armed, no turn yet), or
  /// Answering (`ChangeTurn` named a winner — mine or the opponent's).
  BellPhase get bellPhase {
    if (_hasBellTurn) {
      return BellPhase.answering;
    }
    return _s.bellArmed ? BellPhase.racing : BellPhase.idle;
  }

  /// The Bell button's visibility, per the reference's `isBelling`.
  bool get isBellVisible => bellPhase == BellPhase.racing;

  /// Whether tapping Bell right now may actually send `RingBell`.
  bool get canRingBell => bellPhase == BellPhase.racing;

  bool get _hasBellTurn => (_s.game?.currentTurn?.trim() ?? '').isNotEmpty;

  /// PvP buzz. Sends the request only — the server decides the winner via
  /// `ChangeTurn`, so nothing here marks a local winner or hides the button;
  /// `bellArmed` only changes when that `ChangeTurn` (or a Penalty / next
  /// question) actually arrives.
  Future<bool> ringBell() async {
    if (!canRingBell) {
      return false;
    }
    final gameId = _s.game?.id ?? '';
    AppLogger.log(
      'GameController — invoke ${PlayGameHubEvents.ringBell} | '
      'gameId: $gameId',
    );
    return ref.read(signalRServiceProvider).invoke(
          PlayGameHubEvents.ringBell,
          args: [gameId],
        );
  }

  /// `bellArmed` after [name], given the game already reduced for every
  /// other field this event carries. `null` means "leave it as it is".
  ///
  /// `TimeStarted` arms it only while no turn is assigned yet — restoring the
  /// exact `isBelling = isTurnPlaying == null && isStartTimer` rule from the
  /// reference. `ChangeTurn` (a winner **or** an explicit reset) and
  /// `Penalty` (timeout **or** wrong) both disarm it: the race is over
  /// either way, and Bell does not reappear until the next `TimeStarted`.
  bool? _nextBellArmed(String name, CreatedGame? nextGame) {
    if (name == PlayGameHubEvents.timeStarted) {
      return (nextGame?.currentTurn?.trim() ?? '').isEmpty;
    }
    if (name == PlayGameHubEvents.changeTurn ||
        name == PlayGameHubEvents.penalty) {
      return false;
    }
    return null;
  }
}
