import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signalr_core/signalr_core.dart';

// Background -> foreground during an active game.
//
// A socket can die while the app is away and the hub still reports connected:
// signalr_core only notices through its own server timeout, whose timer may
// not have run in the background. `onAppResumed` used to act only when the hub
// was not live, so it did nothing here — no recovery, no CheckPlayerGame.
//
// On resume the service now asks whether the server has spoken within the
// hub's own server timeout. If not, the connection is replaced through the
// existing reconnect path, which announces recovery once:
//
//   _notifyRecovered() -> ConnectionRecoveryController
//     -> GameController.onRecovered() -> CheckPlayerGame
//
// Real SignalRService, ConnectionRecoveryController, PlayGameHubBindings and
// GameController; only the HubConnection is a fake, and the service's clock
// is a test clock so "the app was away" is deterministic.

const _localId = '47';
const _opponentId = '211403';
const _url = 'ws://fake.test/hub';
const _serverTimeout = Duration(milliseconds: DEFAULT_TIMEOUT_IN_MS);

class _FakeHub extends HubConnection {
  _FakeHub({this.startGate}) : super(protocol: JsonHubProtocol());

  /// When set, the hub reports connected at once but start() only returns
  /// when this completes — a connect() still in flight.
  final Completer<void>? startGate;

  final invoked = <String>[];
  int stopCalls = 0;

  final _handlers = <String, MethodInvocationFunc>{};
  final _reconnecting = <ReconnectingCallback>[];
  final _reconnected = <ReconnectedCallback>[];
  HubConnectionState _state = HubConnectionState.disconnected;

  @override
  HubConnectionState? get state => _state;

  @override
  String? get connectionId => 'fake';

  @override
  Future<void>? start() async {
    _state = HubConnectionState.connected;
    final gate = startGate;
    if (gate != null) {
      await gate.future;
    }
  }

  @override
  Future<void> stop() {
    stopCalls++;
    _state = HubConnectionState.disconnected;
    return Future<void>.value();
  }

  @override
  Future<dynamic> invoke(String methodName, {List<dynamic>? args}) async {
    invoked.add(methodName);
    return null;
  }

  @override
  void on(String methodName, MethodInvocationFunc newMethod) =>
      _handlers[methodName] = newMethod;

  @override
  void off(String methodName, {MethodInvocationFunc? method}) =>
      _handlers.remove(methodName);

  @override
  void onclose(ClosedCallback callback) {}

  @override
  void onreconnecting(ReconnectingCallback callback) =>
      _reconnecting.add(callback);

  @override
  void onreconnected(ReconnectedCallback callback) =>
      _reconnected.add(callback);

  /// A hub event from the server, through whatever the service registered.
  void serverSends(String event) => _handlers[event]?.call(null);

  /// The transport dropped and signalr_core began reconnecting.
  void dropToReconnecting() {
    _state = HubConnectionState.reconnecting;
    for (final callback in List.of(_reconnecting)) {
      callback(null);
    }
  }

  /// signalr_core's own reconnect succeeded.
  void reconnectedByLibrary() {
    _state = HubConnectionState.connected;
    for (final callback in List.of(_reconnected)) {
      callback('fake');
    }
  }
}

/// A game already in a round (status 3, type 1 = WDYK).
Map<String, dynamic> _activeRound() => {
      'id': 'g1',
      'status': 3,
      'type': 1,
      'mode': 1,
      'groupId': 'grp',
      'currentTurn': _localId,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
      'currentQuestion': {
        'id': 1,
        'text': 'q',
        'textEn': 'q',
        'questionNumber': 1,
        'answers': [
          {'id': 10, 'text': 'a', 'textEn': 'a'},
        ],
      },
    };

class _Engine {
  _Engine(this.container, this.service, this.hubs);

  final ProviderContainer container;
  final SignalRService service;
  final List<_FakeHub> hubs;

  DateTime now = DateTime(2026, 9, 13, 12);

  /// Hop 1: `_notifyRecovered()` put an event on `recoveredStream`.
  int announced = 0;

  /// Hop 2: ConnectionRecoveryController ran its registered callbacks.
  int controllerRuns = 0;

  GameController get controller =>
      container.read(gameControllerProvider.notifier);

  GameSessionState get session => container.read(gameControllerProvider);

  Future<void> connect() =>
      service.connect(url: _url, accessTokenFactory: () async => 'token');

