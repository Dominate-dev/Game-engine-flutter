import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signalr_core/signalr_core.dart';

// Every successful recovery resynchronises the game:
//
//   _notifyRecovered() -> ConnectionRecoveryController
//     -> GameController.onRecovered() -> CheckPlayerGame
//
// The service reaches `connected` three ways. `start()` succeeding and
// `onreconnected` both announced recovery; the third, `_skipIfAlreadyConnected`
// correcting a stale status on a hub that is already up, did not. The
// Reconnect button took that third way whenever the popup was showing over a
// live hub: the status was corrected, the popup came down, and the round was
// never resynchronised.
//
// Each test checks every hop separately — the recoveredStream announcement,
// the ConnectionRecoveryController run, and CheckPlayerGame on the wire — so
// "the status became connected" can never pass for "the game was synced".
//
// Everything runs the real SignalRService, ConnectionRecoveryController,
// PlayGameHubBindings and GameController. Only the HubConnection is a fake,
// injected through the service's existing factory seam.

const _localId = '47';
const _opponentId = '211403';
const _url = 'ws://fake.test/hub';

/// In-memory hub. Records what the service invokes on it, and can drop, come
/// back without telling anyone, hold stop() forever, or report connected
/// while start() is still pending.
class _FakeHub extends HubConnection {
  _FakeHub({this.holdStop = false, this.startGate})
      : super(protocol: JsonHubProtocol());

  /// signalr_core 1.1.2 can leave stop() pending forever (see N6).
  final bool holdStop;

  /// When set, the hub reports connected at once but start() only returns
  /// when this completes — a connect() still in flight over a live hub.
  final Completer<void>? startGate;

  final invoked = <String>[];
  int stopCalls = 0;
  int onCalls = 0;

