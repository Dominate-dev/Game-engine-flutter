import 'dart:async';

import 'package:flutter/services.dart';

import '../utils/app_logger.dart';
import 'game_engine.dart';
import 'game_engine_config.dart';
import 'game_engine_connection_state.dart';

// The native bridge: one MethodChannel, both directions.
//
// Why not an EventChannel for onConnectionStateChanged — the engine pushes
// state to native with `invokeMethod` on the same channel. A second channel
// would mean a second native registration, a second lifecycle to tear down,
// and a stream that can outlive the method handler. One channel keeps the
// native side to a single object.
//
// Why not Pigeon — it would add a codegen dependency and a build step for a
// nine-method, value-type-only surface (MA2 in TASKS.md: five codegen packages
// are declared and unused, and using one for the first time needs approval).
// The payloads here are primitives, lists of int, and string maps, which the
// standard codec already carries.
//
// There is no game logic in this file. It decodes, calls the public API, and
// encodes the reply.
class GameEngineChannel {
  GameEngineChannel({
    required GameEngine engine,
    MethodChannel? channel,
  })  : _engine = engine,
        _channel = channel ?? const MethodChannel(channelName);

  // Native must use this exact name. Changing it is a breaking change for the
  // host, so it lives here rather than being spelled out at a call site.
  static const channelName = 'com.gameengine/public_api';

  // Native → engine.
  static const methodInitialize = 'initialize';
  static const methodUpdateConfig = 'updateConfig';
  static const methodConnectHub = 'connectHub';
  static const methodConnectionState = 'connectionState';
  static const methodJoinRandomGame = 'joinRandomGame';
  static const methodCreatePrivateGame = 'createPrivateGame';
  static const methodJoinPrivateGame = 'joinPrivateGame';
  static const methodLeaveGame = 'leaveGame';
  static const methodDispose = 'dispose';

  // Engine → native.
  static const methodOnConnectionStateChanged = 'onConnectionStateChanged';

  // Pushed once, after the runtime has finished starting and this handler is
  // installed. Until native sees it, a call can land before the handler exists
  // and come back as MissingPluginException — this is what removes the need to
  // retry or to poll connectionState for readiness. No argument.
  static const methodOnEngineReady = 'onEngineReady';

  // Pushed each time the game route is actually removed. No argument.
  static const methodOnGameExited = 'onGameExited';

  static const errorBadArguments = 'bad_arguments';
  static const errorEngineDisposed = 'engine_disposed';
  static const errorFailed = 'engine_error';

  final GameEngine _engine;
  final MethodChannel _channel;

  StreamSubscription<GameEngineConnectionState>? _stateSubscription;
  StreamSubscription<void>? _exitSubscription;
  Future<void> Function()? _teardown;
  bool _attached = false;
  bool _readySent = false;

  // The full-runtime teardown that native's `dispose` must perform.
  //
  // Set by GameEngineRuntime, which owns the container, the lifecycle observer
  // and this bridge. Without it the bridge could only dispose the GameEngine,
  // which leaves the container — and therefore SignalR and the observer —
  // alive: a bridge that has gone deaf while the engine it fronted is still
  // running. The bridge does not implement teardown of its own; it calls the
  // one that already exists.
  void bindTeardown(Future<void> Function() teardown) => _teardown = teardown;

