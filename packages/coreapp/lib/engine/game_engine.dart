import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_provider.dart';
import '../constants/api_endpoints.dart';
import '../constants/app_language.dart';
import '../di/providers.dart';
import '../l10n/app_strings.dart';
import '../presentation/providers/app_language_provider.dart';
import '../signalr/signalr_provider.dart';
import '../signalr/signalr_status.dart';
import '../utils/app_logger.dart';
import 'game_engine_config.dart';
import 'game_engine_connection_state.dart';
import 'game_engine_host.dart';

// The public Game Engine API — the whole surface a native host talks to.
//
// Nothing internal crosses this boundary: no SignalRService, no
// GameController, no providers, no BuildContext, no game state. The host gets
// value types (GameEngineConfig, GameEngineConnectionState) and futures.
//
// This class owns no connection logic of its own. SignalRService remains the
// single owner of connecting, reconnecting, recovery, backoff and app
// pause/resume; the engine only exposes the capability and enforces the
// idempotency the host contract promises.
class GameEngine {
  GameEngine({required ProviderContainer container, GameEngineHost? host})
      : _container = container {
    if (host != null) {
      registerHost(host);
    }
  }

  final ProviderContainer _container;
  GameEngineHost? _host;

  final _connectionStates =
      StreamController<GameEngineConnectionState>.broadcast();
  StreamSubscription<SignalRStatus>? _statusSubscription;

  // Re-emitted from the registered host rather than handed through, so a
  // subscriber that attached before the host was registered — the native
  // bridge does exactly that — still sees every exit.
  final _gameExits = StreamController<void>.broadcast();
  StreamSubscription<void>? _hostExitSubscription;

  GameEngineConfig? _appliedConfig;

  // The configuration the host set while a game was running. Held rather than
  // applied, so the active game keeps the one it started with.
  GameEngineConfig? _pendingConfig;

  Future<void>? _connectInFlight;
  bool _disposed = false;

  // Registered by the game plugin's own glue. Null until then, which is why
  // every flow call reports rather than throws — a host calling a flow before
  // the engine is mounted is a sequencing bug on their side, not a crash.
  void registerHost(GameEngineHost host) {
    if (_disposed) {
      return;
    }
    _host = host;
    // One subscription at a time: re-registering replaces the source rather
    // than adding a second one, so a re-registered host cannot double an exit.
    unawaited(_hostExitSubscription?.cancel());
    _hostExitSubscription = host.onGameExited.listen((_) {
      if (!_gameExits.isClosed) {
        _gameExits.add(null);
      }
    });
  }

  bool get isDisposed => _disposed;

  // The configuration currently in effect. Null before the first initialize.
  GameEngineConfig? get activeConfig => _appliedConfig;

  // Set only while a config change is waiting for the active game to end.
  GameEngineConfig? get pendingConfig => _pendingConfig;

  bool get isGameActive => _host?.isGameActive ?? false;

  GameEngineConnectionState get connectionState {
    _throwIfDisposed();
    return GameEngineConnectionState.fromStatus(
      _container.read(signalRServiceProvider).checkConnectionStatus(),
    );
  }

  // Future changes only — the host reads [connectionState] for the value it
  // has right now. Broadcast, so several native listeners are fine.
  Stream<GameEngineConnectionState> get onConnectionStateChanged {
    _throwIfDisposed();
    _startWatchingStatus();
    return _connectionStates.stream;
  }

  // Fires once each time the game route is actually removed — a Back gesture,
  // closing the result dialog, or a host-initiated [leaveGame] all arrive
  // here, and all arrive once, because the game has a single exit owner.
  //
  // Not a "game over" signal: reaching GameOver and showing the result dialog
  // is not an exit, and nothing is emitted until the route itself goes. It
  // carries no payload — the host is being told the surface is gone.
  Stream<void> get onGameExited {
    _throwIfDisposed();
    return _gameExits.stream;
  }

  // First configuration. Applied immediately: initialize is by definition
  // outside a game.
  Future<void> initialize(GameEngineConfig config) async {
    _throwIfDisposed();
    AppLogger.log('GameEngine — initialize');
    await _apply(config);
    _startWatchingStatus();
  }

  // A later configuration change.
  //
  // Outside a game it is applied at once. Inside one it is held: the running
  // game keeps the configuration it started with — a language flip or a muted
  // track mid-round is exactly the silent change the contract forbids — and
  // the held value is applied when the game ends, so the next session gets it.
  Future<void> updateConfig(GameEngineConfig config) async {
    _throwIfDisposed();
    if (isGameActive) {
      AppLogger.log('GameEngine — updateConfig deferred, game active');
      _pendingConfig = config;
      return;
    }
    await _apply(config);
  }

  // Applies a configuration that was held during a game. Called by the engine
  // itself after a leave; safe and cheap when nothing is pending.
  Future<void> applyPendingConfig() async {
    final pending = _pendingConfig;
    if (_disposed || pending == null) {
      return;
    }
    _pendingConfig = null;
    AppLogger.log('GameEngine — applying deferred config');
    await _apply(pending);
  }

