import 'package:coreapp/coreapp.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';

// The production entry point a native host targets.
//
// Deliberately separate from `main()`, which stays exactly as it is — that
// one is the development launcher (HomeLauncherPage, DebugConfig, the
// "Register"/"Start Hub" buttons) and is not what a host embeds.
//
// It lives here rather than in coreapp because it is the one place both
// packages are visible: coreapp owns the Public API and cannot depend on a
// game plugin (ENGINEERING_RULES §12.4), and the game flows it registers are
// play_game's. Nothing game-specific moved into coreapp to make this work.
//
// The engine boots idle. No token, no language, no audio setting and no
// connection is assumed — the host sends configuration through
// GameEngine.initialize and then drives the flows. Inventing defaults here
// would put the host's product decisions inside the engine.
@pragma('vm:entry-point')
Future<void> gameEngineMain() async {
  final runtime = await startGameEngine();
  runApp(runtime.buildApp());
}

// The entry point's body, without `runApp`, so the boot sequence can be
// exercised without pumping a real app.
Future<GameEngineRuntime> startGameEngine({
  List<Override> overrides = const [],
  bool attachNativeBridge = true,
}) async {
  final runtime = await GameEngineRuntime.start(
    overrides: overrides,
    attachNativeBridge: attachNativeBridge,
  );
  // The game-flow half of the Public API. coreapp declares GameEngineHost;
  // play_game implements it, and the two only meet here.
  runtime.registerHost(
    PlayGameEngineHost(
      navigatorKey: runtime.navigatorKey,
      container: runtime.container,
    ),
  );
  // D3: `onEngineReady`, and not a moment earlier.
  //
  // Everything above is done by now — prefs loaded, container built, bridge
  // attached, host registered. What is still missing at this line is the
  // navigator: `runApp` has not been called yet, so a host acting on the event
  // immediately could ask for a game flow that PlayGameEngineHost would have
  // to drop for want of a navigator. Deferring to the end of the first frame
  // closes that too, and the first frame is the one `runApp` schedules
  // directly after this returns.
  //
  // Registered here rather than in `gameEngineMain` so the ordering that
  // native depends on is inside the function the tests exercise.
  WidgetsBinding.instance.addPostFrameCallback((_) => runtime.markReady());
  return runtime;
}
