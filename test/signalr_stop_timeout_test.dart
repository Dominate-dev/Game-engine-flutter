import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:coreapp/coreapp.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signalr_core/signalr_core.dart';

// Long-idle stale hub. signalr_core 1.1.2 never completes stop() when it lands
// on an in-flight start that then fails, so cleanup used to block forever and
// no fresh HubConnection could be built. Most tests here run the real
// HubConnection/HttpConnection over a scripted transport, because an instant
// fake stop() cannot show that.

const _url = 'http://stale.test/hub';
const _retryDelays = [0, 2000, 5000, 10000, 15000, 30000];

class _ScriptedTransport implements Transport {
  bool holdConnects = false;
  final held = <Completer<void>>[];

  @override
  OnReceive? onreceive;

  @override
  OnClose? onclose;

  @override
  Future<void> connect(String? url, TransferFormat? transferFormat) {
    if (!holdConnects) {
      return Future<void>.value();
    }
    final attempt = Completer<void>();
    held.add(attempt);
    return attempt.future;
  }

  @override
  Future<void> send(dynamic data) {
    final text = data as String;
    // Handshake answer; anything else gets a ping so the server timeout
    // never fires while a test holds a connection open.
    _reply(text.contains('"protocol"') ? '{}' : '{"type":6}');
    return Future<void>.value();
  }

  @override
  Future<void> stop() {
    onclose?.call(null);
    return Future<void>.value();
  }

  void drop() => onclose?.call(null);

  void _reply(String message) {
    scheduleMicrotask(() => onreceive?.call('$message\u001e'));
  }
}

class _NegotiateClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = utf8.encode(
      '{"connectionId":"c","connectionToken":"t","negotiateVersion":1,'
      '"availableTransports":[]}',
    );
    return http.StreamedResponse(Stream<List<int>>.value(body), 200);
  }
}

// In-memory hub whose stop() can be held forever, as signalr_core's is.
class _FakeHub extends HubConnection {
  _FakeHub({this.startError, this.holdStop = true})
      : super(protocol: JsonHubProtocol());

  final Object? startError;
  final bool holdStop;

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
    final error = startError;
    if (error != null) {
      throw error;
    }
    _state = HubConnectionState.connected;
  }

  @override
  Future<void> stop() {
    if (holdStop) {
      return Completer<void>().future;
    }
    _state = HubConnectionState.disconnected;
    return Future<void>.value();
  }

  @override
  void on(String methodName, MethodInvocationFunc newMethod) {}

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

  void fireClose([Exception? error]) {
    for (final callback in List.of(_closed)) {
      callback(error);
    }
  }

  void fireReconnecting() {
    _state = HubConnectionState.reconnecting;
    for (final callback in List.of(_reconnecting)) {
      callback(null);
    }
  }

  void fireReconnected(String id) {
    for (final callback in List.of(_reconnected)) {
      callback(id);
    }
  }
}

class _CountingService extends SignalRService {
  _CountingService({super.hubConnectionFactory});

  int recoverCalls = 0;

  @override
  Future<void> recoverConnection() {
    recoverCalls++;
    return super.recoverConnection();
  }
}

HubConnection _realHub(String url, _ScriptedTransport transport) {
  return HubConnectionBuilder()
      .withUrl(
        url,
        HttpConnectionOptions(
          transport: transport,
          client: _NegotiateClient(),
          logging: (level, message) {},
        ),
      )
      .withAutomaticReconnect(_retryDelays)
      .build();
}

SignalRService _service(
  List<HubConnection> hubs,
  HubConnection Function(int index, String url) make,
) {
  return SignalRService(
    hubConnectionFactory: (url, tokenFactory) {
      final hub = make(hubs.length, url);
      hubs.add(hub);
      return hub;
    },
  );
}

Future<void> _connect(SignalRService service) =>
    service.connect(url: _url, accessTokenFactory: () async => 'token');

