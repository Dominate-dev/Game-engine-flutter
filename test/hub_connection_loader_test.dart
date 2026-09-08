import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The connection loader is the single source of truth for a hub drop.
//
// Audited before changing anything; what the code actually does:
//   - LoaderOverlay (coreapp/presentation/widgets/loader_overlay.dart) is
//     mounted once at the app root (lib/main.dart:51, MaterialApp.builder), so
//     it sits above every route and every game phase.
//   - Its connection state comes from signalRStatusProvider, a StreamProvider
//     over SignalRService.statusStream — the same stream BaseState listens to.
//   - Reconnect calls SignalRService.reconnect(), which replays the stored hub
//     url through connectIfNeeded(); with no stored url it no-ops, so the
//     overlay falls back to connectIfNeeded(ApiEndpoints.signalRHubUrl).
//
// What was wrong, and what these tests pin:
//   1. The loader was gated on _hubWasConnected — it only appeared if the hub
//      had connected at least once. A first connect that failed, or one
//      aborted with no internet, showed no loader at all.
//   2. A real drop and a deliberate disconnect() both report
//      SignalRStatus.disconnected, so the loader needs the service's own
//      _manuallyDisconnected to tell them apart.
//   3. Losing internet raised BaseState's no-internet toast on top of the
//      loader — two competing reports of one event.
//   4. Reconnect had no in-flight guard.

/// Drives status exactly the way the real service does — through the same
/// broadcast stream signalRStatusProvider reads.
class _FakeSignalRService extends SignalRService {
  _FakeSignalRService();

  // sync so a status set in a test reaches signalRStatusProvider before the
  // next pump, instead of trailing a frame behind it.
  final _status = StreamController<SignalRStatus>.broadcast(sync: true);
  final connectCalls = <String>[];

  SignalRStatus _current = SignalRStatus.idle;
  bool _manual = false;
  bool _stored = false;

  /// Completes a pending reconnect on demand, so a second tap can be made
  /// while the first is still in flight.
  Completer<void>? pending;

  @override
  Stream<SignalRStatus> get statusStream => _status.stream;

  @override
  SignalRStatus checkConnectionStatus() => _current;

  @override
  bool get isManuallyDisconnected => _manual;

  @override
  bool get hasStoredHubSession => _stored;

  @override
  bool get isConnected => _current == SignalRStatus.connected;

  void emit(SignalRStatus status, {bool manual = false}) {
    _current = status;
    _manual = manual;
    _status.add(status);
  }

  /// Marks a hub url as stored, as a first successful connect would.
  void storeSession() => _stored = true;

  @override
  Future<void> reconnect() async {
    connectCalls.add('reconnect');
    _manual = false;
    final gate = pending;
    if (gate != null) {
      await gate.future;
    }
  }

  /// Mirrors the real branch so the button's two outcomes stay observable.
  @override
  Future<void> recoverConnection() async {
    if (_stored) {
      await reconnect();
      return;
    }
    await connectIfNeeded(url: 'endpoint', accessTokenFactory: null);
  }

  @override
  Future<void> connectIfNeeded({
    required String url,
    Future<String> Function()? accessTokenFactory,
  }) async {
    connectCalls.add('connectIfNeeded:$url');
    _manual = false;
    final gate = pending;
    if (gate != null) {
      await gate.future;
    }
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
  Future<void> dispose() async {
    await _status.close();
  }
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

/// A minimal BaseState screen, standing in for whatever phase is on screen.
class _HostScreen extends ConsumerStatefulWidget {
  const _HostScreen({this.label = 'phase'});

  final String label;

  @override
  ConsumerState<_HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends BaseState<_HostScreen> {
  @override
  bool get handleSignalRConnection => true;

  @override
  Widget buildPage(BuildContext context) => Scaffold(
        body: Center(child: Text(widget.label)),
      );
}

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;
  late StreamController<bool> internet;

  Future<void> newContainer() async {
    SharedPreferences.setMockInitialValues({
      'user_id': '47',
      'app_language': AppLanguage.english,
      'access_token': 'token-abc',
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    internet = StreamController<bool>.broadcast();
    addTearDown(internet.close);
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
        hasInternetProvider.overrideWith((ref) => internet.stream),
      ],
    );
    addTearDown(container.dispose);
    // statusStream is a broadcast controller: events emitted before anything
    // listens are dropped. Hold the subscription open from the start so a
    // status set before the first frame is not lost by the harness.
    final sub = container.listen(signalRStatusProvider, (_, __) {});
    addTearDown(sub.close);
  }

  /// Mounts the app the way main.dart does: LoaderOverlay wrapping the route.
  Future<void> pumpApp(
    WidgetTester tester, {
    String label = 'phase',
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => LoaderOverlay(child: child!),
          home: _HostScreen(label: label),
        ),
      ),
    );
    // Two frames: signalRStatusProvider's subscription to statusStream is
    // attached after the first build, and statusStream is a broadcast
    // controller — anything emitted before the listener exists is dropped.
    await tester.pump();
    await tester.pump();
  }

