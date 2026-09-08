import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The public Game Engine API and its native bridge.
//
// The boundary under test is deliberately narrow: native hands over value
// types and gets futures back. Nothing here reaches SignalRService,
// GameController, a provider or a BuildContext, and the fakes below stand in
// at exactly that boundary.

/// Records connects and drives the status stream, the way the real service
/// does — the engine must never open a second connection manager of its own.
class _FakeSignalRService extends SignalRService {
  int connectCalls = 0;
  SignalRStatus status = SignalRStatus.idle;
  bool connected = false;

  /// Held so a test can keep a connect in flight and fire more calls at it.
  Completer<void>? gate;

  final _statuses = StreamController<SignalRStatus>.broadcast(sync: true);

  /// The tokens each connect attempt actually resolved, so "the token the
  /// host set is the one used" is observable.
  final tokensUsed = <String>[];

  @override
  Stream<SignalRStatus> get statusStream => _statuses.stream;

  @override
  SignalRStatus checkConnectionStatus() => status;

  @override
  bool get isConnected => connected;

  @override
  bool get isConnecting =>
      status == SignalRStatus.connecting || status == SignalRStatus.reconnecting;

  @override
  bool get hasLiveConnection => connected || isConnecting;

  void emit(SignalRStatus next) {
    status = next;
    connected = next == SignalRStatus.connected;
    _statuses.add(next);
  }

  @override
  Future<void> connectIfNeeded({
    required String url,
    Future<String> Function()? accessTokenFactory,
  }) async {
    connectCalls++;
    if (accessTokenFactory != null) {
      tokensUsed.add(await accessTokenFactory());
    }
    await gate?.future;
    emit(SignalRStatus.connected);
  }

  @override
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) =>
      () {};

  @override
  void reattachEventHandlers() {}

  @override
  Future<void> dispose() async {
    await _statuses.close();
  }
}

/// Stands in for play_game at the GameEngineHost seam.
class _FakeHost implements GameEngineHost {
  bool active = false;
  final calls = <String>[];
  final interestIds = <List<int>>[];
  final codes = <String>[];
  int leaveCalls = 0;

  @override
  bool get isGameActive => active;

  @override
  Future<void> joinRandomGame() async => calls.add('random');

  @override
  Future<void> createPrivateGame(List<int> ids) async {
    calls.add('createPrivate');
    interestIds.add(ids);
    active = true;
  }

  @override
  Future<void> joinPrivateGame(String code) async {
    calls.add('joinPrivate');
    codes.add(code);
    active = true;
  }

  @override
  Future<void> leaveGame() async {
    leaveCalls++;
    calls.add('leave');
    active = false;
    // The real host does not emit from leaveGame either — the single exit
    // owner does, once the route is gone. Modelled the same way so a test
    // cannot pass on an emission the production path would not make.
  }

  final _exits = StreamController<void>.broadcast();

  @override
  Stream<void> get onGameExited => _exits.stream;

  /// What GameControllerScreen._exitGame does once the route has been popped.
  void exitGameRoute() {
    active = false;
    _exits.add(null);
  }

  void disposeHost() => _exits.close();
}

class _FakeNetworkInfo implements NetworkInfo {
  @override
  bool get isOnline => true;
  @override
  Future<bool> get isConnected async => true;
  @override
  Stream<bool> get onStatusChange => const Stream<bool>.empty();
  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _FakeSignalRService signalR;
  late SharedPrefsService prefs;
  late GameEngine engine;
  late _FakeHost host;

