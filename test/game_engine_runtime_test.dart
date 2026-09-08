import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:game_engine/engine_entry.dart';
import 'package:game_engine/main.dart' as dev_launcher;

// The engine's own lifecycle: what start() builds, and that dispose() undoes
// all of it in the right order.
//
// S8 in TASKS.md is what this closes — `main()` built a container and added a
// lifecycle observer with no disposal path, which is a real leak once a
// native host attaches and detaches repeatedly.

/// Records disposal and lifecycle callbacks, so "the container disposal
/// eventually reaches SignalR" and "the observer was removed" are observable
/// rather than assumed.
class _RecordingSignalRService extends SignalRService {
  bool disposed = false;
  int paused = 0;
  int resumed = 0;
  int connectCalls = 0;

  @override
  Future<void> connectIfNeeded({
    required String url,
    Future<String> Function()? accessTokenFactory,
  }) async {
    connectCalls++;
  }

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async => true;

  @override
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) =>
      () {};

  @override
  void reattachEventHandlers() {}

  @override
  void onAppPaused() => paused++;

  @override
  void onAppResumed() => resumed++;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// The real networkInfoProvider builds an InternetConnection with periodic
/// checks, which leaves pending timers in a widget test.
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

/// A bridge that records attach/detach instead of touching a real channel.
class _RecordingChannel extends GameEngineChannel {
  _RecordingChannel({required super.engine, required super.channel});

  int attaches = 0;
  int detaches = 0;

  @override
  void attach() {
    attaches++;
    super.attach();
  }

