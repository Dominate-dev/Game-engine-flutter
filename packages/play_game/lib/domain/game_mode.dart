/// Native `CreatedGame.mode` values.
///
/// Only the value this repository has a confirmed contract for is declared —
/// the other modes the backend may send are not established here and are
/// deliberately not guessed at.
abstract final class GameMode {
  /// Private PvP — the invite-code 1v1 game created by `CreatePrivateGame`.
  static const privatePvp = 4;
}
