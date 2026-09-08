import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A hub that comes up is not news to the player. connectHub used to raise a
// SnackBar on both success paths — "Hub connected" after a real connect, and
// "Hub already connected" when there was nothing to do — which surfaced on
// every game entry, every reconnect and every internet recovery. The
// connection loader is the one place connection state belongs.
//
// Only those two are gone. The failure path, the return value, the caller's
// own onSuccess/onError and everything the SignalRService does are untouched,
// and each of those is asserted below rather than assumed.

class _FakeSignalRService extends SignalRService {
  _FakeSignalRService({this.connectSucceeds = true});

  bool connected = false;
  bool connectSucceeds;
  int connectCalls = 0;
  int recoverCalls = 0;

  @override
  bool get isConnected => connected;

  @override
  bool get hasLiveConnection => connected;

  @override
  Future<void> connect({
    required String url,
    Future<String> Function()? accessTokenFactory,
  }) async {
    connectCalls++;
    connected = connectSucceeds;
  }

  @override
  Future<void> connectIfNeeded({
    required String url,
    Future<String> Function()? accessTokenFactory,
  }) async {
    if (connected) {
      return;
    }
    await connect(url: url, accessTokenFactory: accessTokenFactory);
  }

  @override
  Future<void> recoverConnection() async {
    recoverCalls++;
    connected = connectSucceeds;
  }

  @override
  Future<void> reconnect() async {
    await recoverConnection();
  }

  @override
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) =>
      () {};

  @override
  void reattachEventHandlers() {}
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

/// A BaseState screen, so `connectHub` runs exactly as it does in the app.
class _HostScreen extends ConsumerStatefulWidget {
  const _HostScreen({required this.controller});

  final _HostController controller;

  @override
  ConsumerState<_HostScreen> createState() => _HostScreenState();
}

/// Lets a test drive `connectHub` and read back what it returned.
class _HostController {
  _HostScreenState? _state;

  Future<bool> connect({ErrorType error = ErrorType.none}) =>
      _state!.connectHub(
        error: error,
        onSuccess: () => successCallbacks++,
        onError: (_) => errorCallbacks++,
      );

  Future<void> reconnect() => _state!.reconnectHub();

  int successCallbacks = 0;
  int errorCallbacks = 0;
}

