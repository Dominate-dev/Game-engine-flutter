import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A1 — the GameEngine guarantees a hub connection on entry.
//
// GameControllerScreen is the entry point (PlayGame.openWaiting pushes it,
// and it hosts every phase from Waiting onward). The native host may or may
// not have connected first, so entry connects when nothing is live and
// reuses whatever is live otherwise.
//
// `hasLiveConnection` is `isConnected || isConnecting`, so the connected and
// connecting cases are both covered by the same guard — these fakes report
// those states directly rather than driving a real socket.

const _localId = '47';

class _FakeSignalRService extends SignalRService {
  _FakeSignalRService({
    this.connected = false,
    this.connecting = false,
  });

  bool connected;
  bool connecting;

  int connectCalls = 0;
  final invocations = <String>[];

  @override
  bool get isConnected => connected;

  @override
  bool get isConnecting => connecting;

  @override
  Future<void> connectIfNeeded({
    required String url,
    Future<String> Function()? accessTokenFactory,
  }) async {
    connectCalls++;
    // Mirrors the real service: a connect attempt that cannot complete
    // leaves the service not-connected rather than throwing.
    if (shouldConnectSucceed) {
      connected = true;
    }
  }

  bool shouldConnectSucceed = true;

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    invocations.add(methodName);
    return connected;
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

class _FakeHubBindings extends PlayGameHubBindings {
  _FakeHubBindings(super.signalR);

  final _events = StreamController<GameHubEvent>.broadcast();

  @override
  Stream<GameHubEvent> get stream => _events.stream;

  @override
  void bindAll() {}

  @override
  void bindEvents(Iterable<String> eventNames) {}

  @override
  void dispose() {
    _events.close();
  }
}

class _FakeStickersRepository implements StickersRepository {
  @override
  Future<Result<StickerPage>> getStickerGroups(
    StickerFilterParams params,
  ) async =>
      Result.success(const StickerPage(items: [], pageIndex: 0, pageSize: 20));

  @override
  Future<Result<bool>> payStickerGroup(int id) async => Result.success(true);
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

class _FakeAudioService extends AudioService {
  @override
  Future<void> start(
    String asset, {
    AudioSourceType type = AudioSourceType.sfx,
    String? package,
    bool? loop,
    double? volume,
  }) async {}

  @override
  Future<void> playMusic(
    String asset, {
    String? package,
    bool loop = true,
    double? volume,
  }) async {}

  @override
  Future<void> playSfx(String asset, {String? package, double? volume}) async {}
}

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;
  late GlobalKey<NavigatorState> navigatorKey;

  /// Enters the GameEngine the way production does — pushing the screen
  /// PlayGame.openWaiting pushes — with the hub in the given state.
  Future<void> enterGameEngine(
    WidgetTester tester, {
    required _FakeSignalRService service,
    String? storedToken = 'a-token',
  }) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
      if (storedToken != null) 'auth_token': storedToken,
    });
    final prefs = await SharedPrefsService.init();
    signalR = service;
    navigatorKey = GlobalKey<NavigatorState>();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider.overrideWithValue(_FakeHubBindings(signalR)),
        stickersRepositoryProvider.overrideWithValue(_FakeStickersRepository()),
        audioServiceProvider.overrideWithValue(_FakeAudioService()),
        networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
        hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
        signalRStatusProvider.overrideWith(
          (ref) => Stream<SignalRStatus>.value(
            service.isConnected
                ? SignalRStatus.connected
                : SignalRStatus.disconnected,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const _HomePlaceholder(),
        ),
      ),
    );
    await tester.pump();

    unawaited(

      navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const GameControllerScreen()),
    ));
    // initState + the post-frame callback that performs the connect.
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    '1. entering with no connection triggers exactly one connect',
    (tester) async {
      await enterGameEngine(
        tester,
        service: _FakeSignalRService(),
      );

      expect(signalR.connectCalls, 1);
      expect(signalR.isConnected, isTrue);
    },
  );

  testWidgets(
    '2. entering while already connected reuses it — no duplicate connect',
    (tester) async {
      await enterGameEngine(
        tester,
        service: _FakeSignalRService(connected: true),
      );

      expect(signalR.connectCalls, 0);
    },
  );

  testWidgets(
    '3. entering while a connect is already in flight does not start '
    'another one',
    (tester) async {
      await enterGameEngine(
        tester,
        service: _FakeSignalRService(connecting: true),
      );

      expect(signalR.connectCalls, 0);
    },
  );

  testWidgets(
    '4. a failed connect leaves the screen usable and raises no modal — the '
    "service's own retry/status handling is what owns the failure",
    (tester) async {
      await enterGameEngine(
        tester,
        service: _FakeSignalRService()..shouldConnectSucceed = false,
      );

      expect(signalR.connectCalls, 1, reason: 'attempted once');
      expect(signalR.isConnected, isFalse);
      expect(
        find.byType(ShowDialogGame),
        findsNothing,
        reason: 'no error dialog over the screen being entered',
      );
      expect(find.byType(GameControllerScreen), findsOneWidget);
    },
  );

  testWidgets(
    '5. a failed connect is not retried in a loop by the entry path itself',
    (tester) async {
      await enterGameEngine(
        tester,
        service: _FakeSignalRService()..shouldConnectSucceed = false,
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(
        signalR.connectCalls,
        1,
        reason: 'entry connects once; retry belongs to SignalRService',
      );
    },
  );

  testWidgets(
    '6. entering does not disturb the hub-event binding lifecycle',
    (tester) async {
      await enterGameEngine(
        tester,
        service: _FakeSignalRService(connected: true),
      );

      // The waiting phase still dispatches its join through the hub, which
      // is what proves the screen came up wired as before.
      await tester.pump();
      expect(
        signalR.invocations,
        contains(PlayGameHubEvents.joinRandomGame),
      );
    },
  );

  testWidgets(
    '7. re-entering after leaving connects again when the hub went down',
    (tester) async {
      final service = _FakeSignalRService();
      await enterGameEngine(tester, service: service);
      expect(service.connectCalls, 1);

      navigatorKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      service.connected = false;
      unawaited(
        navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const GameControllerScreen()),
      ));
      await tester.pump();
      await tester.pump();

      expect(service.connectCalls, 2, reason: 'each entry guarantees it');
    },
  );
}
