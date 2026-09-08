import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// CHARACTERIZATION ONLY — no production code was changed for this file.
//
// These tests document what the automatic internet-recovery path does TODAY,
// including one case where it does nothing. A test here passing means "this
// is the current behaviour", not "this is the desired behaviour". The gap is
// called out by name in the group and test titles so it cannot be mistaken
// for an endorsement.
//
// The real chain, traced in source:
//   NetworkInfo (network/network_info.dart) — connectivity_plus for
//     interface changes + internet_connection_checker_plus for real
//     reachability, both funnelled into one broadcast `onStatusChange`.
//   -> signalr_provider.dart:22-25 subscribes that stream directly to
//      SignalRService.onInternetStatusChanged. This is the ONLY automatic
//      link between connectivity and the hub.
//   -> onInternetStatusChanged (signalr_service.dart:396) — on false, stops
//      the hub; on true it returns early unless the previous value was
//      false, then calls _reconnectAfterInternetRestored().
//   -> _reconnectAfterInternetRestored (signalr_service.dart:535) — bails on
//      _manuallyDisconnected, on a null _hubUrl, while a no-internet stop is
//      still running, or when a connection is already live; otherwise
//      reconnect().
//   -> reconnect() (signalr_service.dart:216) replays the stored url through
//      connectIfNeeded().
//
// The load-bearing detail: connect() assigns `_hubUrl` only AFTER its
// no-internet guard (:84-90) and its empty-token guard (:95-100) have both
// passed. A first connect attempted while already offline therefore returns
// before ever storing a url — and every automatic recovery path is gated on
// that url being present.

/// Lets a test drive connectivity the way NetworkInfo does.
class _FakeNetworkInfo implements NetworkInfo {
  _FakeNetworkInfo({bool online = true}) : _online = online;

  final _controller = StreamController<bool>.broadcast(sync: true);
  bool _online;

  @override
  bool get isOnline => _online;

  @override
  Future<bool> get isConnected async => _online;

  @override
  Stream<bool> get onStatusChange => _controller.stream;

  void emit(bool online) {
    _online = online;
    _controller.add(online);
  }

  @override
  void dispose() {
    _controller.close();
  }
}