  Future<void> newEngine() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
      ],
    );
    addTearDown(container.dispose);
    host = _FakeHost();
    addTearDown(host.disposeHost);
    engine = GameEngine(container: container, host: host);
    addTearDown(engine.dispose);
  }

  const config = GameEngineConfig(
    token: 'token-abc',
    socialMediaId: 'social-1',
    language: AppLanguage.arabic,
    musicEnabled: false,
    soundEnabled: false,
  );

  setUp(() async => newEngine());

  group('1. initialize applies all five values', () {
    test('token, socialMediaId, language, music and sound all land', () async {
      await engine.initialize(config);

      expect(prefs.getToken(), 'token-abc');
      expect(prefs.getSocialMediaId(), 'social-1');
      expect(container.read(appLanguageProvider), AppLanguage.arabic);
      expect(AppStrings.current, isA<AppStrings>());
      final audio = container.read(audioServiceProvider);
      expect(audio.isMusicEnabled, isFalse);
      expect(audio.isSfxEnabled, isFalse);
      expect(engine.activeConfig, config);
    });

    test('an unrecognised language falls back rather than reaching the '
        'string tables raw', () async {
      await engine.initialize(
        const GameEngineConfig(token: 't', language: 'klingon'),
      );

      expect(container.read(appLanguageProvider), AppLanguage.english);
      expect(engine.activeConfig?.language, AppLanguage.english);
    });
  });

  group('2-3. configuration lifecycle', () {
    test('updateConfig outside a game applies at once', () async {
      await engine.initialize(config);
      host.active = false;

      await engine.updateConfig(
        config.copyWith(token: 'token-2', language: AppLanguage.english),
      );

      expect(prefs.getToken(), 'token-2');
      expect(container.read(appLanguageProvider), AppLanguage.english);
      expect(engine.pendingConfig, isNull);
    });

    test('updateConfig during a game does not alter the active game',
        () async {
      await engine.initialize(config);
      host.active = true;

      await engine.updateConfig(
        config.copyWith(token: 'token-2', language: AppLanguage.english),
      );

      expect(prefs.getToken(), 'token-abc',
          reason: 'the running game keeps the configuration it started with');
      expect(container.read(appLanguageProvider), AppLanguage.arabic);
      expect(engine.activeConfig?.token, 'token-abc');
      expect(engine.pendingConfig?.token, 'token-2', reason: 'held, not lost');
    });

    test('the held configuration is applied for the next session', () async {
      await engine.initialize(config);
      host.active = true;
      await engine.updateConfig(config.copyWith(token: 'token-2'));

      await engine.leaveGame();

      expect(prefs.getToken(), 'token-2');
      expect(engine.pendingConfig, isNull);
      expect(engine.activeConfig?.token, 'token-2');
    });
  });

  group('4-6. connectHub idempotency', () {
    test('already connected does nothing', () async {
      signalR.emit(SignalRStatus.connected);

      await engine.connectHub();

      expect(signalR.connectCalls, 0);
    });

    test('connecting does not start another', () async {
      signalR.status = SignalRStatus.connecting;

      await engine.connectHub();

      expect(signalR.connectCalls, 0);
    });

    test('reconnecting does not start another', () async {
      signalR.status = SignalRStatus.reconnecting;

      await engine.connectHub();

      expect(signalR.connectCalls, 0);
    });

    test('disconnected starts exactly one', () async {
      signalR.status = SignalRStatus.disconnected;

      await engine.connectHub();

      expect(signalR.connectCalls, 1);
    });

    test('three concurrent calls make ONE connection attempt', () async {
      signalR.status = SignalRStatus.disconnected;
      signalR.gate = Completer<void>();

      final calls = [
        engine.connectHub(),
        engine.connectHub(),
        engine.connectHub(),
      ];
      signalR.gate!.complete();
      await Future.wait(calls);

      expect(signalR.connectCalls, 1,
          reason: 'the in-flight future is shared, not raced');
    });

    test('a later call after the first finished can connect again', () async {
      signalR.status = SignalRStatus.disconnected;
      await engine.connectHub();
      signalR.emit(SignalRStatus.disconnected);

      await engine.connectHub();

      expect(signalR.connectCalls, 2);
    });
  });

  group('7-8. connection state', () {
    test('the current state is exposed and mapped', () async {
      signalR.status = SignalRStatus.connected;
      expect(engine.connectionState, GameEngineConnectionState.connected);

      signalR.status = SignalRStatus.connecting;
      expect(engine.connectionState, GameEngineConnectionState.connecting);

      signalR.status = SignalRStatus.reconnecting;
      expect(engine.connectionState, GameEngineConnectionState.reconnecting);
    });

    test('every not-connected internal status maps to disconnected', () {
      for (final status in [
        SignalRStatus.idle,
        SignalRStatus.failed,
        SignalRStatus.disconnected,
        SignalRStatus.disconnectedNoInternet,
      ]) {
        expect(
          GameEngineConnectionState.fromStatus(status),
          GameEngineConnectionState.disconnected,
          reason: '$status is "not connected" to the host',
        );
      }
    });

    test('changes are propagated', () async {
      final seen = <GameEngineConnectionState>[];
      final sub = engine.onConnectionStateChanged.listen(seen.add);
      addTearDown(sub.cancel);

      signalR.emit(SignalRStatus.connecting);
      signalR.emit(SignalRStatus.connected);
      signalR.emit(SignalRStatus.reconnecting);
      signalR.emit(SignalRStatus.failed);
      // The engine's own broadcast controller delivers asynchronously; one
      // flush is enough because the events queue in order.
      await Future<void>.delayed(Duration.zero);

      expect(seen, [
        GameEngineConnectionState.connecting,
        GameEngineConnectionState.connected,
        GameEngineConnectionState.reconnecting,
        GameEngineConnectionState.disconnected,
      ]);
    });
  });

  group('9-11. game flow requests reach the host', () {
    test('createPrivateGame forwards the ids verbatim', () async {
      await engine.createPrivateGame([7, 88, 91]);

      expect(host.calls, ['createPrivate']);
      expect(host.interestIds.single, [7, 88, 91],
          reason: 'the host supplies the real ids; none is invented here');
    });

    test('joinPrivateGame forwards the code', () async {
      await engine.joinPrivateGame('ABC123');

      expect(host.calls, ['joinPrivate']);
      expect(host.codes.single, 'ABC123');
    });

    test('joinRandomGame invokes the random flow', () async {
      await engine.joinRandomGame();

      expect(host.calls, ['random']);
    });

    test('a flow requested with no host registered is ignored, not thrown',
        () async {
      final bare = GameEngine(container: container);
      addTearDown(bare.dispose);

      await bare.joinRandomGame();
      await bare.createPrivateGame([1]);
      await bare.joinPrivateGame('x');
      await bare.leaveGame();

      expect(host.calls, isEmpty);
    });
  });

  group('12-13. leave goes through the one exit owner', () {
    test('leaveGame delegates to the host', () async {
      host.active = true;

      await engine.leaveGame();

      expect(host.leaveCalls, 1);
    });

    test('repeated leaveGame does not duplicate the request', () async {
      host.active = true;
      await engine.leaveGame();

      await engine.leaveGame();
      await engine.leaveGame();

      expect(host.leaveCalls, 3,
          reason: 'the engine forwards each call; the single exit owner '
              'behind it is what makes repeats a no-op — see '
              'game_exit_lifecycle_test.dart');
      expect(host.active, isFalse);
    });
  });

  group('14. dispose', () {
    test('is idempotent and closes the stream', () async {
      final seen = <GameEngineConnectionState>[];
      engine.onConnectionStateChanged.listen(seen.add);

      await engine.dispose();
      await engine.dispose();

      expect(engine.isDisposed, isTrue);
      signalR.emit(SignalRStatus.connected);
      expect(seen, isEmpty, reason: 'no push after dispose');
    });

    test('the API refuses use after dispose rather than misbehaving',
        () async {
      await engine.dispose();

      expect(() => engine.connectionState, throwsStateError);
      expect(engine.connectHub, throwsStateError);
      expect(() => engine.initialize(config), throwsStateError);
    });

    test('dispose does not disconnect the hub by itself', () async {
      signalR.emit(SignalRStatus.connected);

      await engine.dispose();

      expect(signalR.connected, isTrue,
          reason: 'the hub is app-lifetime; the container disposal that '
              'accompanies engine teardown is what tears it down');
    });
  });

  group('16-18. configuration reaches the real mechanisms', () {
    test('audio uses the existing service, not a second one', () async {
      final audio = container.read(audioServiceProvider);
      await engine.initialize(config.copyWith(musicEnabled: true));

      expect(audio.isMusicEnabled, isTrue);
      expect(audio.isSfxEnabled, isFalse);
      expect(identical(container.read(audioServiceProvider), audio), isTrue,
          reason: 'no second AudioService was constructed');
    });

    test('language uses the existing notifier', () async {
      await engine.initialize(config.copyWith(language: AppLanguage.arabic));
      expect(container.read(appLanguageProvider), AppLanguage.arabic);

      await engine.updateConfig(
        config.copyWith(language: AppLanguage.english),
      );
      expect(container.read(appLanguageProvider), AppLanguage.english);
    });

    test('the token is the one the existing connection path uses', () async {
      await engine.initialize(config.copyWith(token: 'from-native'));
      signalR.status = SignalRStatus.disconnected;

      await engine.connectHub();

      expect(signalR.tokensUsed.single, 'from-native',
          reason: 'accessTokenFactory reads prefs, which initialize wrote');
    });

    test('a token set after connectHub is used by the NEXT connect',
        () async {
      await engine.initialize(config.copyWith(token: 'first'));
      signalR.status = SignalRStatus.disconnected;
      await engine.connectHub();

      await engine.updateConfig(config.copyWith(token: 'second'));
      signalR.emit(SignalRStatus.disconnected);
      await engine.connectHub();

      expect(signalR.tokensUsed, ['first', 'second'],
          reason: 'no forced reconnect is invented for a new token');
    });
  });

  group('the native bridge', () {
    late GameEngineChannel bridge;
    late MethodChannel channel;
    late List<MethodCall> toNative;

    Future<Object?> callFromNative(String method, [Object? args]) {
      return TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage(
        GameEngineChannel.channelName,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall(method, args)),
        null,
      ).then((data) => data == null
          ? null
          : const StandardMethodCodec().decodeEnvelope(data));
    }

    setUp(() {
      toNative = [];
      channel = const MethodChannel(GameEngineChannel.channelName);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        toNative.add(call);
        return null;
      });
      bridge = GameEngineChannel(engine: engine, channel: channel);
      bridge.attach();
      addTearDown(bridge.detach);
    });

    test('initialize crosses as a map and applies', () async {
      await callFromNative(GameEngineChannel.methodInitialize, {
        'token': 'native-token',
        'socialMediaId': 'sm-9',
        'language': 'ar',
        'musicEnabled': false,
        'soundEnabled': true,
      });

      expect(prefs.getToken(), 'native-token');
      expect(prefs.getSocialMediaId(), 'sm-9');
      expect(container.read(appLanguageProvider), AppLanguage.arabic);
      expect(container.read(audioServiceProvider).isMusicEnabled, isFalse);
      expect(container.read(audioServiceProvider).isSfxEnabled, isTrue);
    });

    test('connectionState comes back as a stable wire string', () async {
      signalR.status = SignalRStatus.reconnecting;

      final state =
          await callFromNative(GameEngineChannel.methodConnectionState);

      expect(state, 'reconnecting');
    });

    test('state changes are pushed to native', () async {
      signalR.emit(SignalRStatus.connecting);
      signalR.emit(SignalRStatus.connected);
      await Future<void>.delayed(Duration.zero);

      expect(
        toNative
            .where((c) =>
                c.method == GameEngineChannel.methodOnConnectionStateChanged)
            .map((c) => c.arguments)
            .toList(),
        ['connecting', 'connected'],
      );
    });

    test('game flow calls reach the host with their arguments', () async {
      await callFromNative(
        GameEngineChannel.methodCreatePrivateGame,
        {'interestIds': [4, 5]},
      );
      await callFromNative(
        GameEngineChannel.methodJoinPrivateGame,
        {'code': ' ZX9 '},
      );
      await callFromNative(GameEngineChannel.methodJoinRandomGame);

      expect(host.interestIds.single, [4, 5]);
      expect(host.codes.single, 'ZX9', reason: 'trimmed at the boundary');
      expect(host.calls, ['createPrivate', 'joinPrivate', 'random']);
    });

    test('bad arguments come back as a typed error, not a crash', () async {
      await expectLater(
        callFromNative(GameEngineChannel.methodCreatePrivateGame, {
          'interestIds': ['not-a-number'],
        }),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', GameEngineChannel.errorBadArguments)),
      );
      await expectLater(
        callFromNative(GameEngineChannel.methodJoinPrivateGame, {'code': '  '}),
        throwsA(isA<PlatformException>()),
      );
    });

    test('an unknown method is reported as not-implemented', () async {
      // A MissingPluginException thrown from a method-call handler is encoded
      // as the standard empty ("notImplemented") reply, which is what native
      // sees — not a crash, and not a silent success.
      expect(await callFromNative('nonexistent'), isNull);
    });

    test('dispose over the channel tears the bridge down', () async {
      await callFromNative(GameEngineChannel.methodDispose);

      expect(engine.isDisposed, isTrue);
      toNative.clear();
      signalR.emit(SignalRStatus.connected);
      await Future<void>.delayed(Duration.zero);
      expect(toNative, isEmpty, reason: 'no push after detach');
    });

    test('leave over the channel reaches the host once', () async {
      host.active = true;

      await callFromNative(GameEngineChannel.methodLeaveGame);

      expect(host.leaveCalls, 1);
    });

    // B2, at the bridge. The end-to-end proof that a real Back gesture and a
    // real leaveGame both reach this point exactly once lives in
    // game_exit_lifecycle_test.dart, group H.
    group('B2 — onGameExited reaches native', () {
      List<MethodCall> exits() => toNative
          .where((c) => c.method == GameEngineChannel.methodOnGameExited)
          .toList();

      test('an exit is pushed once, with no payload', () async {
        host.active = true;

        host.exitGameRoute();
        await Future<void>.delayed(Duration.zero);

        expect(exits().length, 1);
        expect(exits().single.arguments, isNull,
            reason: 'no game state crosses the boundary');
      });

      test('two exits are two events; nothing is coalesced', () async {
        host.exitGameRoute();
        host.exitGameRoute();
        await Future<void>.delayed(Duration.zero);

        expect(exits().length, 2, reason: 'one per exit, not one per session');
      });

      test('a leaveGame that reaches the exit owner emits exactly once',
          () async {
        host.active = true;

        // Native asks to leave; the game's own exit owner then removes the
        // route and reports. Two steps, one event — leaveGame itself must not
        // emit, or a host-initiated exit would be reported twice.
        await callFromNative(GameEngineChannel.methodLeaveGame);
        host.exitGameRoute();
        await Future<void>.delayed(Duration.zero);

        expect(host.leaveCalls, 1);
        expect(exits().length, 1);
      });

      test('connection changes and config calls emit nothing', () async {
        signalR.emit(SignalRStatus.connected);
        signalR.emit(SignalRStatus.disconnected);
        await callFromNative(GameEngineChannel.methodInitialize, {
          'token': 't',
        });
        await callFromNative(GameEngineChannel.methodConnectionState);
        await Future<void>.delayed(Duration.zero);

        expect(exits(), isEmpty);
      });

      test('disposing the engine does not emit an exit', () async {
        host.active = true;

        await engine.dispose();
        await Future<void>.delayed(Duration.zero);

        expect(exits(), isEmpty,
            reason: 'teardown is not an exit; only an actual route removal is');
      });

      test('an exit after disposal cannot reach native', () async {
        await callFromNative(GameEngineChannel.methodDispose);
        toNative.clear();

        host.exitGameRoute();
        await Future<void>.delayed(Duration.zero);

        expect(toNative, isEmpty);
      });

      test('re-registering a host does not double the event', () async {
        // The engine holds one subscription at a time, so a host registered
        // twice reports one exit, not two.
        engine.registerHost(host);
        engine.registerHost(host);

        host.exitGameRoute();
        await Future<void>.delayed(Duration.zero);

        expect(exits().length, 1);
      });
    });

    // D3. The full boot ordering is proven in game_engine_runtime_test.dart;
    // this is the channel's half of the guarantee.
    group('D3 — onEngineReady', () {
      List<MethodCall> readies() => toNative
          .where((c) => c.method == GameEngineChannel.methodOnEngineReady)
          .toList();

      test('is pushed once, however many times it is asked for', () async {
        bridge.notifyEngineReady();
        bridge.notifyEngineReady();
        bridge.notifyEngineReady();
        await Future<void>.delayed(Duration.zero);

        expect(readies().length, 1);
        expect(readies().single.arguments, isNull);
      });

      test('is never sent before the handler is attached', () async {
        final detached = GameEngineChannel(engine: engine, channel: channel);
        toNative.clear();

        detached.notifyEngineReady();
        await Future<void>.delayed(Duration.zero);

        expect(toNative, isEmpty,
            reason: 'a readiness signal that precedes the handler is the very '
                'race this event exists to remove');
      });

      test('native can invoke a public method straight after it', () async {
        bridge.notifyEngineReady();
        await Future<void>.delayed(Duration.zero);
        expect(readies().length, 1);

        // No retry, no MissingPluginException, no polling.
        await callFromNative(GameEngineChannel.methodInitialize, {
          'token': 'after-ready',
          'language': 'ar',
        });

        expect(prefs.getToken(), 'after-ready');
      });
    });
  });
}