  Finder loader() => find.byType(ConnectionLoader);
  Finder reconnectButton() => find.widgetWithText(
        GameButton,
        AppStrings.forLanguage(AppLanguage.english).reconnect,
      );

  /// The loader only offers Reconnect after ConnectionLoader.retryAfter, so a
  /// tap test has to get past that existing delay first.
  Future<void> revealReconnect(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
  }

  group('loader visibility follows the real hub status', () {
    testWidgets('idle — nothing has tried to connect, so no loader',
        (tester) async {
      await newContainer();
      await pumpApp(tester);

      expect(loader(), findsNothing,
          reason: 'the app before a game is entered has no hub session');
    });

    testWidgets('connected — no loader, the screen underneath is untouched',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.emit(SignalRStatus.connected);
      await tester.pump();

      expect(loader(), findsNothing);
      expect(find.text('phase'), findsOneWidget);
    });

    testWidgets('disconnected — loader visible', (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.emit(SignalRStatus.connected);
      await tester.pump();
      signalR.emit(SignalRStatus.disconnected);
      await tester.pump();

      expect(loader(), findsOneWidget);
    });

    testWidgets('never connected at all — a failed first connect still shows '
        'the loader', (tester) async {
      await newContainer();
      await pumpApp(tester);
      // No `connected` ever emitted: this is the case the old
      // _hubWasConnected gate silently swallowed.
      signalR.emit(SignalRStatus.failed);
      await tester.pump();

      expect(
        loader(),
        findsOneWidget,
        reason: 'a hub that never came up is as unusable as one that dropped',
      );
    });

    testWidgets('disconnectedNoInternet without a prior connect shows the '
        'loader', (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.emit(SignalRStatus.disconnectedNoInternet);
      await tester.pump();

      expect(loader(), findsOneWidget);
    });

    testWidgets('connecting and reconnecting both keep the loader up',
        (tester) async {
      await newContainer();
      await pumpApp(tester);

      signalR.emit(SignalRStatus.connecting);
      await tester.pump();
      expect(loader(), findsOneWidget);

      signalR.emit(SignalRStatus.reconnecting);
      await tester.pump();
      expect(loader(), findsOneWidget);
    });

    testWidgets('a deliberate disconnect is not a connection loss',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.emit(SignalRStatus.connected);
      await tester.pump();
      signalR.emit(SignalRStatus.disconnected, manual: true);
      await tester.pump();

      expect(
        loader(),
        findsNothing,
        reason: 'disconnect() reports the same status a real drop does — '
            'isManuallyDisconnected is what separates them',
      );
    });