  // Starts listening for native calls and pushing engine events back.
  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    _channel.setMethodCallHandler(_handle);
    _stateSubscription = _engine.onConnectionStateChanged.listen((state) {
      _push(methodOnConnectionStateChanged, state.wireName);
    });
    // Subscribed here rather than at host registration: the host is registered
    // after the runtime starts, and the engine re-emits on its own controller,
    // so attaching first loses nothing.
    _exitSubscription = _engine.onGameExited.listen((_) {
      _push(methodOnGameExited);
    });
  }

  // Tells native the runtime is up and this handler is installed, so public
  // API commands will be received. Sent at most once, and never before
  // [attach] — a readiness signal that could precede the handler would be
  // exactly the race it exists to remove.
  void notifyEngineReady() {
    if (!_attached || _readySent) {
      return;
    }
    _readySent = true;
    _push(methodOnEngineReady);
  }

  Future<void> detach() async {
    if (!_attached) {
      return;
    }
    _attached = false;
    _channel.setMethodCallHandler(null);
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    await _exitSubscription?.cancel();
    _exitSubscription = null;
  }

  void _push(String method, [Object? argument]) {
    unawaited(
      _channel
          .invokeMethod<void>(method, argument)
          // A host that has gone away is not an error worth throwing over.
          .catchError((Object error) {
        AppLogger.log('GameEngineChannel — $method push failed: $error');
      }),
    );
  }

  Future<Object?> _handle(MethodCall call) async {
    try {
      switch (call.method) {
        case methodInitialize:
          await _engine.initialize(_configFrom(call));
          return null;
        case methodUpdateConfig:
          await _engine.updateConfig(_configFrom(call));
          return null;
        case methodConnectHub:
          await _engine.connectHub();
          return null;
        case methodConnectionState:
          return _engine.connectionState.wireName;
        case methodJoinRandomGame:
          await _engine.joinRandomGame();
          return null;
        case methodCreatePrivateGame:
          await _engine.createPrivateGame(_interestIdsFrom(call));
          return null;
        case methodJoinPrivateGame:
          await _engine.joinPrivateGame(_codeFrom(call));
          return null;
        case methodLeaveGame:
          await _engine.leaveGame();
          return null;
        case methodDispose:
          // The runtime's own teardown, when one is bound: it detaches this
          // bridge, disposes the engine, removes the lifecycle observer and
          // disposes the container — which is what lets signalRServiceProvider's
          // onDispose take the hub down. Idempotent on both sides, so a second
          // native dispose is a no-op rather than a crash.
          final teardown = _teardown;
          if (teardown != null) {
            await teardown();
            return null;
          }
          // No runtime bound (a bridge constructed on its own). Everything this
          // bridge actually owns still goes.
          await detach();
          await _engine.dispose();
          return null;
        default:
          throw MissingPluginException(
            'GameEngineChannel — unknown method ${call.method}',
          );
      }
    } on StateError catch (error) {
      throw PlatformException(
        code: errorEngineDisposed,
        message: error.message,
      );
    } on ArgumentError catch (error) {
      throw PlatformException(
        code: errorBadArguments,
        message: error.message?.toString() ?? 'invalid arguments',
      );
    } on MissingPluginException {
      rethrow;
    } catch (error) {
      throw PlatformException(code: errorFailed, message: '$error');
    }
  }

  GameEngineConfig _configFrom(MethodCall call) {
    final arguments = call.arguments;
    if (arguments is! Map) {
      throw ArgumentError('${call.method} expects a configuration map');
    }
    return GameEngineConfig.fromMap(Map<Object?, Object?>.from(arguments));
  }

  List<int> _interestIdsFrom(MethodCall call) {
    final arguments = call.arguments;
    final raw = arguments is Map ? arguments['interestIds'] : arguments;
    if (raw is! List) {
      throw ArgumentError('$methodCreatePrivateGame expects interestIds');
    }
    final ids = <int>[];
    for (final value in raw) {
      final id = value is int ? value : int.tryParse('$value');
      if (id == null) {
        throw ArgumentError('interestIds must be integers, got "$value"');
      }
      ids.add(id);
    }
    if (ids.isEmpty) {
      throw ArgumentError('interestIds must not be empty');
    }
    return ids;
  }

  String _codeFrom(MethodCall call) {
    final arguments = call.arguments;
    final raw = arguments is Map ? arguments['code'] : arguments;
    final code = raw?.toString().trim() ?? '';
    if (code.isEmpty) {
      throw ArgumentError('$methodJoinPrivateGame expects a non-empty code');
    }
    return code;
  }
}
