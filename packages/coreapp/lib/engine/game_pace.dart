// How the game paces itself between steps.
//
// The server waits between game steps so the app can show a message ("your
// turn", "time started", the round intro). The released apps block play
// behind those messages and chain them, which made games slow and tiring.
//
// With fast pacing this module shows round messages as short banners that
// never block a tap and replace each other instead of queueing, and it asks
// the server for its fast pacing ("game-pace: fast"), which shortens or drops
// those waits. The server only uses fast pacing when every human player in
// the game asked for it, so a game against a released app stays classic.
//
// Mutable only so tests can pin the classic behaviour they were written for.
abstract final class GamePace {
  static bool fast = true;

  /// A message lifetime: the classic one, or a little over half of it.
  static int messageMs(int classicMs) => fast ? (classicMs * 0.55).round() : classicMs;
}