  @override
  Future<void> detach() async {
    detaches++;
    await super.detach();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingSignalRService signalR;
  late _RecordingChannel? channel;

  Future<GameEngineRuntime> startRuntime({
    bool attachNativeBridge = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    signalR = _RecordingSignalRService();
    channel = null;
    final runtime = await GameEngineRuntime.start(
      attachNativeBridge: attachNativeBridge,
      overrides: [
        // overrideWith, not overrideWithValue: a value override never runs
        // the provider body, so the real provider's own
        // `ref.onDispose(service.dispose)` (signalr_provider.dart:27-30)
        // would be bypassed and container disposal would prove nothing.
        // This mirrors that contract so the propagation is what is tested.
        signalRServiceProvider.overrideWith((ref) {
          ref.onDispose(signalR.dispose);
          return signalR;
        }),
        networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
        hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
      ],
      channelFactory: (engine) {
        channel = _RecordingChannel(
          engine: engine,
          // A channel name of its own, so this test can never collide with
          // the real one.
          channel: const MethodChannel('test/engine_runtime'),
        );
        return channel!;
      },
    );
    addTearDown(runtime.dispose);
    return runtime;
  }

  // The lifecycle tests below drive real platform lifecycle messages. Left
  // paused, the binding produces no frames and every later widget test finds
  // an empty tree — so the state is always restored.
  tearDown(() => tester_sendLifecycle(AppLifecycleState.resumed));

  group('1-5. start builds the engine', () {
    test('creates a container wired to the engine providers', () async {
      final runtime = await startRuntime();

      expect(runtime.container, isA<ProviderContainer>());
      expect(
        identical(runtime.container.read(signalRServiceProvider), signalR),
        isTrue,
      );
      expect(runtime.container.read(sharedPrefsProvider), isNotNull);
    });

    test('creates and owns the public engine', () async {
      final runtime = await startRuntime();

      expect(runtime.engine, isA<GameEngine>());
      expect(runtime.engine.isDisposed, isFalse);
      expect(runtime.engine.activeConfig, isNull,
          reason: 'the engine boots idle — nothing is invented for the host');
    });

    test('attaches the native bridge', () async {
      final runtime = await startRuntime();

      expect(runtime.isBridgeAttached, isTrue);
      expect(channel!.attaches, 1);
    });

    test('the bridge can be left off', () async {
      final runtime = await startRuntime(attachNativeBridge: false);

      expect(runtime.isBridgeAttached, isFalse);
      expect(channel, isNull);
    });

    test('owns a navigator key of its own', () async {
      final runtime = await startRuntime();

      expect(runtime.navigatorKey, isA<GlobalKey<NavigatorState>>());
      expect(identical(runtime.navigatorKey, AppTheme.navigatorKey), isFalse,
          reason: 'AppTheme.navigatorKey is null in release and unusable');
    });

    test('does not connect the hub or configure anything on its own',
        () async {
      final runtime = await startRuntime();

      expect(runtime.engine.connectionState,
          GameEngineConnectionState.disconnected);
      expect(runtime.engine.pendingConfig, isNull);
    });
  });

  group('5. the engine root', () {
    testWidgets('buildApp renders the engine root on the engine navigator',
        (tester) async {
      final runtime = await startRuntime();

      await tester.pumpWidget(runtime.buildApp());
      await tester.pump();

      expect(find.byType(GameEngineRoot), findsOneWidget);
      expect(find.byType(GameEngineIdlePage), findsOneWidget,
          reason: 'idle until the host asks for a flow');
      expect(runtime.navigatorKey.currentState, isNotNull,
          reason: 'the engine navigator is live and usable for host-driven '
              'navigation');
      expect(find.byType(LoaderOverlay), findsOneWidget,
          reason: 'the connection loader still has its host');
    });

    testWidgets('a custom idle widget replaces the blank surface',
        (tester) async {
      final runtime = await startRuntime();

      await tester.pumpWidget(
        runtime.buildApp(idle: const Scaffold(body: Text('idle-here'))),
      );
      await tester.pump();

      expect(find.text('idle-here'), findsOneWidget);
      expect(find.byType(GameEngineIdlePage), findsNothing);
    });

    testWidgets('the root does not carry the debug launcher', (tester) async {
      final runtime = await startRuntime();

      await tester.pumpWidget(runtime.buildApp());
      await tester.pump();

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(identical(app.navigatorKey, runtime.navigatorKey), isTrue);
      expect(app.navigatorObservers, isEmpty,
          reason: 'homeLauncherRouteObserver belongs to the dev launcher');
    });
  });

  group('6-10. dispose undoes start, in order', () {
    test('detaches the bridge', () async {
      final runtime = await startRuntime();

      await runtime.dispose();

      expect(channel!.detaches, 1);
      expect(runtime.isBridgeAttached, isFalse);
    });

    test('disposes the engine', () async {
      final runtime = await startRuntime();

      await runtime.dispose();

      expect(runtime.engine.isDisposed, isTrue);
      expect(runtime.engine.connectHub, throwsStateError);
    });

    test('removes the lifecycle observer', () async {
      final runtime = await startRuntime();
      // Proven behaviourally: a lifecycle change reaches the service before
      // dispose and not after.
      tester_sendLifecycle(AppLifecycleState.paused);
      expect(signalR.paused, 1, reason: 'sanity: the observer was installed');

      await runtime.dispose();
      tester_sendLifecycle(AppLifecycleState.paused);

      expect(signalR.paused, 1, reason: 'no longer observing');
    });

    test('disposes the container, which disposes SignalR', () async {
      final runtime = await startRuntime();

      await runtime.dispose();

      expect(signalR.disposed, isTrue,
          reason: 'the hub goes when the engine goes — and only then');
      expect(
        () => runtime.container.read(signalRServiceProvider),
        throwsStateError,
        reason: 'the container itself is disposed',
      );
    });

    test('the hub is NOT dropped merely because a game screen closed',
        () async {
      final runtime = await startRuntime();

      // Leaving a game goes nowhere near the runtime's teardown.
      await runtime.engine.leaveGame();

      expect(signalR.disposed, isFalse);
      expect(runtime.isDisposed, isFalse);
    });
  });

  group('11-12. dispose is idempotent and leaks nothing', () {
    test('a second dispose does nothing', () async {
      final runtime = await startRuntime();

      await runtime.dispose();
      await runtime.dispose();
      await runtime.dispose();

      expect(runtime.isDisposed, isTrue);
      expect(channel!.detaches, 1, reason: 'detached once, not three times');
    });

    test('repeated start/dispose leaves no observer behind', () async {
      for (var i = 0; i < 3; i++) {
        final runtime = await startRuntime();
        final service = signalR;
        await runtime.dispose();

        tester_sendLifecycle(AppLifecycleState.paused);
        expect(service.paused, 0,
            reason: 'cycle ${i + 1} left an observer behind');
        expect(service.disposed, isTrue);
      }
    });
  });

  // B1. Native's `dispose` used to reach GameEngine.dispose() alone, which
  // leaves the container — and therefore the lifecycle observer and SignalR —
  // alive behind a bridge that has just gone deaf. It must reach the runtime's
  // own teardown instead, and reach all of it.
  group('B1. native dispose performs the full runtime teardown', () {
    Future<Object?> callFromNative(String method, [Object? args]) {
      return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'test/engine_runtime',
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall(method, args)),
        null,
      ).then((data) => data == null
          ? null
          : const StandardMethodCodec().decodeEnvelope(data));
    }

    test('it disposes the engine, the container and SignalR', () async {
      final runtime = await startRuntime();

      await callFromNative(GameEngineChannel.methodDispose);

      expect(runtime.isDisposed, isTrue,
          reason: 'the runtime itself, not just the public engine');
      expect(runtime.engine.isDisposed, isTrue);
      expect(signalR.disposed, isTrue,
          reason: 'through signalRServiceProvider.onDispose, the one path');
      expect(
        () => runtime.container.read(signalRServiceProvider),
        throwsStateError,
        reason: 'the container is disposed',
      );
    });

    test('it detaches the bridge, exactly once', () async {
      final runtime = await startRuntime();

      await callFromNative(GameEngineChannel.methodDispose);

      expect(channel!.detaches, 1,
          reason: 'the runtime detaches it; the bridge does not also do its '
              'own partial teardown');
      expect(runtime.isBridgeAttached, isFalse);
    });

    test('it removes the lifecycle observer', () async {
      await startRuntime();
      tester_sendLifecycle(AppLifecycleState.paused);
      expect(signalR.paused, 1, reason: 'sanity: the observer was installed');

      await callFromNative(GameEngineChannel.methodDispose);
      tester_sendLifecycle(AppLifecycleState.paused);

      expect(signalR.paused, 1, reason: 'nothing left registered');
    });

    test('a second native dispose is a no-op, not a crash', () async {
      final runtime = await startRuntime();

      await callFromNative(GameEngineChannel.methodDispose);
      await callFromNative(GameEngineChannel.methodDispose);
      await callFromNative(GameEngineChannel.methodDispose);

      expect(runtime.isDisposed, isTrue);
      expect(channel!.detaches, 1);
      expect(signalR.disposed, isTrue);
    });

    test('native dispose then a direct runtime dispose is still safe',
        () async {
      final runtime = await startRuntime();

      await callFromNative(GameEngineChannel.methodDispose);
      await runtime.dispose();

      expect(channel!.detaches, 1);
    });

    test('a public command after native dispose is refused, not served',
        () async {
      await startRuntime();
      await callFromNative(GameEngineChannel.methodDispose);

      // The handler is gone, so this is the standard not-implemented reply —
      // native's own signal that the engine is no longer there.
      expect(await callFromNative(GameEngineChannel.methodConnectHub), isNull);
    });

    test('a bridge with no runtime bound still tears down what it owns',
        () async {
      // The fallback path: a GameEngineChannel constructed on its own is not
      // silently unable to dispose.
      final runtime = await startRuntime(attachNativeBridge: false);
      final standalone = GameEngineChannel(
        engine: runtime.engine,
        channel: const MethodChannel('test/engine_runtime_standalone'),
      );
      standalone.attach();

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'test/engine_runtime_standalone',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall(GameEngineChannel.methodDispose),
        ),
        null,
      );

      expect(runtime.engine.isDisposed, isTrue);
      expect(signalR.disposed, isFalse,
          reason: 'no runtime was bound, so no container disposal is claimed');
    });
  });

  // D3. Native must be told when it may start calling, rather than retrying a
  // MissingPluginException or polling connectionState.
  group('D3. onEngineReady closes the startup race', () {
    late List<MethodCall> toNative;
    const publicChannel = MethodChannel(GameEngineChannel.channelName);

    List<MethodCall> readies() => toNative
        .where((c) => c.method == GameEngineChannel.methodOnEngineReady)
        .toList();

    Future<Object?> callFromNative(String method, [Object? args]) {
      return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        GameEngineChannel.channelName,
        const StandardMethodCodec()
            .encodeMethodCall(MethodCall(method, args)),
        null,
      ).then((data) => data == null
          ? null
          : const StandardMethodCodec().decodeEnvelope(data));
    }

    // The real entry point, on the real channel name, with the real bridge.
    Future<GameEngineRuntime> boot() async {
      SharedPreferences.setMockInitialValues({});
      signalR = _RecordingSignalRService();
      final runtime = await startGameEngine(
        overrides: [
          signalRServiceProvider.overrideWith((ref) {
            ref.onDispose(signalR.dispose);
            return signalR;
          }),
          networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
          hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
        ],
      );
      addTearDown(runtime.dispose);
      return runtime;
    }

    setUp(() {
      toNative = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(publicChannel, (call) async {
        toNative.add(call);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(publicChannel, null);
      });
    });

    testWidgets('it is emitted exactly once, and only after the first frame',
        (tester) async {
      final runtime = await boot();

      expect(readies(), isEmpty,
          reason: 'the boot sequence is not finished until the engine root has '
              'rendered and the navigator exists');

      await tester.pumpWidget(runtime.buildApp());
      await tester.pump();

      expect(readies().length, 1);
      expect(readies().single.arguments, isNull);
    });

    testWidgets('further frames do not repeat it', (tester) async {
      final runtime = await boot();
      await tester.pumpWidget(runtime.buildApp());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      runtime.markReady();
      runtime.markReady();
      await tester.pump();

      expect(readies().length, 1);
    });

    testWidgets('the handler is attached before it is sent — native can call '
        'initialize immediately', (tester) async {
      final runtime = await boot();
      await tester.pumpWidget(runtime.buildApp());
      await tester.pump();
      expect(readies().length, 1);

      // No retry loop, no MissingPluginException, no connectionState polling.
      await callFromNative(GameEngineChannel.methodInitialize, {
        'token': 'ready-token',
        'language': 'ar',
        'musicEnabled': false,
      });

      expect(runtime.engine.activeConfig?.token, 'ready-token');
      expect(runtime.engine.activeConfig?.language, AppLanguage.arabic);
      expect(runtime.container.read(sharedPrefsProvider).getToken(),
          'ready-token');
    });

    testWidgets('it does not connect the hub or configure anything by itself',
        (tester) async {
      final runtime = await boot();
      await tester.pumpWidget(runtime.buildApp());
      await tester.pump();

      expect(readies().length, 1);
      expect(runtime.engine.activeConfig, isNull,
          reason: 'initialize stays the host\'s call');
      expect(signalR.connectCalls, 0,
          reason: 'connectHub stays the host\'s call too');
    });

    testWidgets('a runtime with no bridge has nothing to tell', (tester) async {
      final runtime = await startRuntime(attachNativeBridge: false);

      runtime.markReady();
      await tester.pump();

      expect(readies(), isEmpty);
      expect(runtime.isBridgeAttached, isFalse);
    });

    // Not a testWidgets: nothing is pumped, so no frame is produced and the
    // post-frame signal never fires on its own. That is the point — the only
    // thing that could send here is the explicit markReady, and it must not.
    test('markReady after disposal sends nothing', () async {
      final runtime = await boot();

      await runtime.dispose();
      runtime.markReady();
      await Future<void>.delayed(Duration.zero);

      expect(toNative, isEmpty);
    });
  });

  group('13. the production entry point', () {
    test('boots the runtime and registers the game-flow host', () async {
      SharedPreferences.setMockInitialValues({});
      final recording = _RecordingSignalRService();
      final runtime = await startGameEngine(
        attachNativeBridge: false,
        overrides: [
          signalRServiceProvider.overrideWith((ref) {
            ref.onDispose(recording.dispose);
            return recording;
          }),
          networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
          hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
        ],
      );
      addTearDown(runtime.dispose);

      expect(runtime.engine, isA<GameEngine>());
      expect(runtime.engine.isGameActive, isFalse,
          reason: 'a host was registered — this reads through it');
      expect(runtime.engine.activeConfig, isNull,
          reason: 'idle: no token, language or audio value invented');
    });

    testWidgets('its root is the engine root, not the dev launcher',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final runtime = await startGameEngine(
        attachNativeBridge: false,
        overrides: [
          signalRServiceProvider
              .overrideWithValue(_RecordingSignalRService()),
          networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
          hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
        ],
      );
      addTearDown(runtime.dispose);

      await tester.pumpWidget(runtime.buildApp());
      await tester.pump();

      expect(find.byType(GameEngineRoot), findsOneWidget);
      expect(find.byType(GameEngineIdlePage), findsOneWidget);
    });
  });

  group('14. the development launcher is untouched', () {
    test('main() still exists and is a separate entry point', () {
      expect(dev_launcher.main, isA<Function>());
      expect(identical(dev_launcher.main, gameEngineMain), isFalse,
          reason: 'two distinct entry points; the host targets the engine one');
    });

    test('AppRoot is still the launcher root, and is not the engine root',
        () {
      // Type-level rather than pumped: AppRoot builds HomeLauncherPage, which
      // pulls the whole auth/network stack in. What matters here is that the
      // launcher still has its own root and did not get routed through the
      // engine's — lib/main.dart is untouched by this task.
      expect(const dev_launcher.AppRoot(), isA<ConsumerWidget>());
      expect(const dev_launcher.AppRoot(), isNot(isA<GameEngineRoot>()));
    });
  });
}

// Drives the platform lifecycle message the real observer listens to.
void tester_sendLifecycle(AppLifecycleState state) {
  TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
}
