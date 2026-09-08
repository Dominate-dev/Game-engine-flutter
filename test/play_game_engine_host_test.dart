import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The play_game side of the boundary: the engine asks for a flow, and the
// existing PlayGame entries + the existing single exit owner do the work.
//
// coreapp declares GameEngineHost and never depends on play_game, so this is
// the only place the two meet.

const _localId = '47';

class _FakeSignalRService extends SignalRService {
  final invocations = <String>[];
  bool connected = true;

  @override
  bool get isConnected => connected;

  @override
  bool get hasLiveConnection => connected;

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

  int countOf(String method) =>
      invocations.where((m) => m == method).length;
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
  Future<void> playSfx(String asset, {String? package, double? volume}) async {}

  @override
  Future<void> playMusic(
    String asset, {
    String? package,
    bool loop = true,
    double? volume,
  }) async {}
}

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;
  late GlobalKey<NavigatorState> navigatorKey;
  late PlayGameEngineHost host;

  Future<void> pumpHost(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider
            .overrideWithValue(_FakeHubBindings(signalR)),
        stickersRepositoryProvider.overrideWithValue(_FakeStickersRepository()),
        audioServiceProvider.overrideWithValue(_FakeAudioService()),
        networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
        hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
        signalRStatusProvider.overrideWith(
          (ref) => Stream<SignalRStatus>.value(SignalRStatus.connected),
        ),
      ],
    );
    addTearDown(container.dispose);

    navigatorKey = GlobalKey<NavigatorState>();
    host = PlayGameEngineHost(
      navigatorKey: navigatorKey,
      container: container,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // The engine's own navigator key — AppTheme.navigatorKey is null in
        // release, so host-driven navigation cannot use it.
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Center(child: Text('host'))),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('game flows reuse the existing PlayGame entries', () {
    testWidgets('joinRandomGame opens the waiting flow', (tester) async {
      await pumpHost(tester);

      unawaited(host.joinRandomGame());
      await settle(tester);

      expect(find.byType(GameControllerScreen), findsOneWidget);
      expect(signalR.countOf(PlayGameHubEvents.joinRandomGame), 1,
          reason: 'the existing connection-gated random flow, not a new one');
    });

    testWidgets('createPrivateGame forwards the host ids', (tester) async {
      await pumpHost(tester);

      unawaited(host.createPrivateGame([7, 91]));
      await settle(tester);

      final screen = tester.widget<GameControllerScreen>(
        find.byType(GameControllerScreen),
      );
      expect(screen.privateInterestIds, [7, 91],
          reason: 'no debug id such as [88] is invented here');
      expect(screen.privateGameCode, isNull);
      expect(signalR.countOf(PlayGameHubEvents.createPrivateGame), 1);
    });

    testWidgets('joinPrivateGame forwards the code', (tester) async {
      await pumpHost(tester);

      unawaited(host.joinPrivateGame('ZX9'));
      await settle(tester);

      final screen = tester.widget<GameControllerScreen>(
        find.byType(GameControllerScreen),
      );
      expect(screen.privateGameCode, 'ZX9');
      expect(screen.privateInterestIds, isNull);
      expect(signalR.countOf(PlayGameHubEvents.joinPrivateGame), 1);
    });
  });

  group('an entry completes when the flow is presented, not when it ends', () {
    /// Runs [entry] and reports whether its Future had completed by the time
    /// the flow was on screen — with the flow still open.
    Future<({bool completed, bool onScreen})> present(
      WidgetTester tester,
      Future<void> Function() entry,
    ) async {
      var completed = false;
      unawaited(entry().then((_) => completed = true));
      await settle(tester);
      return (
        completed: completed,
        onScreen: find.byType(GameControllerScreen).evaluate().isNotEmpty,
      );
    }

    for (final flow in <({String name, Future<void> Function() Function() go})>[
      (name: 'joinRandomGame', go: () => () => host.joinRandomGame()),
      (name: 'createPrivateGame', go: () => () => host.createPrivateGame([7])),
      (name: 'joinPrivateGame', go: () => () => host.joinPrivateGame('ZX9')),
    ]) {
      testWidgets('${flow.name} answers once its flow is mounted',
          (tester) async {
        await pumpHost(tester);

        final result = await present(tester, flow.go());

        expect(result.onScreen, isTrue, reason: 'sanity: the flow is up');
        expect(
          result.completed,
          isTrue,
          reason: '${flow.name} must answer the host when the flow is on '
              'screen — awaiting Navigator.push held the reply until the '
              'player left the game',
        );
      });

      testWidgets('${flow.name} answers again on a warm second entry',
          (tester) async {
        await pumpHost(tester);

        final first = await present(tester, flow.go());
        expect(first.completed, isTrue, reason: 'sanity: first entry');
        await host.leaveGame();
        await settle(tester);
        expect(find.byType(GameControllerScreen), findsNothing,
            reason: 'sanity: back to idle between entries');

        final second = await present(tester, flow.go());

        expect(second.onScreen, isTrue);
        expect(
          second.completed,
          isTrue,
          reason: 'a repeated entry on a warm engine answers the same way',
        );
      });
    }

    testWidgets('the reply does not wait for the game to end', (tester) async {
      await pumpHost(tester);

      var completed = false;
      unawaited(host.joinRandomGame().then((_) => completed = true));
      await settle(tester);

      expect(completed, isTrue);
      expect(host.isGameActive, isTrue,
          reason: 'the game is still running when the host was answered');
    });

    testWidgets('a host entry raises no visible route transition',
        (tester) async {
      await pumpHost(tester);

      unawaited(host.joinRandomGame());
      // One frame only: with a zero-duration transition the flow is fully
      // there, not sliding in.
      await tester.pump();
      await tester.pump();

      final route = ModalRoute.of(
        tester.element(find.byType(GameControllerScreen)),
      )!;
      expect(route.transitionDuration, Duration.zero);
      expect(route.animation?.value, 1.0,
          reason: 'already arrived on the first frame it exists');
    });
  });

  group('isGameActive tracks the live game', () {
    testWidgets('false before entry, true during, false after',
        (tester) async {
      await pumpHost(tester);
      expect(host.isGameActive, isFalse);

      unawaited(host.joinRandomGame());
      await settle(tester);
      expect(host.isGameActive, isTrue);

      await host.leaveGame();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(host.isGameActive, isFalse);
    });
  });

  group('leave uses the existing single exit owner', () {
    testWidgets('one LeaveGame, one route removed, host page survives',
        (tester) async {
      await pumpHost(tester);
      unawaited(host.joinRandomGame());
      await settle(tester);
      signalR.invocations.clear();

      await host.leaveGame();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 1);
      expect(find.byType(GameControllerScreen), findsNothing);
      expect(find.text('host'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isFalse);
    });

    testWidgets('repeated leaveGame does not duplicate LeaveGame',
        (tester) async {
      await pumpHost(tester);
      unawaited(host.joinRandomGame());
      await settle(tester);
      signalR.invocations.clear();

      await host.leaveGame();
      await host.leaveGame();
      await host.leaveGame();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 1,
          reason: 'the single exit owner is one-shot');
      expect(find.text('host'), findsOneWidget);
    });

    testWidgets('leaveGame with no game running is a no-op', (tester) async {
      await pumpHost(tester);

      await host.leaveGame();
      await tester.pump();

      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 0);
      expect(find.text('host'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isFalse,
          reason: 'nothing was popped');
    });
  });

  group('no navigator yet', () {
    testWidgets('a flow requested before the tree exists is ignored',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPrefsService.init();
      final bare = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(bare.dispose);
      final orphan = PlayGameEngineHost(
        navigatorKey: GlobalKey<NavigatorState>(),
        container: bare,
      );

      await orphan.joinRandomGame();
      await orphan.createPrivateGame([1]);
      await orphan.joinPrivateGame('x');
      await orphan.leaveGame();

      expect(orphan.isGameActive, isFalse);
    });
  });
}
