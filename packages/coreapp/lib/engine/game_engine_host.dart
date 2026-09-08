// The game-flow half of the public API, inverted.
//
// `coreapp` owns the integration boundary but must never depend on a game
// plugin (ENGINEERING_RULES §12.4 — plugins depend on coreapp, never the
// reverse). So the engine declares what a game flow must be able to do, and
// the plugin that owns those flows registers an implementation. Nothing about
// rounds, lobbies, dialogs or game state crosses back.
//
// Every method is a *request*: the implementation decides what showing a flow
// means, and reports back only whether the request was accepted.
abstract class GameEngineHost {
  // True while a game flow is on screen. The engine reads this to decide
  // whether a configuration change may be applied now or has to wait for the
  // next session — an active game keeps the configuration it started with.
  bool get isGameActive;

  Future<void> joinRandomGame();

  Future<void> createPrivateGame(List<int> interestIds);

  Future<void> joinPrivateGame(String code);

  // Leaves through the game's own single exit owner. Must be a no-op when no
  // game is active, and must not open a second LeaveGame path.
  Future<void> leaveGame();

  // Fires once each time an active game's route is actually removed, whatever
  // caused it — a Back gesture, closing the result dialog, or a host-initiated
  // [leaveGame].
  //
  // It carries nothing: the host is being told the game surface is gone, and
  // any payload would be game state crossing a boundary that exists to stop
  // exactly that. Implementations must emit from their single exit owner, so
  // two paths reaching the same exit produce one event.
  //
  // Broadcast: the engine subscribes, and so may Flutter-side glue.
  Stream<void> get onGameExited;
}
