import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalr_core/signalr_core.dart';

// T2 / T-COV — the SignalR connection lifecycle.
//
// These are the paths that were unreachable before the seam: everything from
// `connect()`'s builder onward. `SignalRService` now takes an optional
// `HubConnectionFactory`; production passes none and keeps the real builder,
// while these tests pass a fake.
//
// The fake is a real `HubConnection` subclass, which the package permits:
// `class HubConnection` carries no `final`/`base` modifier, its `connection`
// parameter is nullable, and `JsonHubProtocol` is exported and constructible.
// Passing `connection: null` means the constructor's `if (_connection != null)`
// wiring is skipped — no transport, no socket, no negotiate. Every method the
// service calls is overridden, so nothing reaches the network.
//
// Timing is controlled, never real: the service's reconnect backoff runs on
// `Timer`, so the schedule assertions run inside `fakeAsync` and advance
// deliberately. No test sleeps and none touches the network.

/// A `HubConnection` that answers in-memory.
///
/// Captures the callbacks the service registers so a test can fire `onclose`,
/// `onreconnecting` and `onreconnected` exactly as the real hub would.
class _FakeHubConnection extends HubConnection {
  _FakeHubConnection({
    this.startError,
    this.startCompleter,
  }) : super(protocol: JsonHubProtocol());

  /// When set, `start()` throws it — the failed-connect path.
  final Object? startError;

  /// When set, `start()` waits on it, so a test can hold a connect in flight.
  final Completer<void>? startCompleter;

  final closedCallbacks = <ClosedCallback>[];
  final reconnectingCallbacks = <ReconnectingCallback>[];
  final reconnectedCallbacks = <ReconnectedCallback>[];
  final registeredEvents = <String>[];
  final removedEvents = <String>[];

  int startCalls = 0;
  int stopCalls = 0;
  HubConnectionState _state = HubConnectionState.disconnected;

  @override
  HubConnectionState? get state => _state;

  @override
  String? get connectionId => 'fake-connection-id';

  @override
  Future<void>? start() async {
    startCalls++;
    final gate = startCompleter;
    if (gate != null) {
      await gate.future;
    }
    final error = startError;
    if (error != null) {
      _state = HubConnectionState.disconnected;
      throw error;
    }
    _state = HubConnectionState.connected;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _state = HubConnectionState.disconnected;
  }

  @override
  void on(String methodName, MethodInvocationFunc newMethod) {
    registeredEvents.add(methodName);
  }

  @override
  void off(String methodName, {MethodInvocationFunc? method}) {
    removedEvents.add(methodName);
  }

  @override
  void onclose(ClosedCallback callback) => closedCallbacks.add(callback);

  @override
  void onreconnecting(ReconnectingCallback callback) =>
      reconnectingCallbacks.add(callback);

  @override
  void onreconnected(ReconnectedCallback callback) =>
      reconnectedCallbacks.add(callback);

  /// Drives the hub's own callbacks, the way the real transport would.
  void fireClose([Exception? error]) {
    _state = HubConnectionState.disconnected;
    for (final callback in List.of(closedCallbacks)) {
      callback(error);
    }
  }

  void fireReconnecting([Exception? error]) {
    _state = HubConnectionState.reconnecting;
    for (final callback in List.of(reconnectingCallbacks)) {
      callback(error);
    }
  }

  void fireReconnected([String? connectionId]) {
    _state = HubConnectionState.connected;
    for (final callback in List.of(reconnectedCallbacks)) {
      callback(connectionId);
    }
  }
}

class _FakeNetworkInfo implements NetworkInfo {
  _FakeNetworkInfo({this.online = true});

  bool online;

  @override
  bool get isOnline => online;

  @override
  Future<bool> get isConnected async => online;

  @override
  Stream<bool> get onStatusChange => const Stream<bool>.empty();

  @override
  void dispose() {}
}

const _url = 'ws://fake.test/hub';