  // Connects the hub, once.
  //
  // Idempotent by contract: connected, connecting and reconnecting all return
  // without starting anything, and concurrent calls share the one in-flight
  // future rather than racing. The underlying SignalRService has its own
  // `_skipIfAlreadyConnected` guard too — this is the outer half, so the host
  // never even reaches the service with a redundant request.
  Future<void> connectHub() {
    _throwIfDisposed();
    final inFlight = _connectInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final service = _container.read(signalRServiceProvider);
    final status = service.checkConnectionStatus();
    if (service.hasLiveConnection ||
        status == SignalRStatus.connecting ||
        status == SignalRStatus.reconnecting) {
      AppLogger.log('GameEngine — connectHub skipped, already live');
      return Future<void>.value();
    }
    _startWatchingStatus();
    AppLogger.log('GameEngine — connectHub');
    final future = service
        .connectIfNeeded(
          url: ApiEndpoints.signalRHubUrl,
          // Read per attempt, not captured: a token written after this call
          // is still the one used when the attempt actually runs.
          accessTokenFactory: () async =>
              _container.read(sharedPrefsProvider).getToken() ?? '',
        )
        .whenComplete(() => _connectInFlight = null);
    _connectInFlight = future;
    return future;
  }

  Future<void> joinRandomGame() async {
    _throwIfDisposed();
    await _requireHost()?.joinRandomGame();
  }

  Future<void> createPrivateGame(List<int> interestIds) async {
    _throwIfDisposed();
    await _requireHost()?.createPrivateGame(List<int>.unmodifiable(interestIds));
  }

  Future<void> joinPrivateGame(String code) async {
    _throwIfDisposed();
    await _requireHost()?.joinPrivateGame(code);
  }

  // Host-initiated exit. Goes through the game's own single exit owner — this
  // opens no second LeaveGame path. A configuration held during the game is
  // applied once the game is gone.
  Future<void> leaveGame() async {
    _throwIfDisposed();
    await _requireHost()?.leaveGame();
    await applyPendingConfig();
  }

  // Engine teardown, for when the native host destroys or detaches it.
  //
  // Deliberately NOT a hub disconnect on its own account: the hub is
  // app-lifetime by design and leaving a game never drops it. Disposing the
  // container, however, disposes signalRServiceProvider with it, and that
  // provider's own onDispose tears the connection down — so the hub goes when
  // the engine goes, and only then.
  //
  // Idempotent: a second call does nothing.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    AppLogger.log('GameEngine — dispose');
    _host = null;
    _pendingConfig = null;
    _connectInFlight = null;
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    // Disposal is not itself an exit: the subscription is dropped before the
    // stream closes, so tearing the engine down emits no onGameExited. A host
    // that wants the event must leave the game first — leaveGame() then
    // dispose() produces exactly one, from the leave.
    await _hostExitSubscription?.cancel();
    _hostExitSubscription = null;
    await _connectionStates.close();
    await _gameExits.close();
  }

  Future<void> _apply(GameEngineConfig config) async {
    final prefs = _container.read(sharedPrefsProvider);
    await prefs.setToken(value: config.token);
    await prefs.setSocialMediaId(value: config.socialMediaId);

    // Only when the host actually supplied one. `getUserId()` reads 0 as
    // "no account", so writing a 0 through would erase an id the module's
    // own login flow had already persisted — the same reason
    // `AuthNotifier._persist` guards its write. A host that sends the id
    // owns the value; one that sends nothing leaves it alone.
    if (config.userId > 0) {
      await prefs.setUserId(value: config.userId.toString());
    }

    // Through the existing notifier, not the prefs key: it persists, updates
    // AppStrings and rebuilds the UI in one step.
    await _container
        .read(appLanguageProvider.notifier)
        .setLanguage(AppLanguage.normalize(config.language));
    AppStrings.setLanguage(AppLanguage.normalize(config.language));

    // The existing setters, not a second AudioService. AudioService reads
    // these two flags in its constructor, so writing the prefs alone would
    // not reach an instance that already exists — these do, and persist.
    final audio = _container.read(audioServiceProvider);
    await audio.setMusicEnabled(config.musicEnabled);
    await audio.setSfxEnabled(config.soundEnabled);

    _appliedConfig = config.copyWith(
      language: AppLanguage.normalize(config.language),
    );

    // A hub that failed for want of a usable token gets one retry once the
    // host supplies a token; otherwise nothing would ever reconnect it.
    final service = _container.read(signalRServiceProvider);
    if (config.token.isNotEmpty &&
        service.checkConnectionStatus() == SignalRStatus.failed &&
        !service.hasLiveConnection) {
      unawaited(service.recoverConnection());
    }
  }

  void _startWatchingStatus() {
    if (_disposed || _statusSubscription != null) {
      return;
    }
    _statusSubscription =
        _container.read(signalRServiceProvider).statusStream.listen((status) {
      if (_connectionStates.isClosed) {
        return;
      }
      _connectionStates.add(GameEngineConnectionState.fromStatus(status));
    });
  }

  GameEngineHost? _requireHost() {
    final host = _host;
    if (host == null) {
      AppLogger.log(
        'GameEngine — no host registered; game flow request ignored',
      );
    }
    return host;
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError('GameEngine has been disposed.');
    }
  }
}
