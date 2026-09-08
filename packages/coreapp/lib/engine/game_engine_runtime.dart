import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import '../l10n/app_strings.dart';
import '../storage/shared_prefs_service.dart';
import '../utils/app_lifecycle_observer.dart';
import '../utils/app_logger.dart';
import '../signalr/signalr_provider.dart';
import 'game_engine.dart';
import 'game_engine_channel.dart';
import 'game_engine_host.dart';
import 'game_engine_root.dart';

// Owns everything the engine creates, so detaching can actually undo it.
//
// S8 in TASKS.md: `main()` builds a ProviderContainer and adds a lifecycle
// observer with no disposal path. That is invisible in a standalone app and a
// real leak once a native host attaches and detaches repeatedly. Bundling the
// four together — container, observer, engine, bridge — is what makes
// [dispose] able to reverse [start].
//
// The navigator key lives here too. AppTheme.navigatorKey is
// `kDebugMode ? ChuckerFlutter.navigatorKey : null` — null in release, so it
// cannot carry host-driven navigation.
class GameEngineRuntime {
  GameEngineRuntime._({
    required this.container,
    required this.engine,
    required this.navigatorKey,
    required AppLifecycleObserver observer,
    GameEngineChannel? channel,
  })  : _observer = observer,
        _channel = channel;

  final ProviderContainer container;
  final GameEngine engine;
  final GlobalKey<NavigatorState> navigatorKey;

  final AppLifecycleObserver _observer;
  GameEngineChannel? _channel;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  // Whether the native bridge is currently listening.
  bool get isBridgeAttached => _channel != null;

  // Builds the runtime. Does not connect the hub, does not configure anything
  // and shows nothing on its own — the host decides all three, through the
  // Public API, in that order.
  //
  // [overrides] is passed to the container. Provided for a host that must
  // substitute infrastructure (and used by the runtime's own tests) — it is a
  // normal Riverpod affordance, not a test-only hook.
  static Future<GameEngineRuntime> start({
    GlobalKey<NavigatorState>? navigatorKey,
    MethodChannelFactory? channelFactory,
    bool attachNativeBridge = true,
    List<Override> overrides = const [],
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPrefsService.init();
    // Whatever the host last persisted. Nothing is invented here: a token,
    // user id, language or audio flag arrives through GameEngine.initialize.
    AppStrings.setLanguage(prefs.getLanguage());

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        ...overrides,
      ],
    );
    final observer = AppLifecycleObserver(
      container.read(signalRServiceProvider),
    );
    WidgetsBinding.instance.addObserver(observer);

    final engine = GameEngine(container: container);
    final runtime = GameEngineRuntime._(
      container: container,
      engine: engine,
      navigatorKey: navigatorKey ?? GlobalKey<NavigatorState>(),
      observer: observer,
    );
    if (attachNativeBridge) {
      runtime._channel = channelFactory != null
          ? channelFactory(engine)
          : GameEngineChannel(engine: engine);
      // B1: native's `dispose` must reach *this* teardown, not the bridge's
      // own partial one. Bound before attach, so the very first native call
      // already has the full path available.
      runtime._channel!
        ..bindTeardown(runtime.dispose)
        ..attach();
    }
    AppLogger.log('GameEngineRuntime — started');
    return runtime;
  }

  // The widget tree to hand to runApp: the engine's root under this runtime's
  // own container, with this runtime's own navigator.
  Widget buildApp({Widget? idle}) {
    return UncontrolledProviderScope(
      container: container,
      child: GameEngineRoot(navigatorKey: navigatorKey, idle: idle),
    );
  }

  void registerHost(GameEngineHost host) => engine.registerHost(host);

  // Tells native the engine is ready for public API commands.
  //
  // Called by the entry point once the whole boot sequence is done — runtime
  // started, bridge attached, game-flow host registered, first frame up — so
  // a host that acts on the event immediately can call any public method, not
  // only the ones that happen not to need a navigator. Deliberately not fired
  // inside [start]: start is one step of that sequence, not the end of it.
  //
  // At most once, and never without an attached bridge; both guards live in
  // the channel. A runtime started with `attachNativeBridge: false` has no
  // native to tell, so this is a no-op.
  void markReady() {
    if (_disposed) {
      return;
    }
    _channel?.notifyEngineReady();
  }

  // Reverses [start], once, in the order the pieces were built.
  //
  //   detach bridge -> dispose engine -> remove observer -> dispose container
  //
  // The bridge goes first so no native call can land mid-teardown; the
  // observer goes before the container so a lifecycle callback cannot reach a
  // service that is about to be disposed.
  //
  // The hub is app-lifetime and leaving a game never drops it — but disposing
  // the container disposes signalRServiceProvider, whose own onDispose tears
  // the connection down. So the hub goes when the *engine* goes, and only
  // then. That is the documented behaviour, not an accident.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    AppLogger.log('GameEngineRuntime — dispose');
    await _channel?.detach();
    _channel = null;
    await engine.dispose();
    WidgetsBinding.instance.removeObserver(_observer);
    container.dispose();
  }
}

typedef MethodChannelFactory = GameEngineChannel Function(GameEngine engine);