void main() {
  late _FakeHubConnection hub;
  late SignalRService service;
  late List<SignalRStatus> seen;

  /// Builds a service wired to [hub]. `headersBuilder` is deliberately not
  /// supplied: with a factory injected, the real builder — the only thing
  /// that needs it — never runs.
  SignalRService buildService({
    _FakeHubConnection? connection,
    NetworkInfo? networkInfo,
  }) {
    hub = connection ?? _FakeHubConnection();
    final built = SignalRService(
      networkInfo: networkInfo,
      hubConnectionFactory: (url, tokenFactory) => hub,
    );
    seen = <SignalRStatus>[];
    built.statusStream.listen(seen.add);
    addTearDown(built.dispose);
    return built;
  }

  Future<void> connect(SignalRService target) => target.connect(
        url: _url,
        accessTokenFactory: () async => 'token',
      );

  group('1. a successful connect', () {
    setUp(() => service = buildService());

    test('starts the connection and reports connected', () async {
      await connect(service);
      // statusStream is an async broadcast controller: let the emissions
      // land before asserting on the sequence.
      await Future<void>.delayed(Duration.zero);

      expect(hub.startCalls, 1);
      expect(service.isConnected, isTrue);
      expect(service.checkConnectionStatus(), SignalRStatus.connected);
      expect(seen, [SignalRStatus.connecting, SignalRStatus.connected]);
    });

    test('stores the session so reconnect has something to replay', () async {
      await connect(service);
      expect(service.hasStoredHubSession, isTrue);
    });

    test('registers all three lifecycle callbacks exactly once', () async {
      await connect(service);

      expect(hub.closedCallbacks, hasLength(1));
      expect(hub.reconnectingCallbacks, hasLength(1));
      expect(hub.reconnectedCallbacks, hasLength(1));
    });

    test('re-attaches previously registered event handlers on connect',
        () async {
      service.addEventListener('GameUpdated', (_) {});
      service.addEventListener('GameStarted', (_) {});

      await connect(service);

      expect(hub.registeredEvents, containsAll(['GameUpdated', 'GameStarted']),
          reason: 'handlers registered before the socket existed must be '
              'attached to it once it does');
    });

    test('announces recovery so listeners can re-sync', () async {
      final recovered = <void>[];
      service.recoveredStream.listen(recovered.add);

      await connect(service);
      await Future<void>.delayed(Duration.zero);

      expect(recovered, hasLength(1));
    });

    test('a second connect is skipped while already connected', () async {
      await connect(service);
      await connect(service);

      expect(hub.startCalls, 1, reason: '_skipIfAlreadyConnected');
    });
  });

  group('2. a failed start', () {
    setUp(() {
      service = buildService(
        connection: _FakeHubConnection(startError: StateError('handshake')),
      );
    });

    test('reports failed and is not connected', () async {
      await connect(service);
      await Future<void>.delayed(Duration.zero);

      expect(service.isConnected, isFalse);
      expect(seen.last, SignalRStatus.failed);
    });

    test('schedules a backoff reconnect rather than giving up', () {
      fakeAsync((async) {
        unawaited(connect(service));
        async.flushMicrotasks();
        expect(seen.last, SignalRStatus.failed);

        // The failure path uses useBackoff, whose first delay is 1000ms.
        async.elapse(const Duration(milliseconds: 999));
        expect(hub.startCalls, 1, reason: 'not yet');

        async.elapse(const Duration(milliseconds: 2));
        expect(hub.startCalls, 2, reason: 'the retry fired');
      });
    });

    test('a NoInternetException is reported as no-internet, not failed, and '
        'is not retried', () {
      fakeAsync((async) {
        service = buildService(
          connection: _FakeHubConnection(
            startError: const NoInternetException(),
          ),
        );
        unawaited(connect(service));
        async.flushMicrotasks();

        expect(seen.last, SignalRStatus.disconnectedNoInternet);

        async.elapse(const Duration(minutes: 2));
        expect(hub.startCalls, 1,
            reason: 'the no-internet arm returns before _scheduleReconnect');
      });
    });
  });

  group('3. onclose', () {
    setUp(() => service = buildService());

    test('reports disconnected', () async {
      await connect(service);
      hub.fireClose();

      expect(service.checkConnectionStatus(), SignalRStatus.disconnected);
    });

    test('schedules a reconnect after a drop', () {
      fakeAsync((async) {
        unawaited(connect(service));
        async.flushMicrotasks();
        hub.fireClose(Exception('socket gone'));

        // onclose uses initialDelayMs: 1000, not the backoff.
        async.elapse(const Duration(milliseconds: 1001));
        expect(hub.startCalls, 2);
      });
    });

    test('a close after a manual disconnect does NOT reconnect', () {
      fakeAsync((async) {
        unawaited(connect(service));
        async.flushMicrotasks();

        unawaited(service.disconnect());
        async.flushMicrotasks();
        hub.fireClose();

        async.elapse(const Duration(minutes: 2));
        expect(hub.startCalls, 1,
            reason: 'the app asked for the hub to be down');
        expect(service.isManuallyDisconnected, isTrue);
      });
    });
  });

  group('4. onreconnecting', () {
    test('reports reconnecting without touching the stored session', () async {
      service = buildService();
      await connect(service);

      hub.fireReconnecting(Exception('blip'));

      expect(service.checkConnectionStatus(), SignalRStatus.reconnecting);
      expect(service.hasStoredHubSession, isTrue);
    });
  });

  group('5. onreconnected', () {
    setUp(() => service = buildService());

    test('reports connected again', () async {
      await connect(service);
      hub.fireReconnecting();
      hub.fireReconnected('new-id');

      expect(service.checkConnectionStatus(), SignalRStatus.connected);
    });

    test('re-attaches handlers, because events fired while down were lost',
        () async {
      service.addEventListener('GameUpdated', (_) {});
      await connect(service);
      hub.registeredEvents.clear();

      hub.fireReconnected('new-id');

      expect(hub.registeredEvents, contains('GameUpdated'));
    });

    test('announces recovery', () async {
      await connect(service);
      final recovered = <void>[];
      service.recoveredStream.listen(recovered.add);

      hub.fireReconnected('new-id');
      await Future<void>.delayed(Duration.zero);

      expect(recovered, hasLength(1));
    });

    test('resets the backoff, so the next failure starts at 1s again', () {
      fakeAsync((async) {
        unawaited(connect(service));
        async.flushMicrotasks();
        hub.fireReconnected('new-id');

        hub.fireClose();
        async.elapse(const Duration(milliseconds: 1001));
        expect(hub.startCalls, 2);
      });
    });
  });

  group('6. reconnect scheduling and its guards', () {
    test('the backoff doubles between attempts and is capped', () {
      fakeAsync((async) {
        service = buildService(
          connection: _FakeHubConnection(startError: StateError('nope')),
        );
        unawaited(connect(service));
        async.flushMicrotasks();

        // 1000ms, then 2000, then 4000 — each failure doubles _retryDelayMs.
        async.elapse(const Duration(milliseconds: 1001));
        expect(hub.startCalls, 2);

        async.elapse(const Duration(milliseconds: 1001));
        expect(hub.startCalls, 2, reason: 'the second wait is longer');

        async.elapse(const Duration(milliseconds: 1001));
        expect(hub.startCalls, 3);
      });
    });

    test('no duplicate reconnect while one attempt is already in flight', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        service = buildService(
          connection: _FakeHubConnection(startCompleter: gate),
        );
        unawaited(connect(service));
        async.flushMicrotasks();

        // A connect is in flight (start() is awaiting the gate).
        unawaited(service.reconnect());
        unawaited(service.reconnect());
        async.flushMicrotasks();

        expect(hub.startCalls, 1,
            reason: '_skipIfAlreadyConnected covers connecting, not just '
                'connected');

        gate.complete();
        async.flushMicrotasks();
      });
    });

    test('a manual disconnect cancels a pending reconnect timer', () {
      fakeAsync((async) {
        service = buildService(
          connection: _FakeHubConnection(startError: StateError('nope')),
        );
        unawaited(connect(service));
        async.flushMicrotasks();

        unawaited(service.disconnect());
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 2));
        expect(hub.startCalls, 1, reason: 'the scheduled retry was cancelled');
      });
    });
  });

  group('7. no-internet stop', () {
    test('stops the hub and reports no-internet', () {
      fakeAsync((async) {
        service = buildService();
        unawaited(connect(service));
        async.flushMicrotasks();

        service.onInternetStatusChanged(false);
        async.flushMicrotasks();

        expect(hub.stopCalls, 1);
        expect(
          service.checkConnectionStatus(),
          SignalRStatus.disconnectedNoInternet,
        );
      });
    });

    test('the close that the stop triggers does not schedule a reconnect', () {
      fakeAsync((async) {
        service = buildService();
        unawaited(connect(service));
        async.flushMicrotasks();

        service.onInternetStatusChanged(false);
        // The real hub fires onclose while the service is stopping it.
        hub.fireClose();
        async.flushMicrotasks();

        async.elapse(const Duration(minutes: 2));
        expect(hub.startCalls, 1,
            reason: '_suppressAutoReconnect covers the deliberate stop');
      });
    });
  });

  group('8. internet-restored recovery', () {
    test('reconnects automatically when internet returns', () {
      fakeAsync((async) {
        service = buildService();
        unawaited(connect(service));
        async.flushMicrotasks();
        expect(hub.startCalls, 1);

        service.onInternetStatusChanged(false);
        async.flushMicrotasks();

        service.onInternetStatusChanged(true);
        async.flushMicrotasks();

        expect(hub.startCalls, 2,
            reason: 'no Reconnect tap was involved');
        expect(service.checkConnectionStatus(), SignalRStatus.connected);
      });
    });

    test('internet returning does not undo a manual disconnect', () {
      fakeAsync((async) {
        service = buildService();
        unawaited(connect(service));
        async.flushMicrotasks();

        unawaited(service.disconnect());
        async.flushMicrotasks();

        service.onInternetStatusChanged(false);
        service.onInternetStatusChanged(true);
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 2));

        expect(hub.startCalls, 1);
        expect(service.isManuallyDisconnected, isTrue);
      });
    });

    test('recoverConnection replays the stored session', () {
      fakeAsync((async) {
        service = buildService();
        unawaited(connect(service));
        async.flushMicrotasks();
        hub.fireClose();
        async.flushMicrotasks();

        unawaited(service.recoverConnection());
        async.flushMicrotasks();

        expect(hub.startCalls, greaterThanOrEqualTo(2));
      });
    });
  });

  group('9. manual disconnect versus a real drop', () {
    test('both report `disconnected`, and the flag is what separates them',
        () async {
      service = buildService();
      await connect(service);
      hub.fireClose();
      expect(service.checkConnectionStatus(), SignalRStatus.disconnected);
      expect(service.isManuallyDisconnected, isFalse,
          reason: 'a drop is not a deliberate shutdown');

      final second = buildService();
      await connect(second);
      await second.disconnect();
      expect(second.checkConnectionStatus(), SignalRStatus.disconnected);
      expect(second.isManuallyDisconnected, isTrue);
    });

    test('a reconnect after a manual disconnect clears the flag', () async {
      service = buildService();
      await connect(service);
      await service.disconnect();
      expect(service.isManuallyDisconnected, isTrue);

      await service.reconnect();

      expect(service.isManuallyDisconnected, isFalse);
      expect(service.isConnected, isTrue);
    });
  });

  group('10. the status stream a loader would render', () {
    test('a full drop-and-recover cycle emits exactly the expected sequence',
        () {
      fakeAsync((async) {
        service = buildService();
        unawaited(connect(service));
        async.flushMicrotasks();

        hub.fireReconnecting();
        hub.fireReconnected('id');
        async.flushMicrotasks();

        expect(seen, [
          SignalRStatus.connecting,
          SignalRStatus.connected,
          SignalRStatus.reconnecting,
          SignalRStatus.connected,
        ]);
      });
    });

    test('never reports connected while an attempt is still in flight', () {
      fakeAsync((async) {
        final gate = Completer<void>();
        service = buildService(
          connection: _FakeHubConnection(startCompleter: gate),
        );
        unawaited(connect(service));
        async.flushMicrotasks();

        expect(seen, [SignalRStatus.connecting]);
        expect(service.isConnected, isFalse,
            reason: 'the loader must stay up until start() returns');

        gate.complete();
        async.flushMicrotasks();
        expect(seen.last, SignalRStatus.connected);
      });
    });

    test('an offline connect never reaches the socket at all', () async {
      service = buildService(networkInfo: _FakeNetworkInfo(online: false));

      await connect(service);

      expect(hub.startCalls, 0);
      expect(seen, [SignalRStatus.disconnectedNoInternet]);
      expect(service.hasStoredHubSession, isFalse,
          reason: 'the guard returns above the `_hubUrl = url` assignment');
    });
  });

  group('11. listener cleanup across the connection', () {
    test('unsubscribeAll takes the handlers off the live connection', () async {
      service = buildService();
      service.addEventListener('GameUpdated', (_) {});
      await connect(service);

      service.unsubscribeAll();

      expect(hub.removedEvents, contains('GameUpdated'));
      expect(service.isSubscribed('GameUpdated'), isFalse);
    });

    test('removing the last listener detaches it from the connection',
        () async {
      service = buildService();
      final remove = service.addEventListener('GameUpdated', (_) {});
      await connect(service);

      remove();

      expect(hub.removedEvents, contains('GameUpdated'));
    });

    test('dispose stops the connection and closes the streams', () async {
      final local = SignalRService(
        hubConnectionFactory: (url, tokenFactory) => hub,
      );
      hub = _FakeHubConnection();
      await local.connect(url: _url, accessTokenFactory: () async => 'token');

      await local.dispose();

      expect(
        () => local.statusStream.listen((_) {}),
        returnsNormally,
        reason: 'a closed broadcast stream still accepts a listener',
      );
    });
  });

  group('12. the injected factory is a test-only seam', () {
    test('the factory receives the url and a working token factory',
        () async {
      String? seenUrl;
      String? seenToken;
      final probe = SignalRService(
        hubConnectionFactory: (url, tokenFactory) {
          seenUrl = url;
          unawaited(tokenFactory().then((value) => seenToken = value));
          return hub = _FakeHubConnection();
        },
      );
      addTearDown(probe.dispose);

      await probe.connect(url: _url, accessTokenFactory: () async => 'tok');
      await Future<void>.delayed(Duration.zero);

      expect(seenUrl, _url);
      expect(seenToken, 'tok',
          reason: 'the real builder needs it for the upgrade headers');
    });

    test('a service with no factory keeps the production builder path', () {
      // Constructing it is enough: the default path is only taken inside
      // connect(), and this asserts the seam is opt-in, not required.
      final production = SignalRService();
      addTearDown(production.dispose);

      expect(production.checkConnectionStatus(), SignalRStatus.idle);
      expect(production.hasStoredHubSession, isFalse);
    });
  });

  // The connect() race.
  //
  // `_skipIfAlreadyConnected` reads `hasLiveConnection`, which is driven by
  // `_isConnecting`. That flag used to be set only after `await
  // tokenFactory()`, so two callers landing together both passed the guard
  // and each built and started a HubConnection — two live sockets delivering
  // the same events. The claim is now taken synchronously, before any await.
  group('13. concurrent connect() calls', () {
    /// Counts how many connections the factory was asked to build, and holds
    /// the token lookup open so both callers are inside connect() at once.
    test('two callers arriving together create and start exactly one '
        'HubConnection', () async {
      var built = 0;
      final tokenGate = Completer<void>();
      late _FakeHubConnection created;

      final service = SignalRService(
        hubConnectionFactory: (url, tokenFactory) {
          built++;
          return created = _FakeHubConnection();
        },
      );
      addTearDown(service.dispose);

      Future<void> connectOnce() => service.connect(
            url: _url,
            accessTokenFactory: () async {
              await tokenGate.future;
              return 'token';
            },
          );

      // Both start before either has a token — the exact interleaving that
      // used to produce two connections.
      final first = connectOnce();
      final second = connectOnce();
      tokenGate.complete();
      await Future.wait([first, second]);

      expect(built, 1, reason: 'only one HubConnection was ever built');
      expect(created.startCalls, 1, reason: 'and it was started once');
      expect(service.isConnected, isTrue);
    });

    test('the second caller is skipped, not queued or replayed', () async {
      var built = 0;
      final tokenGate = Completer<void>();

      final service = SignalRService(
        hubConnectionFactory: (url, tokenFactory) {
          built++;
          return _FakeHubConnection();
        },
      );
      addTearDown(service.dispose);

      final statuses = <SignalRStatus>[];
      service.statusStream.listen(statuses.add);

      Future<void> connectOnce() => service.connect(
            url: _url,
            accessTokenFactory: () async {
              await tokenGate.future;
              return 'token';
            },
          );

      final first = connectOnce();
      final second = connectOnce();
      tokenGate.complete();
      await Future.wait([first, second]);
      await Future<void>.delayed(Duration.zero);

      expect(built, 1);
      expect(
        statuses.where((s) => s == SignalRStatus.connecting).length,
        1,
        reason: 'one connect ran; the other returned at the guard without '
            'restarting the handshake',
      );
    });

    test('handlers are registered on the connection that actually started',
        () async {
      late _FakeHubConnection created;
      final service = SignalRService(
        hubConnectionFactory: (url, tokenFactory) => created =
            _FakeHubConnection(),
      );
      addTearDown(service.dispose);

      service.addEventListener('GameFinished', (_) {});
      await service.connect(
        url: _url,
        accessTokenFactory: () async => 'token',
      );

      expect(created.registeredEvents, contains('GameFinished'),
          reason: 'the started instance carries the dispatchers — a socket '
              'without them is what logged "No client method with the name '
              'GameFinished found"');
    });

    test('a failed token lookup releases the claim, so a later connect is '
        'not skipped as already-connecting', () async {
      var built = 0;
      final service = SignalRService(
        hubConnectionFactory: (url, tokenFactory) {
          built++;
          return _FakeHubConnection();
        },
      );
      addTearDown(service.dispose);

      await service.connect(
        url: _url,
        accessTokenFactory: () async => throw StateError('no token'),
      );
      expect(built, 0);
      expect(service.isConnecting, isFalse,
          reason: 'the claim must not survive a throwing token factory');

      await service.connect(
        url: _url,
        accessTokenFactory: () async => 'token',
      );
      expect(built, 1, reason: 'the retry was allowed through');
    });

    test('an empty token also releases the claim', () async {
      final service = SignalRService(
        hubConnectionFactory: (url, tokenFactory) => _FakeHubConnection(),
      );
      addTearDown(service.dispose);

      await service.connect(
        url: _url,
        accessTokenFactory: () async => '',
      );

      expect(service.isConnecting, isFalse);
      expect(service.checkConnectionStatus(), SignalRStatus.failed);
    });
  });

  // The overnight-sleep deadlock: a start() that never completes.
  //
  // `_isConnecting` is released only after `start()` returns, and it is what
  // `hasLiveConnection` reports. A socket that died silently while the device
  // slept leaves the attempt awaiting forever, so resume, the Reconnect
  // button and the backoff scheduler all skip on a claim that will never be
  // released, and the connection loader never comes down.
  group('14. a start() that never completes', () {
    late Completer<void> stalled;

    setUp(() {
      stalled = Completer<void>();
      service = buildService(
        connection: _FakeHubConnection(startCompleter: stalled),
      );
    });

    tearDown(() {
      if (!stalled.isCompleted) {
        stalled.complete();
      }
    });

    test('holds the connection in flight until the timeout elapses', () {
      fakeAsync((async) {
        unawaited(connect(service));
        async.elapse(const Duration(seconds: 1));

        expect(service.isConnecting, isTrue, reason: 'sanity: in flight');
        expect(service.hasLiveConnection, isTrue);
        expect(service.checkConnectionStatus(), SignalRStatus.connecting);

        // Past the timeout but short of the 1s backoff retry, which would
        // legitimately claim the flag again.
        async.elapse(const Duration(seconds: 29, milliseconds: 500));

        expect(
          service.isConnecting,
          isFalse,
          reason: 'the timeout must release the claim that blocks every '
              'other connect path',
        );
        expect(service.hasLiveConnection, isFalse);
      });
    });

    test('a timed-out start reaches the existing failed path', () {
      fakeAsync((async) {
        unawaited(connect(service));
        async.elapse(const Duration(seconds: 30, milliseconds: 500));

        expect(service.checkConnectionStatus(), SignalRStatus.failed);
      });
    });

    test('and schedules the existing backoff retry', () {
      fakeAsync((async) {
        unawaited(connect(service));
        async.elapse(const Duration(seconds: 30, milliseconds: 500));
        final afterTimeout = hub.startCalls;

        // The same 1s first backoff every other failure gets.
        async.elapse(const Duration(seconds: 2));

        expect(
          hub.startCalls,
          greaterThan(afterTimeout),
          reason: 'recovery continues on its own after a stall',
        );
      });
    });

    test('onAppResumed can reconnect once the stale attempt is cleared', () {
      fakeAsync((async) {
        unawaited(connect(service));
        async.elapse(const Duration(seconds: 1));

        // Resume while the attempt is still in flight: correctly skipped,
        // because a connect really is running.
        service.onAppResumed();
        async.flushMicrotasks();
        expect(hub.startCalls, 1, reason: 'nothing new while genuinely live');

        async.elapse(const Duration(seconds: 29, milliseconds: 500));
        final afterTimeout = hub.startCalls;

        service.onAppResumed();
        async.elapse(const Duration(milliseconds: 10));

        expect(
          hub.startCalls,
          greaterThan(afterTimeout),
          reason: 'resume must be able to reconnect once the claim is gone',
        );
      });
    });
  });

  group('15. explicit Reconnect overrides a stale claim', () {
    test('recoverConnection starts a new attempt while one looks in flight',
        () {
      fakeAsync((async) {
        final stalled = Completer<void>();
        service = buildService(
          connection: _FakeHubConnection(startCompleter: stalled),
        );

        unawaited(connect(service));
        async.elapse(const Duration(seconds: 1));
        expect(service.hasLiveConnection, isTrue, reason: 'sanity: stale');
        final before = hub.startCalls;

        unawaited(service.recoverConnection());
        async.elapse(const Duration(seconds: 1));

        expect(
          hub.startCalls,
          greaterThan(before),
          reason: 'the button must do something — this is the state in which '
              'it used to be a silent no-op',
        );
        stalled.complete();
      });
    });

    test('a genuinely connected hub is not torn down', () async {
      service = buildService();
      await connect(service);
      await Future<void>.delayed(Duration.zero);
      expect(service.isConnected, isTrue, reason: 'sanity');
      final startsBefore = hub.startCalls;
      final stopsBefore = hub.stopCalls;

      await service.recoverConnection();

      expect(hub.stopCalls, stopsBefore,
          reason: 'nothing is stopped while the hub is healthy');
      expect(hub.startCalls, startsBefore,
          reason: 'and no redundant reconnect is issued');
      expect(service.isConnected, isTrue);
      expect(service.checkConnectionStatus(), SignalRStatus.connected);
    });

    test('a healthy hub is left alone when internet is reported up', () async {
      service = buildService();
      await connect(service);
      await Future<void>.delayed(Duration.zero);
      final startsBefore = hub.startCalls;
      final stopsBefore = hub.stopCalls;

      // No prior loss, so onInternetStatusChanged returns before the recovery
      // path — unchanged by this fix. (A genuine loss deliberately stops the
      // hub and reconnects on restore; that is group 7/8's subject.)
      service.onInternetStatusChanged(true);
      await Future<void>.delayed(Duration.zero);

      expect(hub.startCalls, startsBefore);
      expect(hub.stopCalls, stopsBefore);
      expect(service.isConnected, isTrue);
    });
  });
}