  void enterRound() => controller.applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _activeRound(),
      );

  void away(Duration duration) => now = now.add(duration);

  /// Hop 3, across every hub this engine has built.
  int get checks => [for (final hub in hubs) ...hub.invoked]
      .where((m) => m == PlayGameHubEvents.checkPlayerGame)
      .length;
}

void main() {
  late SharedPrefsService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    prefs = await SharedPrefsService.init();
  });

  /// [gate] holds start() open on the hub built at [gateIndex].
  _Engine buildEngine({int? gateIndex, Completer<void>? gate}) {
    final hubs = <_FakeHub>[];
    late final _Engine engine;
    final service = SignalRService(
      hubConnectionFactory: (url, tokenFactory) {
        final hub = _FakeHub(startGate: hubs.length == gateIndex ? gate : null);
        hubs.add(hub);
        return hub;
      },
      clock: () => engine.now,
    );
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(service),
      ],
    );
    addTearDown(service.dispose);
    addTearDown(container.dispose);
    final session = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(session.close);
    final status = container.listen(signalRStatusProvider, (_, __) {});
    addTearDown(status.close);

    engine = _Engine(container, service, hubs);
    final recovered = service.recoveredStream.listen((_) => engine.announced++);
    addTearDown(recovered.cancel);
    final unregister = container
        .read(connectionRecoveryControllerProvider)
        .onRecovered(() {
      engine.controllerRuns++;
    });
    addTearDown(unregister);
    return engine;
  }

  /// In a round, on a connected hub, with the entry connect's own recovery
  /// already settled.
  Future<_Engine> inActiveGame({int? gateIndex, Completer<void>? gate}) async {
    final e = buildEngine(gateIndex: gateIndex, gate: gate);
    e.enterRound();
    await e.connect();
    await pumpEventQueue();
    expect(e.session.phase, GamePhase.wdyk, reason: 'sanity: in a round');
    expect(e.service.checkConnectionStatus(), SignalRStatus.connected);
    return e;
  }

  group('1. foreground on a healthy connection changes nothing', () {
    test('the server spoke moments ago: no reconnect, no CheckPlayerGame',
        () async {
      final e = await inActiveGame();
      final announced = e.announced;
      final checks = e.checks;

      e.away(const Duration(seconds: 10));
      e.service.onAppResumed();
      await pumpEventQueue();

      expect(e.hubs, hasLength(1));
      expect(e.hubs.single.stopCalls, 0);
      expect(e.announced, announced);
      expect(e.checks, checks);
      expect(e.service.checkConnectionStatus(), SignalRStatus.connected);
    });

    test('a long-lived connection the server keeps talking on is left alone',
        () async {
      final e = await inActiveGame();
      final announced = e.announced;
      final runs = e.controllerRuns;
      final checks = e.checks;

      e.away(const Duration(minutes: 10));
      e.hubs.single.serverSends(PlayGameHubEvents.playerEmoted);
      e.away(const Duration(seconds: 5));
      e.service.onAppResumed();
      await pumpEventQueue();

      expect(e.hubs, hasLength(1));
      expect(e.hubs.single.stopCalls, 0);
      expect(e.announced, announced);
      expect(e.controllerRuns, runs);
      expect(e.checks, checks);
    });

    test('silence shorter than the hub server timeout is not treated as dead',
        () async {
      final e = await inActiveGame();
      final checks = e.checks;

      e.away(_serverTimeout - const Duration(seconds: 1));
      e.service.onAppResumed();
      await pumpEventQueue();

      expect(e.hubs, hasLength(1));
      expect(e.hubs.single.stopCalls, 0);
      expect(e.checks, checks);
    });
  });

  group('2. foreground on a connection that died while away', () {
    test('status still says connected, yet the dead hub is replaced and the '
        'round resynchronised', () async {
      final e = await inActiveGame();
      final announced = e.announced;
      final runs = e.controllerRuns;
      final checks = e.checks;

      e.away(const Duration(minutes: 5));
      expect(e.service.isConnected, isTrue,
          reason: 'sanity: the hub still reports connected');
      expect(e.service.checkConnectionStatus(), SignalRStatus.connected,
          reason: 'sanity: no popup, nothing else will act on its own');

      e.service.onAppResumed();
      await pumpEventQueue();

      expect(e.hubs.first.stopCalls, 1, reason: 'the dead hub was torn down');
      expect(e.hubs, hasLength(2), reason: 'and a fresh one connected');
      expect(e.service.checkConnectionStatus(), SignalRStatus.connected);
      expect(e.announced, announced + 1,
          reason: 'hop 1: _notifyRecovered() fired');
      expect(e.controllerRuns, runs + 1,
          reason: 'hop 2: ConnectionRecoveryController ran');
      expect(e.hubs.last.invoked, [PlayGameHubEvents.checkPlayerGame],
          reason: 'hop 3: GameController.onRecovered sent CheckPlayerGame');
      expect(e.checks, checks + 1);
      expect(e.session.phase, GamePhase.wdyk);
    });
  });

  group('3. CheckPlayerGame is sent exactly once per recovery', () {
    test('two resume callbacks back to back replace the hub once', () async {
      final e = await inActiveGame();
      final announced = e.announced;
      final checks = e.checks;

      e.away(const Duration(minutes: 5));
      e.service.onAppResumed();
      e.service.onAppResumed();
      await pumpEventQueue();

      expect(e.hubs, hasLength(2));
      expect(e.announced, announced + 1);
      expect(e.checks, checks + 1);
    });

    test('a resume right after the recovery does not recover again', () async {
      final e = await inActiveGame();
      final checks = e.checks;

      e.away(const Duration(minutes: 5));
      e.service.onAppResumed();
      await pumpEventQueue();
      e.away(const Duration(seconds: 2));
      e.service.onAppResumed();
      await pumpEventQueue();

      expect(e.hubs, hasLength(2));
      expect(e.checks, checks + 1);
    });
  });

  group('4. a reconnect already in progress is not duplicated', () {
    test("signalr_core's own reconnect is left to finish and announces once",
        () async {
      final e = await inActiveGame();
      final announced = e.announced;
      final checks = e.checks;

      e.away(const Duration(minutes: 5));
      e.hubs.single.dropToReconnecting();
      e.service.onAppResumed();
      await pumpEventQueue();

      expect(e.hubs, hasLength(1), reason: 'no second connection');
      expect(e.hubs.single.stopCalls, 0);
      expect(e.checks, checks);

      e.hubs.single.reconnectedByLibrary();
      await pumpEventQueue();
      e.service.onAppResumed();
      await pumpEventQueue();

      expect(e.hubs, hasLength(1));
      expect(e.announced, announced + 1);
      expect(e.checks, checks + 1);
      expect(e.service.checkConnectionStatus(), SignalRStatus.connected);
    });

    test('a replacement connect still in flight is not started twice',
        () async {
      final gate = Completer<void>();
      final e = await inActiveGame(gateIndex: 1, gate: gate);
      final announced = e.announced;
      final checks = e.checks;

      e.hubs.single.dropToReconnecting();
      unawaited(e.service.recoverConnection());
      await pumpEventQueue();
      expect(e.hubs, hasLength(2), reason: 'sanity: a connect is in flight');

      e.away(const Duration(minutes: 5));
      e.service.onAppResumed();
      await pumpEventQueue();
      expect(e.hubs, hasLength(2), reason: 'resume did not start another');
      expect(e.hubs.last.stopCalls, 0);

      gate.complete();
      await pumpEventQueue();

      expect(e.hubs, hasLength(2));
      expect(e.announced, announced + 1);
      expect(e.checks, checks + 1);
      expect(e.hubs.last.invoked, [PlayGameHubEvents.checkPlayerGame]);
    });
  });

  group('5. the Reconnect button is unchanged', () {
    testWidgets('popup -> Reconnect -> popup gone -> CheckPlayerGame once',
        (tester) async {
      final e = buildEngine();
      e.enterRound();
      await e.connect();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: e.container,
          child: MaterialApp(
            builder: (context, child) => LoaderOverlay(child: child!),
            home: const Scaffold(body: Text('round')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final announced = e.announced;
      final checks = e.checks;

      e.hubs.single.dropToReconnecting();
      await tester.pump();
      await tester.pump();
      expect(find.byType(ConnectionLoader), findsOneWidget);

      await tester.pump(const Duration(seconds: 6));
      await tester.tap(
        find.widgetWithText(
          GameButton,
          AppStrings.forLanguage(AppLanguage.english).reconnect,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byType(ConnectionLoader), findsNothing);
      expect(e.hubs, hasLength(2));
      expect(e.announced, announced + 1);
      expect(e.checks, checks + 1);
      expect(e.hubs.last.invoked, [PlayGameHubEvents.checkPlayerGame]);
    });
  });
}