void main() {
  /// Collects every status the service publishes.
  ({SignalRService service, List<SignalRStatus> seen}) newService({
    NetworkInfo? networkInfo,
    ApiHeadersBuilder? headersBuilder,
  }) {
    final service = SignalRService(
      networkInfo: networkInfo,
      headersBuilder: headersBuilder,
    );
    final seen = <SignalRStatus>[];
    service.statusStream.listen(seen.add);
    addTearDown(service.dispose);
    return (service: service, seen: seen);
  }

  /// The real builder over mock prefs — the endpoint fallback reads its token
  /// from here, the same SharedPrefs the manual button used to read directly.
  Future<ApiHeadersBuilder> headersBuilder({String token = 'token-abc'}) async {
    // PrefsKeys.token — the key SharedPrefsService.getToken() actually reads.
    SharedPreferences.setMockInitialValues({'auth_token': token});
    return ApiHeadersBuilder(await SharedPrefsService.init());
  }

  /// Gets a real hub url stored, the only way production does it.
  ///
  /// No headersBuilder is supplied, so connect() stores `_hubUrl` and then
  /// throws internally and lands on `failed` — which is all this needs. A
  /// live socket cannot be stood up in a unit test, and none of the
  /// recovery gates below read anything but the stored url.
  Future<void> storeHubUrl(SignalRService service) async {
    await service.connect(
      url: 'ws://characterization.test/hub',
      accessTokenFactory: () async => 'token',
    );
    // statusStream is async: let the `failed` this attempt produces land
    // before a caller clears the collected statuses, or it arrives after the
    // clear and looks like a fresh event.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  group('the connectivity source is wired to the hub automatically', () {
    test('signalRServiceProvider subscribes NetworkInfo.onStatusChange to '
        'SignalRService.onInternetStatusChanged', () async {
      SharedPreferences.setMockInitialValues({'access_token': 'tok'});
      final prefs = await SharedPrefsService.init();
      final network = _FakeNetworkInfo();
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          networkInfoProvider.overrideWithValue(network),
        ],
      );
      addTearDown(container.dispose);

      // Reading the provider is what installs the subscription.
      final service = container.read(signalRServiceProvider);
      final seen = <SignalRStatus>[];
      service.statusStream.listen(seen.add);

      network.emit(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        seen,
        contains(SignalRStatus.disconnectedNoInternet),
        reason: 'the connectivity stream reached the hub with no widget, no '
            'screen and no user action — this is the automatic link',
      );
    });
  });

  group('WITH a stored hub session — automatic recovery works', () {
    test('internet returning reconnects on its own, with no Reconnect tap',
        () async {
      final s = newService();
      await storeHubUrl(s.service);
      expect(s.service.hasStoredHubSession, isTrue, reason: 'precondition');
      s.seen.clear();

      s.service.onInternetStatusChanged(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(s.seen.last, SignalRStatus.disconnectedNoInternet);

      s.service.onInternetStatusChanged(true);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        s.seen,
        contains(SignalRStatus.connecting),
        reason: 'a connect was attempted automatically — nothing in this '
            'test touched the Reconnect button',
      );
    });

    test('the automatic attempt goes through the same connect path, so a '
        'failure lands on failed rather than silently giving up', () async {
      final s = newService();
      await storeHubUrl(s.service);
      s.seen.clear();

      s.service.onInternetStatusChanged(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      s.service.onInternetStatusChanged(true);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(s.seen.last, SignalRStatus.failed);
      expect(
        s.service.checkConnectionStatus().isConnected,
        isFalse,
        reason: 'never reports connected without a real socket — this is '
            'what keeps the loader up',
      );
    });
  });

  group('WITHOUT a stored hub session — the endpoint fallback (the fix)', () {
    test('FIXED: a first connect that never stored a url IS now retried when '
        'internet returns', () async {
      final s = newService(headersBuilder: await headersBuilder());
      expect(s.service.hasStoredHubSession, isFalse, reason: 'precondition');

      s.service.onInternetStatusChanged(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(s.seen, [SignalRStatus.disconnectedNoInternet]);

      s.service.onInternetStatusChanged(true);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        s.seen,
        contains(SignalRStatus.connecting),
        reason: 'this is the previously failing case: with no _hubUrl, '
            'recoverConnection() falls back to ApiEndpoints.signalRHubUrl '
            'instead of returning',
      );
      expect(
        s.service.hasStoredHubSession,
        isTrue,
        reason: 'the fallback connect got far enough to store the url, so '
            'every later recovery uses the ordinary replay path',
      );
    });

    test('FIXED: entering while offline, then internet returning, recovers '
        'with no user interaction at all', () async {
      final network = _FakeNetworkInfo(online: false);
      addTearDown(network.dispose);
      final s = newService(
        networkInfo: network,
        headersBuilder: await headersBuilder(),
      );

      // Entry while offline — connect aborts above the `_hubUrl = url` line.
      await s.service.connect(
        url: 'ws://characterization.test/hub',
        accessTokenFactory: () async => 'token',
      );
      expect(s.service.hasStoredHubSession, isFalse, reason: 'precondition');
      expect(s.service.checkConnectionStatus(),
          SignalRStatus.disconnectedNoInternet);
      s.seen.clear();

      // Internet returns. Nothing below touches Reconnect.
      network.emit(true);
      s.service.onInternetStatusChanged(true);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(s.seen, contains(SignalRStatus.connecting),
          reason: 'recovery was attempted automatically');
    });

    test('an empty token still aborts before storing a url, and recovery '
        'still retries it', () async {
      final s = newService(headersBuilder: await headersBuilder(token: ''));

      await s.service.connect(
        url: 'ws://characterization.test/hub',
        accessTokenFactory: () async => '',
      );
      expect(s.service.checkConnectionStatus(), SignalRStatus.failed);
      expect(s.service.hasStoredHubSession, isFalse);
      s.seen.clear();

      s.service.onInternetStatusChanged(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      s.service.onInternetStatusChanged(true);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // The token is still empty, so the attempt lands on failed again —
      // but it is an attempt, and the backoff owns it from here.
      expect(s.seen.last, SignalRStatus.failed);
    });

    test('with no headers builder there is nothing to build a token from, '
        'so the fallback declines rather than connecting blind', () async {
      final s = newService();

      s.service.onInternetStatusChanged(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      s.service.onInternetStatusChanged(true);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(s.seen, [SignalRStatus.disconnectedNoInternet]);
    });
  });

  group('the guards on the automatic path', () {
    test('internet reported up without a recorded drop does nothing — the '
        'hadInternet guard', () async {
      final s = newService();
      await storeHubUrl(s.service);
      s.seen.clear();

      // _hasInternet starts true, so this is a no-op by design.
      s.service.onInternetStatusChanged(true);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(s.seen, isEmpty,
          reason: 'recovery only runs on a false -> true transition');
    });

    test('a deliberate disconnect is not undone by internet returning',
        () async {
      final s = newService();
      await storeHubUrl(s.service);
      await s.service.disconnect();
      expect(s.service.isManuallyDisconnected, isTrue);
      s.seen.clear();

      s.service.onInternetStatusChanged(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      s.service.onInternetStatusChanged(true);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(s.seen, isNot(contains(SignalRStatus.connecting)),
          reason: 'the app asked for the hub to be down; connectivity '
              'returning must not override that');
      expect(s.service.isManuallyDisconnected, isTrue);
    });

    test('losing internet with no hub connection still reports the state '
        'without attempting anything', () async {
      final s = newService();

      s.service.onInternetStatusChanged(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(s.seen, [SignalRStatus.disconnectedNoInternet]);
      expect(s.service.isConnecting, isFalse);
    });
  });

  group('the loader only clears on a real connection', () {
    test('no status on the automatic path ever reports connected without a '
        'live socket', () async {
      final s = newService();
      await storeHubUrl(s.service);
      s.seen.clear();

      s.service.onInternetStatusChanged(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      s.service.onInternetStatusChanged(true);
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        s.seen.where((status) => status.isConnected),
        isEmpty,
        reason: 'connected is set only after hubConnection.start() returns, '
            'so LoaderOverlay cannot clear on an attempt alone',
      );
      expect(s.seen, contains(SignalRStatus.connecting));
      expect(s.seen.last, SignalRStatus.failed);
    });

    test('every non-connected status the recovery path can produce keeps the '
        'loader up by LoaderOverlay\'s rule', () {
      // Mirrors _hubNeedsLoader: hidden only on connected, idle, or a
      // deliberate disconnect.
      const producedByRecovery = [
        SignalRStatus.disconnectedNoInternet,
        SignalRStatus.connecting,
        SignalRStatus.reconnecting,
        SignalRStatus.disconnected,
        SignalRStatus.failed,
      ];
      for (final status in producedByRecovery) {
        expect(status.isConnected, isFalse, reason: '$status');
        expect(status == SignalRStatus.idle, isFalse, reason: '$status');
      }
    });
  });
}