class _HostScreenState extends BaseState<_HostScreen> {
  @override
  bool get handleSignalRConnection => true;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  Widget buildPage(BuildContext context) => const Scaffold(
        body: Center(child: Text('phase')),
      );
}

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;
  late _HostController host;

  final strings = AppStrings.forLanguage(AppLanguage.english);

  Future<void> pumpApp(
    WidgetTester tester, {
    bool connectSucceeds = true,
    bool alreadyConnected = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'user_id': '47',
      'app_language': AppLanguage.english,
      'access_token': 'token-abc',
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService(connectSucceeds: connectSucceeds)
      ..connected = alreadyConnected;
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
        hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
      ],
    );
    addTearDown(container.dispose);
    host = _HostController();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => LoaderOverlay(child: child!),
          home: _HostScreen(controller: host),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Anything the player would actually see, whatever its wording.
  Finder anySnackBar() => find.byType(SnackBar);

  group('a successful connect says nothing', () {
    testWidgets('a fresh connect raises no SnackBar', (tester) async {
      await pumpApp(tester);

      final connected = await host.connect();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(connected, isTrue, reason: 'the return value is unchanged');
      expect(signalR.connectCalls, 1, reason: 'it really did connect');
      expect(anySnackBar(), findsNothing);
      expect(find.text(strings.hubConnected), findsNothing);
    });

    testWidgets('the caller\'s own onSuccess still runs', (tester) async {
      await pumpApp(tester);

      await host.connect();
      await tester.pump();

      expect(host.successCallbacks, 1,
          reason: 'only the Toast was removed from onSuccess');
    });

    testWidgets('an already-connected hub raises no SnackBar either',
        (tester) async {
      await pumpApp(tester, alreadyConnected: true);

      final connected = await host.connect();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(connected, isTrue);
      expect(signalR.connectCalls, 0, reason: 'nothing to do, as before');
      expect(host.successCallbacks, 1);
      expect(anySnackBar(), findsNothing);
      expect(find.text(strings.hubAlreadyConnected), findsNothing);
    });

    testWidgets('entering twice in a row stays silent both times',
        (tester) async {
      await pumpApp(tester);

      await host.connect();
      await tester.pump();
      await host.connect();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(anySnackBar(), findsNothing,
          reason: 'the second call takes the already-connected path');
      expect(host.successCallbacks, 2);
    });
  });

  group('a successful reconnect or recovery says nothing', () {
    testWidgets('reconnecting after a drop raises no SnackBar',
        (tester) async {
      await pumpApp(tester);
      await host.connect();
      await tester.pump();

      // The drop, then the reconnect.
      signalR.connected = false;
      await host.reconnect();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(signalR.connected, isTrue, reason: 'it really did reconnect');
      expect(anySnackBar(), findsNothing);
    });

    testWidgets('recovery after internet returns raises no SnackBar',
        (tester) async {
      await pumpApp(tester);
      await host.connect();
      await tester.pump();
      signalR.connected = false;

      // The same call the automatic internet-recovery path makes.
      await container.read(signalRServiceProvider).recoverConnection();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(signalR.recoverCalls, 1);
      expect(signalR.connected, isTrue);
      expect(anySnackBar(), findsNothing);
    });

    testWidgets('a connect that follows a recovery is silent too',
        (tester) async {
      await pumpApp(tester);
      signalR.connected = false;
      await container.read(signalRServiceProvider).recoverConnection();
      await tester.pump();

      await host.connect();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(anySnackBar(), findsNothing);
    });
  });

  group('failures are untouched', () {
    testWidgets('a failed connect still reports through the snack path',
        (tester) async {
      await pumpApp(tester, connectSucceeds: false);

      final connected = await host.connect(error: ErrorType.snack);
      await tester.pump();

      expect(connected, isFalse, reason: 'the return value is unchanged');
      expect(find.text(strings.hubConnectFailed), findsOneWidget,
          reason: 'only the success notification was removed');
      expect(host.errorCallbacks, 1);
      expect(host.successCallbacks, 0);
    });

    testWidgets('ErrorType.none still stays silent on failure',
        (tester) async {
      // The game entry path's setting — a failed connect must not put
      // anything over the screen being entered. Unchanged.
      await pumpApp(tester, connectSucceeds: false);

      final connected = await host.connect();
      await tester.pump();

      expect(connected, isFalse);
      expect(anySnackBar(), findsNothing);
      expect(host.errorCallbacks, 1);
    });

    testWidgets('a failure then a success: the failure shows, the success '
        'does not', (tester) async {
      await pumpApp(tester, connectSucceeds: false);

      await host.connect(error: ErrorType.snack);
      await tester.pump();
      expect(find.text(strings.hubConnectFailed), findsOneWidget);

      // Clear the failure SnackBar, then let the retry succeed.
      ScaffoldMessenger.of(
        tester.element(find.text('phase')),
      ).removeCurrentSnackBar();
      await tester.pump();
      signalR.connectSucceeds = true;

      await host.connect(error: ErrorType.snack);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(anySnackBar(), findsNothing,
          reason: 'nothing announces the recovery');
    });
  });

  group('unrelated notifications still work', () {
    testWidgets('showToast itself is not disabled', (tester) async {
      await pumpApp(tester);

      // Proves the assertions above are about connectHub, not about a
      // SnackBar mechanism that stopped working in this harness.
      tester
          .state<_HostScreenState>(find.byType(_HostScreen))
          .showToast('some other message');
      await tester.pump();

      expect(find.text('some other message'), findsOneWidget);
    });
  });
}