    testWidgets('the loader blocks interaction with the screen underneath',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.emit(SignalRStatus.disconnected);
      await tester.pump();

      expect(
        find.descendant(
          of: loader(),
          matching: find.byType(ModalBarrier),
        ),
        findsOneWidget,
        reason: 'the existing design covers and blocks, as intended',
      );
    });
  });

  group('the loader is independent of the current game phase', () {
    for (final phase in ['waiting', 'lobby', 'wdyk', 'auction', 'finish']) {
      testWidgets('a drop while showing "$phase" still raises the loader',
          (tester) async {
        await newContainer();
        await pumpApp(tester, label: phase);
        signalR.emit(SignalRStatus.connected);
        await tester.pump();

        signalR.emit(SignalRStatus.disconnected);
        await tester.pump();

        expect(loader(), findsOneWidget);
        expect(find.text(phase), findsOneWidget,
            reason: 'the game UI may remain underneath');
      });
    }

    testWidgets('it survives a route change while still disconnected',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.emit(SignalRStatus.disconnected);
      await tester.pump();
      expect(loader(), findsOneWidget);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const _HostScreen(label: 'next'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('next'), findsOneWidget);
      expect(
        loader(),
        findsOneWidget,
        reason: 'LoaderOverlay is above the Navigator, not inside a route',
      );
    });
  });

  group('reconnect performs the real hub operation', () {
    testWidgets('tapping Reconnect calls SignalRService.reconnect()',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.storeSession();
      signalR.emit(SignalRStatus.disconnected);
      await tester.pump();
      await revealReconnect(tester);

      expect(reconnectButton(), findsOneWidget);
      await tester.tap(reconnectButton());
      await tester.pump();

      expect(signalR.connectCalls, ['reconnect'],
          reason: 'the real service call, not a local UI flag');
    });

    testWidgets('with no stored hub url it falls back to a real connect',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      // hasStoredHubSession stays false — a connect that aborted before
      // storing a url. reconnect() alone would no-op here.
      signalR.emit(SignalRStatus.disconnectedNoInternet);
      await tester.pump();
      await revealReconnect(tester);

      await tester.tap(reconnectButton());
      await tester.pump();

      expect(signalR.connectCalls, hasLength(1));
      expect(signalR.connectCalls.single, startsWith('connectIfNeeded:'),
          reason: 'the button must not be dead before the first connect');
    });

    testWidgets('the loader stays visible while reconnecting', (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.storeSession();
      signalR.emit(SignalRStatus.disconnected);
      await tester.pump();
      await revealReconnect(tester);

      signalR.pending = Completer<void>();
      await tester.tap(reconnectButton());
      await tester.pump();

      expect(loader(), findsOneWidget, reason: 'still not connected');

      signalR.pending!.complete();
      await tester.pump();
    });

    testWidgets('duplicate taps while one reconnect is in flight are ignored',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.storeSession();
      signalR.emit(SignalRStatus.disconnected);
      await tester.pump();
      await revealReconnect(tester);

      signalR.pending = Completer<void>();
      await tester.tap(reconnectButton());
      await tester.pump();
      await tester.tap(reconnectButton());
      await tester.pump();
      await tester.tap(reconnectButton());
      await tester.pump();

      expect(signalR.connectCalls, hasLength(1),
          reason: 'three taps, one hub request');

      signalR.pending!.complete();
      await tester.pump();
    });

    testWidgets('a later tap is allowed once the first attempt finished',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.storeSession();
      signalR.emit(SignalRStatus.disconnected);
      await tester.pump();
      await revealReconnect(tester);

      await tester.tap(reconnectButton());
      await tester.pump();
      await tester.tap(reconnectButton());
      await tester.pump();

      expect(signalR.connectCalls, hasLength(2),
          reason: 'the guard releases, it does not latch');
    });

    testWidgets('a successful reconnect removes the loader automatically',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.storeSession();
      signalR.emit(SignalRStatus.disconnected);
      await tester.pump();
      expect(loader(), findsOneWidget);
      await revealReconnect(tester);

      await tester.tap(reconnectButton());
      await tester.pump();
      signalR.emit(SignalRStatus.connected);
      await tester.pumpAndSettle();

      expect(loader(), findsNothing,
          reason: 'driven by the hub status, not by the tap');
    });
  });

  group('internet loss shows the loader and no toast', () {
    testWidgets('losing internet with a live hub raises no SnackBar',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.emit(SignalRStatus.connected);
      await tester.pump();

      internet.add(true);
      await tester.pump();
      internet.add(false);
      await tester.pump();
      // The hub follows the internet down, as the service does on
      // onInternetStatusChanged.
      signalR.emit(SignalRStatus.disconnectedNoInternet);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(loader(), findsOneWidget, reason: 'the loader is the report');
      expect(find.byType(SnackBar), findsNothing,
          reason: 'no competing toast for the same event');
      expect(
        find.text(AppStrings.forLanguage(AppLanguage.english).noInternet),
        findsNothing,
      );
    });

    testWidgets('internet returning and the hub reconnecting removes the '
        'loader', (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.emit(SignalRStatus.connected);
      await tester.pump();
      internet.add(true);
      await tester.pump();

      internet.add(false);
      signalR.emit(SignalRStatus.disconnectedNoInternet);
      await tester.pump();
      expect(loader(), findsOneWidget);

      internet.add(true);
      signalR.emit(SignalRStatus.connected);
      await tester.pumpAndSettle();

      expect(loader(), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('with no hub session the existing no-internet toast is kept',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      // status stays idle — nothing has connected, so nothing else speaks
      // for this screen.
      internet.add(true);
      await tester.pump();
      internet.add(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(loader(), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget,
          reason: 'pre-existing behaviour outside a hub session is preserved');
    });
  });

  group('the connected flow is unchanged', () {
    testWidgets('a connected hub leaves the screen fully interactive',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.emit(SignalRStatus.connected);
      await tester.pump();

      expect(loader(), findsNothing);
      // Scoped to the loader: MaterialApp's own Navigator always has a
      // ModalBarrier of its own, unrelated to this overlay.
      expect(
        find.descendant(of: loader(), matching: find.byType(ModalBarrier)),
        findsNothing,
      );
      expect(find.text('phase'), findsOneWidget);
    });

    testWidgets('a manual showConnectionLoader() still works independently',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.emit(SignalRStatus.connected);
      await tester.pump();
      expect(loader(), findsNothing);

      container.read(connectionLoaderVisibleProvider.notifier).show();
      await tester.pump();
      expect(loader(), findsOneWidget,
          reason: 'the explicit provider path is still ORed in');

      container.read(connectionLoaderVisibleProvider.notifier).hide();
      await tester.pump();
      expect(loader(), findsNothing);
    });

    testWidgets('the base loader and the connection loader coexist',
        (tester) async {
      await newContainer();
      await pumpApp(tester);
      signalR.emit(SignalRStatus.disconnected);
      container.read(loaderVisibleProvider.notifier).show();
      await tester.pump();

      expect(find.byType(BaseLoader), findsOneWidget);
      expect(loader(), findsOneWidget);
    });
  });
}