  final _closed = <ClosedCallback>[];
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
    if (holdStop) {
      return Completer<void>().future;
    }
    _state = HubConnectionState.disconnected;
    return Future<void>.value();
  }

  @override
  Future<dynamic> invoke(String methodName, {List<dynamic>? args}) async {
    invoked.add(methodName);
    return null;
  }

  @override
  void on(String methodName, MethodInvocationFunc newMethod) {
    onCalls++;
  }

  @override
  void off(String methodName, {MethodInvocationFunc? method}) {}

  @override
  void onclose(ClosedCallback callback) => _closed.add(callback);

  @override
  void onreconnecting(ReconnectingCallback callback) =>
      _reconnecting.add(callback);

  @override
  void onreconnected(ReconnectedCallback callback) =>
      _reconnected.add(callback);

  /// The transport dropped and signalr_core began reconnecting.
  void dropToReconnecting() {
    _state = HubConnectionState.reconnecting;
    for (final callback in List.of(_reconnecting)) {
      callback(null);
    }
  }

  /// The hub is up again, but `onreconnected` never reached the service.
  /// This is the precondition `_skipIfAlreadyConnected`'s self-heal branch
  /// exists for: `isConnected` true, the reported status not `connected`.
  void comeBackSilently() => _state = HubConnectionState.connected;

  int count(String method) => invoked.where((m) => m == method).length;
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

  /// Hop 1: `_notifyRecovered()` put an event on `recoveredStream`.
  int announced = 0;

  /// Hop 2: ConnectionRecoveryController ran its registered callbacks —
  /// counted by a probe registered after GameController's own.
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

  List<String> get allInvoked => [for (final hub in hubs) ...hub.invoked];

  /// Hop 3, across every hub this engine has built.
  int get checks => allInvoked
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

  /// The real providers with only the HubConnection faked. [holdStopOn] makes
  /// the hub built at that index hold stop() forever; [gateFirstStart] holds
  /// the first hub's start() open while it already reports connected.
  _Engine buildEngine({int? holdStopOn, Completer<void>? gateFirstStart}) {
    final hubs = <_FakeHub>[];
    final service = SignalRService(
      hubConnectionFactory: (url, tokenFactory) {
        final hub = _FakeHub(
          holdStop: hubs.length == holdStopOn,
          startGate: hubs.isEmpty ? gateFirstStart : null,
        );
        hubs.add(hub);
        return hub;
      },
    );
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(service),
      ],
    );
    // LIFO: the container is disposed before the service it depends on.
    addTearDown(service.dispose);
    addTearDown(container.dispose);
    // Held open, as the engine's own container holds it: the controller
    // outlives any one screen, so its recovery registration stays live.
    final session = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(session.close);
    final status = container.listen(signalRStatusProvider, (_, __) {});
    addTearDown(status.close);

    final engine = _Engine(container, service, hubs);
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

  Future<void> mountLoader(WidgetTester tester, _Engine engine) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: engine.container,
        child: MaterialApp(
          builder: (context, child) => LoaderOverlay(child: child!),
          home: const Scaffold(body: Text('round')),
        ),
      ),
    );
    // The real status stream is an async broadcast controller, so a status
    // change reaches the loader one frame later than a synchronous fake would.
    await tester.pump();
    await tester.pump();
  }

  Finder popup() => find.byType(ConnectionLoader);

  Finder reconnectButton() => find.widgetWithText(
        GameButton,
        AppStrings.forLanguage(AppLanguage.english).reconnect,
      );

  /// ConnectionLoader only offers Reconnect after its existing retryAfter.
  Future<void> revealReconnect(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 6));

  group('1. a genuinely disconnected hub that Reconnect brings back', () {
    test('recovery is announced, the controller runs, and CheckPlayerGame '
        'resynchronises the round', () async {
      final e = buildEngine();
      e.enterRound();
      expect(e.session.phase, GamePhase.wdyk, reason: 'sanity: in a round');
      await e.connect();
      await pumpEventQueue();

      e.hubs.single.dropToReconnecting();
      expect(e.service.isConnected, isFalse);
      expect(e.service.checkConnectionStatus(), SignalRStatus.reconnecting,
          reason: 'sanity: the popup is up');
      final announced = e.announced;
      final runs = e.controllerRuns;

      await e.service.recoverConnection();
      await pumpEventQueue();

      expect(e.service.checkConnectionStatus(), SignalRStatus.connected);
      expect(e.hubs, hasLength(2), reason: 'the dead hub was replaced');
      expect(e.announced, announced + 1,
          reason: 'hop 1: _notifyRecovered() fired');
      expect(e.controllerRuns, runs + 1,
          reason: 'hop 2: ConnectionRecoveryController ran');
      expect(e.hubs.last.invoked, [PlayGameHubEvents.checkPlayerGame],
          reason: 'hop 3: GameController.onRecovered sent CheckPlayerGame');
      expect(e.allInvoked, isNot(contains(PlayGameHubEvents.joinRandomGame)),
          reason: 'a game in progress is resynchronised, not re-joined');
      expect(e.session.phase, GamePhase.wdyk);
    });
  });

  group('2. a live hub whose stale status _skipIfAlreadyConnected corrects', () {
    test('Reconnect: status corrected, recovery announced, controller run, '
        'CheckPlayerGame sent', () async {
      final e = buildEngine();
      e.enterRound();
      await e.connect();
      await pumpEventQueue();
      final hub = e.hubs.single;
      final onBefore = hub.onCalls;

      hub
        ..dropToReconnecting()
        ..comeBackSilently();
      expect(e.service.isConnected, isTrue, reason: 'sanity: the hub is up');
      expect(e.service.checkConnectionStatus(), SignalRStatus.reconnecting,
          reason: 'sanity: yet the popup is showing');
      final announced = e.announced;
      final runs = e.controllerRuns;
      final checks = e.checks;

      await e.service.recoverConnection();
      await pumpEventQueue();

      expect(e.service.checkConnectionStatus(), SignalRStatus.connected,
          reason: 'the popup comes down');
      expect(e.announced, announced + 1,
          reason: 'hop 1: _notifyRecovered() fired — the step that was missing');
      expect(e.controllerRuns, runs + 1,
          reason: 'hop 2: ConnectionRecoveryController ran');
      expect(e.checks, checks + 1,
          reason: 'hop 3: CheckPlayerGame went out — the resync that never did');
      expect(hub.onCalls, greaterThan(onBefore),
          reason: 'handlers re-attached before the announcement, as on any '
              'real reconnect');
      expect(e.hubs, hasLength(1), reason: 'a live hub is not rebuilt');
      expect(hub.stopCalls, 0, reason: 'nor torn down');
    });

    test('every caller that corrects a stale status resynchronises, not only '
        'the button', () async {
      // connectIfNeeded() is what the backoff timer's reconnect() reaches, and
      // what any other entry path calls.
      final e = buildEngine();
      e.enterRound();
      await e.connect();
      await pumpEventQueue();
      e.hubs.single
        ..dropToReconnecting()
        ..comeBackSilently();
      final announced = e.announced;
      final runs = e.controllerRuns;
      final checks = e.checks;

      await e.service.connectIfNeeded(
        url: _url,
        accessTokenFactory: () async => 'token',
      );
      await pumpEventQueue();

      expect(e.service.checkConnectionStatus(), SignalRStatus.connected);
      expect(e.announced, announced + 1);
      expect(e.controllerRuns, runs + 1);
      expect(e.checks, checks + 1);
    });

    test('a correction while connect() is still in flight is announced once, '
        'by connect()', () async {
      final gate = Completer<void>();
      final e = buildEngine(gateFirstStart: gate);
      e.enterRound();
      final connecting = e.connect();
      await pumpEventQueue();
      expect(e.service.isConnected, isTrue,
          reason: 'sanity: hub up, start() still pending');
      expect(e.service.checkConnectionStatus(), SignalRStatus.connecting);

      await e.service.connectIfNeeded(
        url: _url,
        accessTokenFactory: () async => 'token',
      );
      await pumpEventQueue();
      expect(e.announced, 0, reason: 'the in-flight connect() owns this one');

      gate.complete();
      await connecting;
      await pumpEventQueue();

      expect(e.announced, 1, reason: 'one connection, one recovery');
      expect(e.checks, 1, reason: 'and one resync — not two');
    });

    test('a live hub already reporting connected is left alone', () async {
      final e = buildEngine();
      e.enterRound();
      await e.connect();
      await pumpEventQueue();
      final hub = e.hubs.single;
      final before = List.of(hub.invoked);
      final announced = e.announced;

      await e.service.recoverConnection();
      await pumpEventQueue();

      expect(e.announced, announced, reason: 'nothing recovered');
      expect(hub.invoked, before, reason: 'so no redundant resync');
      expect(hub.stopCalls, 0);
      expect(e.hubs, hasLength(1));
    });

    testWidgets('the ticket flow: popup -> Reconnect -> popup gone -> '
        'CheckPlayerGame', (tester) async {
      final e = buildEngine();
      e.enterRound();
      await e.connect();
      await mountLoader(tester, e);
      expect(popup(), findsNothing, reason: 'sanity: connected, no popup');

      e.hubs.single
        ..dropToReconnecting()
        ..comeBackSilently();
      await tester.pump();
      await tester.pump();
      expect(popup(), findsOneWidget,
          reason: 'the popup is up over a hub that is actually live');

      await revealReconnect(tester);
      final announced = e.announced;
      final checks = e.checks;
      await tester.tap(reconnectButton());
      await tester.pump();
      await tester.pump();

      expect(popup(), findsNothing, reason: 'the popup comes down');
      expect(e.announced, announced + 1, reason: 'recovery announced');
      expect(e.checks, checks + 1,
          reason: 'and the round is resynchronised, not just uncovered');
    });
  });

  group('3. Reconnect cannot be held forever by stop()', () {
    test('recoverConnection completes once the stale hub is abandoned, and '
        'the round resynchronises on the fresh one', () {
      fakeAsync((async) {
        final e = buildEngine(holdStopOn: 0);
        e.enterRound();
        unawaited(e.connect());
        async.flushMicrotasks();
        expect(e.service.isConnected, isTrue, reason: 'sanity');

        e.hubs.single.dropToReconnecting();
        final announced = e.announced;
        var done = false;
        unawaited(
          e.service.recoverConnection().whenComplete(() => done = true),
        );
        async.flushMicrotasks();
        expect(done, isFalse, reason: "held on the old hub's stop()");

        async.elapse(SignalRService.stopTimeout);

        expect(done, isTrue, reason: 'stop() is bounded, so Reconnect returns');
        expect(e.hubs, hasLength(2));
        expect(e.service.checkConnectionStatus(), SignalRStatus.connected);
        expect(e.announced, announced + 1);
        expect(e.hubs.last.invoked, [PlayGameHubEvents.checkPlayerGame]);
      });
    });

    testWidgets('the popup does not stay up behind a stop() that never '
        'returns', (tester) async {
      final e = buildEngine(holdStopOn: 0);
      e.enterRound();
      await e.connect();
      await mountLoader(tester, e);

      e.hubs.single.dropToReconnecting();
      await tester.pump();
      await tester.pump();
      await revealReconnect(tester);
      await tester.tap(reconnectButton());
      await tester.pump();
      expect(popup(), findsOneWidget,
          reason: "sanity: still waiting on the old hub's stop()");

      await tester.pump(SignalRService.stopTimeout);
      await tester.pump();
      await tester.pump();

      expect(popup(), findsNothing);
      expect(e.hubs, hasLength(2));
      expect(e.hubs.last.invoked, [PlayGameHubEvents.checkPlayerGame]);
    });
  });

  group('4. the waiting screen recovers as it always did', () {
    test('a join owed when the entry connect lands goes out after '
        'CheckPlayerGame', () async {
      final e = buildEngine();
      e.controller.enterWaiting();
      await e.controller.onWaitingShown();
      expect(e.allInvoked, isEmpty, reason: 'sanity: no hub, join deferred');

      await e.connect();
      await pumpEventQueue();

      expect(e.hubs.single.invoked, [
        PlayGameHubEvents.checkPlayerGame,
        PlayGameHubEvents.joinRandomGame,
      ]);
    });

    test('a stale-status Reconnect after the join went out does not join '
        'again', () async {
      final e = buildEngine();
      e.controller.enterWaiting();
      await e.connect();
      await pumpEventQueue();
      final hub = e.hubs.single;
      expect(hub.count(PlayGameHubEvents.joinRandomGame), 1, reason: 'sanity');

      hub
        ..dropToReconnecting()
        ..comeBackSilently();
      await e.service.recoverConnection();
      await pumpEventQueue();

      expect(hub.count(PlayGameHubEvents.checkPlayerGame), 2);
      expect(hub.count(PlayGameHubEvents.joinRandomGame), 1,
          reason: 'one join per session; recovery does not repeat it');
    });

    test('a stale-status Reconnect sends a join that is still owed, once',
        () async {
      final e = buildEngine();
      e.controller.enterWaiting();
      await e.connect();
      await pumpEventQueue();
      final hub = e.hubs.single..dropToReconnecting();

      // A new public entry while the hub is down: its join is deferred.
      e.controller.enterWaiting();
      await e.controller.onWaitingShown();
      expect(hub.count(PlayGameHubEvents.joinRandomGame), 1,
          reason: 'sanity: deferred, not sent');

      hub.comeBackSilently();
      await e.service.recoverConnection();
      await pumpEventQueue();

      expect(hub.invoked.skip(2).toList(), [
        PlayGameHubEvents.checkPlayerGame,
        PlayGameHubEvents.joinRandomGame,
      ]);
      expect(hub.count(PlayGameHubEvents.joinRandomGame), 2,
          reason: 'one per session: the first entry and this one');
    });
  });
}
