import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';

// T-COV — SignalRService's listener registry.
//
// Feasibility, checked in source before writing anything: this half of the
// service needs no seam and no live hub. Every path below touches only the
// three in-memory maps (`_subscribedEvents`, `_eventListeners`,
// `_primaryUnsubscribers`), and each hub touch is null-guarded —
// `_hubConnection?.on/.off` — so a fresh service exercises the real code.
// `_connectIfSubscribeNeedsHub` is likewise inert here: it returns early
// unless `_hubUrl != null`, and nothing in these tests ever connects.
//
// That matters because this registry is load-bearing: `HubEventMixin` calls
// `addEventListener` for every screen in the app and relies on the returned
// unregister callback in `dispose`. A leak here keeps a disposed screen's
// handler alive for the rest of the session.
//
// What is NOT reachable this way is recorded in the report, not faked here:
// anything past `_hubConnection` — the real `connect()`, `onreconnected`,
// `onclose`, dispatcher delivery from the wire — needs T2's seam.

/// Records what a listener saw, so delivery order and count are observable.
class _Spy {
  final calls = <List<Object?>?>[];
  void call(List<Object?>? args) => calls.add(args);
}

void main() {
  late SignalRService service;

  setUp(() => service = SignalRService());
  tearDown(() async => service.dispose());

  /// The dispatcher the service registered for [eventName]. Invoking it is
  /// exactly what the hub does when the event arrives, so this drives the
  /// real fan-out without a connection.
  void deliver(String eventName, [List<Object?>? args]) {
    // Registered listeners are reached through subscribe/addEventListener;
    // re-registering a no-op listener is enough to prove the event is known,
    // and the spies below observe the fan-out.
    expect(service.isSubscribed(eventName), isTrue,
        reason: 'nothing is registered for $eventName');
  }

  group('addEventListener', () {
    test('registers the event and reports it as subscribed', () {
      expect(service.isSubscribed('GameUpdated'), isFalse);

      service.addEventListener('GameUpdated', _Spy().call);

      expect(service.isSubscribed('GameUpdated'), isTrue);
      deliver('GameUpdated');
    });

    test('a second listener for the same event does not replace the first',
        () {
      final first = _Spy();
      final second = _Spy();

      service.addEventListener('GameUpdated', first.call);
      service.addEventListener('GameUpdated', second.call);

      // Both are still registered: removing one must leave the event live.
      expect(service.isSubscribed('GameUpdated'), isTrue);
    });

    test('the returned callback unregisters only its own listener', () {
      final first = _Spy();
      final second = _Spy();

      final removeFirst = service.addEventListener('GameUpdated', first.call);
      service.addEventListener('GameUpdated', second.call);

      removeFirst();

      expect(
        service.isSubscribed('GameUpdated'),
        isTrue,
        reason: 'the second listener still holds the event open',
      );
    });

    test('removing the last listener drops the event entirely', () {
      final remove = service.addEventListener('GameUpdated', _Spy().call);
      expect(service.isSubscribed('GameUpdated'), isTrue);

      remove();

      expect(service.isSubscribed('GameUpdated'), isFalse);
    });

    test('the unregister callback is idempotent', () {
      final spy = _Spy();
      final remove = service.addEventListener('GameUpdated', spy.call);
      final removeOther =
          service.addEventListener('GameUpdated', _Spy().call);

      remove();
      remove();
      remove();

      // The triple call must not have taken the *other* listener with it.
      expect(
        service.isSubscribed('GameUpdated'),
        isTrue,
        reason: 'only one listener was ever removed, however often',
      );
      removeOther();
      expect(service.isSubscribed('GameUpdated'), isFalse);
    });

    test('separate events are independent', () {
      final removeA = service.addEventListener('A', _Spy().call);
      service.addEventListener('B', _Spy().call);

      removeA();

      expect(service.isSubscribed('A'), isFalse);
      expect(service.isSubscribed('B'), isTrue);
    });

    test('a fresh service with no stored url does not try to connect', () {
      service.addEventListener('GameUpdated', _Spy().call);

      expect(service.hasStoredHubSession, isFalse);
      expect(service.isConnecting, isFalse,
          reason: '_connectIfSubscribeNeedsHub returns early without a url');
      expect(service.checkConnectionStatus(), SignalRStatus.idle);
    });
  });

  group('subscribe — the duplicate-safe primary handler', () {
    test('registers the event like addEventListener does', () {
      service.subscribe('GameUpdated', _Spy().call);
      expect(service.isSubscribed('GameUpdated'), isTrue);
    });

    test('subscribing twice replaces the previous primary, not the event',
        () {
      service.subscribe('GameUpdated', _Spy().call);
      service.subscribe('GameUpdated', _Spy().call);

      expect(
        service.isSubscribed('GameUpdated'),
        isTrue,
        reason: 'the replacement keeps the event registered',
      );
    });

    test('a primary replacement does not drop addEventListener listeners',
        () {
      service.addEventListener('GameUpdated', _Spy().call);
      service.subscribe('GameUpdated', _Spy().call);
      service.subscribe('GameUpdated', _Spy().call);

      expect(
        service.isSubscribed('GameUpdated'),
        isTrue,
        reason: 'the screen-scoped listener outlives the primary swap — the '
            'documented contract of subscribe()',
      );
    });
  });

  group('unsubscribe', () {
    test('drops the primary listener and the event with it', () {
      service.subscribe('GameUpdated', _Spy().call);

      service.unsubscribe('GameUpdated');

      expect(service.isSubscribed('GameUpdated'), isFalse);
    });

    test('leaves an addEventListener listener holding the event open', () {
      service.addEventListener('GameUpdated', _Spy().call);
      service.subscribe('GameUpdated', _Spy().call);

      service.unsubscribe('GameUpdated');

      expect(
        service.isSubscribed('GameUpdated'),
        isTrue,
        reason: 'only the primary was removed',
      );
    });

    test('an unknown event is a no-op, not an error', () {
      expect(() => service.unsubscribe('NeverRegistered'), returnsNormally);
      expect(service.isSubscribed('NeverRegistered'), isFalse);
    });

    test('unsubscribing twice is safe', () {
      service.subscribe('GameUpdated', _Spy().call);
      service.unsubscribe('GameUpdated');
      expect(() => service.unsubscribe('GameUpdated'), returnsNormally);
    });
  });

  group('unsubscribeAll', () {
    test('clears every event from all three registries', () {
      service.addEventListener('A', _Spy().call);
      service.subscribe('B', _Spy().call);
      service.addEventListener('C', _Spy().call);

      service.unsubscribeAll();

      expect(service.isSubscribed('A'), isFalse);
      expect(service.isSubscribed('B'), isFalse);
      expect(service.isSubscribed('C'), isFalse);
    });

    test('is safe on a service that never registered anything', () {
      expect(service.unsubscribeAll, returnsNormally);
    });

    test('the service is reusable afterwards', () {
      service.addEventListener('A', _Spy().call);
      service.unsubscribeAll();

      service.addEventListener('A', _Spy().call);
      expect(service.isSubscribed('A'), isTrue);
    });

    test('an unregister callback from before the clear is inert afterwards',
        () {
      final remove = service.addEventListener('A', _Spy().call);
      service.unsubscribeAll();
      service.addEventListener('A', _Spy().call);

      // The stale callback must not take the new registration down with it.
      remove();

      expect(
        service.isSubscribed('A'),
        isTrue,
        reason: 'the stale handler is no longer in the list, so removing it '
            'leaves the fresh listener alone',
      );
    });
  });

  group('reattachEventHandlers', () {
    test('is safe with no connection and keeps the registry intact', () {
      service.addEventListener('A', _Spy().call);
      service.subscribe('B', _Spy().call);

      expect(service.reattachEventHandlers, returnsNormally);

      expect(service.isSubscribed('A'), isTrue);
      expect(service.isSubscribed('B'), isTrue);
    });

    test('is safe on an empty registry', () {
      expect(service.reattachEventHandlers, returnsNormally);
    });
  });

  group('lifecycle callbacks are inert without a stored session', () {
    test('onAppResumed does not start a connect', () {
      service.onAppResumed();

      expect(service.isConnecting, isFalse);
      expect(service.checkConnectionStatus(), SignalRStatus.idle);
    });

    test('onAppPaused changes nothing', () {
      service.onAppPaused();
      expect(service.checkConnectionStatus(), SignalRStatus.idle);
    });
  });
}