void main() {
  late List<HubConnection> hubs;
  late List<_ScriptedTransport> transports;

  setUp(() {
    hubs = <HubConnection>[];
    transports = <_ScriptedTransport>[];
  });

  HubConnection scripted(String url, {bool hold = false}) {
    final transport = _ScriptedTransport()..holdConnects = hold;
    transports.add(transport);
    return _realHub(url, transport);
  }

  // Connects a real hub, drops it, and leaves signalr_core's own reconnect
  // attempt in flight.
  _ScriptedTransport connectDropAndHoldReconnect(
    FakeAsync async,
    SignalRService service,
  ) {
    unawaited(_connect(service));
    async.flushMicrotasks();
    expect(service.isConnected, isTrue, reason: 'sanity: real hub connected');

    final first = transports.single..holdConnects = true;
    first.drop();
    async.elapse(const Duration(milliseconds: 1));
    expect(first.held, hasLength(1), reason: 'sanity: attempt in flight');
    expect(service.checkConnectionStatus(), SignalRStatus.reconnecting);
    return first;
  }

  group('stop() that never returns is bounded', () {
    test('a stalled start: the stale hub is cleared and a fresh one connects',
        () {
      fakeAsync((async) {
        final service = _service(hubs, (i, url) => scripted(url, hold: i == 0));
        var connectDone = false;
        unawaited(_connect(service).whenComplete(() => connectDone = true));

        async.elapse(SignalRService.startTimeout);
        expect(connectDone, isFalse, reason: 'cleanup is waiting on stop()');

        async.elapse(SignalRService.stopTimeout);
        expect(connectDone, isTrue, reason: 'stop() no longer blocks forever');
        expect(service.checkConnectionStatus(), SignalRStatus.failed);
        expect(hubs, hasLength(1));
        expect(hubs.single.state, HubConnectionState.disconnecting,
            reason: 'signalr_core itself never finished stopping it');

        async.elapse(const Duration(seconds: 1));
        expect(hubs, hasLength(2), reason: 'the backoff built a fresh hub');
        expect(service.isConnected, isTrue);
        expect(service.checkConnectionStatus(), SignalRStatus.connected);
      });
    });

    test('Reconnect while an auto-reconnect attempt is in flight completes '
        'and connects a fresh hub', () {
      fakeAsync((async) {
        final service = _service(hubs, (i, url) => scripted(url));
        final first = connectDropAndHoldReconnect(async, service);

        var recovered = false;
        unawaited(
          service.recoverConnection().whenComplete(() => recovered = true),
        );
        async.flushMicrotasks();
        first.held.single.completeError(
          const SocketException('Network is unreachable'),
        );
        async.flushMicrotasks();
        expect(recovered, isFalse, reason: 'signalr_core stop() is stuck');

        async.elapse(SignalRService.stopTimeout);

        expect(recovered, isTrue);
        expect(hubs, hasLength(2));
        expect(hubs.first.state, HubConnectionState.disconnecting);
        expect(service.isConnected, isTrue);
        expect(service.checkConnectionStatus(), SignalRStatus.connected);
      });
    });

    test('internet lost during an auto-reconnect attempt: no-internet is '
        'reported and a fresh hub connects when it returns', () {
      fakeAsync((async) {
        final service = _service(hubs, (i, url) => scripted(url));
        final first = connectDropAndHoldReconnect(async, service);

        service.onInternetStatusChanged(false);
        async.flushMicrotasks();
        first.held.single.completeError(
          const SocketException('Network is unreachable'),
        );
        async.elapse(SignalRService.stopTimeout);

        expect(
          service.checkConnectionStatus(),
          SignalRStatus.disconnectedNoInternet,
        );
        expect(hubs, hasLength(1));

        service.onInternetStatusChanged(true);
        async.flushMicrotasks();

        expect(hubs, hasLength(2), reason: 'automatic recovery was not blocked');
        expect(service.isConnected, isTrue);
        expect(service.checkConnectionStatus(), SignalRStatus.connected);
      });
    });

    test('internet lost during the first connect: no-internet is reported '
        'and a fresh hub connects when it returns', () {
      fakeAsync((async) {
        final service = _service(hubs, (i, url) => scripted(url, hold: i == 0));
        unawaited(_connect(service));
        async.flushMicrotasks();
        expect(transports.single.held, hasLength(1));

        service.onInternetStatusChanged(false);
        async.flushMicrotasks();
        transports.single.held.single.completeError(
          const SocketException('Network is unreachable'),
        );
        async.elapse(SignalRService.stopTimeout);

        expect(
          service.checkConnectionStatus(),
          SignalRStatus.disconnectedNoInternet,
        );

        service.onInternetStatusChanged(true);
        async.flushMicrotasks();

        expect(hubs, hasLength(2));
        expect(service.isConnected, isTrue);
      });
    });

    test('disconnect() returns and a later connect builds a fresh hub', () {
      fakeAsync((async) {
        final service = _service(
          hubs,
          (i, url) => i == 0 ? _FakeHub() : scripted(url),
        );
        unawaited(_connect(service));
        async.flushMicrotasks();

        var done = false;
        unawaited(service.disconnect().whenComplete(() => done = true));
        async.flushMicrotasks();
        expect(done, isFalse);

        async.elapse(SignalRService.stopTimeout);
        expect(done, isTrue);
        expect(service.checkConnectionStatus(), SignalRStatus.disconnected);
        expect(service.isManuallyDisconnected, isTrue);

        unawaited(service.reconnect());
        async.flushMicrotasks();
        expect(hubs, hasLength(2));
        expect(service.isConnected, isTrue);
      });
    });
  });

  group('an abandoned hub cannot touch the new connection', () {
    test('its late onclose/onreconnecting/onreconnected are ignored', () {
      fakeAsync((async) {
        late _FakeHub old;
        final service = _service(
          hubs,
          (i, url) => i == 0 ? old = _FakeHub() : scripted(url),
        );
        final seen = <SignalRStatus>[];
        final recovered = <void>[];
        service.statusStream.listen(seen.add);
        service.recoveredStream.listen(recovered.add);

        unawaited(_connect(service));
        async.flushMicrotasks();
        old.fireReconnecting();
        unawaited(service.recoverConnection());
        async.elapse(SignalRService.stopTimeout);
        expect(hubs, hasLength(2));
        expect(service.isConnected, isTrue);
        final recoveredBefore = recovered.length;
        seen.clear();

        old.fireClose(Exception('late close'));
        old.fireReconnecting();
        old.fireReconnected('late');
        async.elapse(const Duration(minutes: 2));

        expect(seen, isEmpty);
        expect(recovered, hasLength(recoveredBefore));
        expect(hubs, hasLength(2), reason: 'no reconnect was scheduled');
        expect(service.isConnected, isTrue);
        expect(service.checkConnectionStatus(), SignalRStatus.connected);
      });
    });

    test('a cleanup that times out later cannot clear the fresh hub', () {
      fakeAsync((async) {
        late _FakeHub old;
        final service = _service(
          hubs,
          (i, url) => i == 0 ? old = _FakeHub() : scripted(url),
        );
        unawaited(_connect(service));
        async.flushMicrotasks();
        old.fireReconnecting();

        unawaited(service.recoverConnection());
        async.elapse(const Duration(seconds: 1));
        unawaited(service.recoverConnection());
        async.elapse(SignalRService.stopTimeout);

        expect(hubs, hasLength(2), reason: 'the fresh hub was not replaced');
        expect(service.isConnected, isTrue);
        expect(service.checkConnectionStatus(), SignalRStatus.connected);
      });
    });
  });

  testWidgets('Reconnect can be pressed again after a recovery completes',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': '47',
      'app_language': AppLanguage.english,
      'access_token': 'token-abc',
    });
    final prefs = await SharedPrefsService.init();
    late _FakeHub old;
    final service = _CountingService(
      hubConnectionFactory: (url, tokenFactory) {
        final hub = hubs.isEmpty
            ? old = _FakeHub()
            : _FakeHub(startError: StateError('unreachable'), holdStop: false);
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
    addTearDown(container.dispose);
    await _connect(service);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => LoaderOverlay(child: child!),
          home: const Scaffold(body: Text('game')),
        ),
      ),
    );
    old.fireReconnecting();
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));

    final reconnect = find.widgetWithText(
      GameButton,
      AppStrings.forLanguage(AppLanguage.english).reconnect,
    );
    expect(reconnect, findsOneWidget);

    await tester.tap(reconnect);
    await tester.pump();
    expect(service.recoverCalls, 1);

    await tester.pump(SignalRService.stopTimeout);
    expect(hubs, hasLength(2), reason: 'the first recovery ran to completion');
    expect(find.byType(ConnectionLoader), findsOneWidget);

    await tester.tap(reconnect);
    await tester.pump();
    expect(service.recoverCalls, 2,
        reason: 'the in-flight guard was released when recovery returned');
    expect(hubs, hasLength(3));

    await service.disconnect();
    await tester.pump();
  });
}
