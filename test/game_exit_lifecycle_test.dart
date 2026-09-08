import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Back -> LeaveGame -> route removal -> re-entry.
//
// The reproduction, traced in the audit and pinned here:
//   Navigator.pop() queues the pop observation while the route is still
//   _RouteLifecycle.popping, so RouteAware.didPopNext() fires with
//   GameControllerScreen STILL MOUNTED. PlayGame.clearGameData() ran
//   ref.invalidate(gameControllerProvider) there, which — with the dying
//   screen still watching it — rebuilt the controller to
//   GameSessionState.initial() (phase waiting), mounted a fresh WaitingScreen
//   inside the dying screen, and dispatched JoinRandomGame after the player
//   had left. It also sent a second LeaveGame('all').
//
// And because Navigator.pop() removes the topmost *present* route (a popping
// route is not present), any second pop during that ~300ms window removed the
// host page instead — an empty navigator, i.e. the black screen.
//
// The host below is a faithful stand-in for the debug launcher: RouteAware,
// calling the real PlayGame.clearGameData on didPopNext.

const _localId = '47';
const _opponentId = '211403';
const _interestIds = [88];

final _routeObserver = RouteObserver<PageRoute<dynamic>>();

typedef HubHandler = void Function(List<Object?>?);

class _FiringSignalRService extends SignalRService {
  final _handlers = <String, List<HubHandler>>{};

  /// Every invoke, in order — the wire log these tests assert against.
  final invocations = <({String method, List<Object?>? args})>[];

  bool connected = true;
  int connectCalls = 0;

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
    connected = true;
  }

  @override
  Future<void> connectIfNeeded({
    required String url,
    Future<String> Function()? accessTokenFactory,
  }) async {
    if (!connected) {
      await connect(url: url, accessTokenFactory: accessTokenFactory);
    }
  }

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    invocations.add((method: methodName, args: args));
    return connected;
  }

  @override
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) {
    final list = _handlers.putIfAbsent(eventName, () => []);
    list.add(handler);
    return () => list.remove(handler);
  }

  @override
  void reattachEventHandlers() {}

  void fire(String eventName, [List<Object?>? args]) {
    for (final handler
        in List.of(_handlers[eventName] ?? const <HubHandler>[])) {
      handler(args);
    }
  }

  List<String> get methods => [for (final i in invocations) i.method];

  int countOf(String method) => methods.where((m) => m == method).length;
}

class _FakeHubBindings extends PlayGameHubBindings {
  _FakeHubBindings(super.signalR);

  final _events = StreamController<GameHubEvent>.broadcast();

  @override
  Stream<GameHubEvent> get stream => _events.stream;

  void emit(String name, [Map<String, dynamic>? data]) =>
      _events.add(GameHubEvent(name: name, data: data));

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
    bool? loop = true,
    double? volume,
  }) async {}

  @override
  Future<void> playSfx(String asset, {String? package, double? volume}) async {}
}

/// The debug launcher's shape: RouteAware, calling the real
/// [PlayGame.clearGameData] on didPopNext, exactly as
/// home_launcher_page.dart does.
class _HostPage extends ConsumerStatefulWidget {
  const _HostPage();

  @override
  ConsumerState<_HostPage> createState() => _HostPageState();
}

class _HostPageState extends ConsumerState<_HostPage> with RouteAware {
  static int clearCalls = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      _routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    clearCalls++;
    unawaited(PlayGame.clearGameData(ref));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('home')),
      );
}

Map<String, dynamic> _roundGame() => {
      'id': 'g1',
      'status': 3,
      'type': 1,
      'groupId': 'grp',
      'currentTurn': _localId,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
      'currentQuestion': {
        'id': 1,
        'text': 'q1',
        'textEn': 'q1',
        'questionNumber': 1,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
    };

void main() {
  late ProviderContainer container;
  late _FiringSignalRService signalR;
  late _FakeHubBindings bindings;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() => _HostPageState.clearCalls = 0);

  Future<void> pumpHome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FiringSignalRService();
    bindings = _FakeHubBindings(signalR);
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider.overrideWithValue(bindings),
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [_routeObserver],
          home: const _HostPage(),
        ),
      ),
    );
    await tester.pump();
  }

  /// Pushes the real game route, public or private.
  Future<void> enterGame(WidgetTester tester, {bool private = false}) async {
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => private
              ? const GameControllerScreen(privateInterestIds: _interestIds)
              : const GameControllerScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The Android back gesture, through the real PopScope.
  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
  }

  /// Confirms the exit dialog if one is showing.
  Future<void> confirmExit(WidgetTester tester) async {
    final strings = PlayGameStrings.forLanguage(AppLanguage.english);
    // The dialog's button, not its label text: WaitingScreen renders its own
    // "Exit the game" copy behind the dialog on the waiting phase.
    final button = find.widgetWithText(GameButton, strings.exitTheGame);
    if (button.evaluate().isEmpty) {
      return;
    }
    await tester.tap(button);
    await tester.pump();
  }
  /// One full public exit: back, confirm, and let the transition finish.
  Future<void> leaveGame(WidgetTester tester) async {
    await pressBack(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await confirmExit(tester);
    await tester.pump();
  }

  Future<void> settleTransition(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  /// True while something sits above the host page — i.e. the game route is
  /// still there. False means exactly one route (the host) is left, which is
  /// black screen, and is asserted separately via find.text('home').
  bool gameRouteOnTop() => navigatorKey.currentState!.canPop();

  group('A. public Back: one leave, one pop, home survives', () {
    testWidgets('exactly one LeaveGame and one route removal', (tester) async {
      await pumpHome(tester);
      await enterGame(tester);
      // Move past waiting so the round PopScope path (the confirm dialog) is
      // the one exercised.
      bindings.emit(PlayGameHubEvents.gameStarted, _roundGame());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      signalR.invocations.clear();

      await leaveGame(tester);
      await settleTransition(tester);

      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 1,
          reason: 'the exit owner sends it; clearGameData no longer does');
      expect(signalR.invocations.single.args, ['all'],
          reason: 'the payload is unchanged');
      expect(find.byType(GameControllerScreen), findsNothing);
      expect(find.text('home'), findsOneWidget);
      expect(gameRouteOnTop(), isFalse, reason: "home, and nothing else");
      expect(_HostPageState.clearCalls, 1,
          reason: 'the launcher still gets its didPopNext');
    });
  });

  group('B. repeated Back cannot leave or pop twice', () {
    testWidgets('two back gestures in the same frame', (tester) async {
      await pumpHome(tester);
      await enterGame(tester);
      bindings.emit(PlayGameHubEvents.gameStarted, _roundGame());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      signalR.invocations.clear();

      await leaveGame(tester);
      // A second gesture while the route is still transitioning out.
      await tester.pump(const Duration(milliseconds: 100));
      await pressBack(tester);
      await settleTransition(tester);

      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 1);
      expect(find.text('home'), findsOneWidget);
      expect(gameRouteOnTop(), isFalse);
    });

    testWidgets('a leave attempt during the exit transition is a no-op',
        (tester) async {
      await pumpHome(tester);
      await enterGame(tester);
      bindings.emit(PlayGameHubEvents.gameStarted, _roundGame());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      signalR.invocations.clear();

      await leaveGame(tester);
      // Mid-transition: PlayerLeft naming me used to reach _leaveGame() and
      // pop again — which, with the game route already popping, removed
      // home.
      await tester.pump(const Duration(milliseconds: 100));
      signalR.fire(PlayGameHubEvents.playerLeft, [_localId, 'g1']);
      await tester.pump();
      await settleTransition(tester);

      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 1);
      expect(find.text('home'), findsOneWidget);
      expect(gameRouteOnTop(), isFalse, reason: 'home was never popped');
    });

    testWidgets('a descendant leaving mid-transition cannot pop home',
        (tester) async {
      // WaitingScreen's own leave path, triggered by a hub Error while the
      // game route is already popping. It used to call a bare
      // Navigator.pop() of its own — and a popping route is not "present",
      // so that pop removed the host page instead: the black screen.
      await pumpHome(tester);
      await enterGame(tester);
      expect(find.byType(WaitingScreen), findsOneWidget, reason: 'sanity');
      signalR.invocations.clear();

      await leaveGame(tester);
      await tester.pump(const Duration(milliseconds: 100));
      signalR.fire(PlayGameHubEvents.error, ['boom']);
      await tester.pump();
      await settleTransition(tester);

      expect(find.text('home'), findsOneWidget,
          reason: 'the host page is still there');
      expect(gameRouteOnTop(), isFalse,
          reason: 'exactly one route was removed, and it was the game');
      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 1,
          reason: 'and the descendant did not send a second LeaveGame');
    });
  });

  group('C. the dying screen dispatches nothing', () {
    testWidgets('no ghost JoinRandomGame after leaving', (tester) async {
      await pumpHome(tester);
      await enterGame(tester);
      expect(signalR.countOf(PlayGameHubEvents.joinRandomGame), 1,
          reason: 'the entry itself joins once');
      signalR.invocations.clear();

      await leaveGame(tester);
      await settleTransition(tester);
      // And well past every post-frame the dying screen could have queued.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(signalR.countOf(PlayGameHubEvents.joinRandomGame), 0,
          reason: 'clearGameData no longer rebuilds the dying screen into '
              'WaitingScreen');
      expect(signalR.countOf(PlayGameHubEvents.checkPlayerGame), 0);
      expect(signalR.countOf(PlayGameHubEvents.createPrivateGame), 0);
      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 1);
    });

    testWidgets('a recovery firing after leaving dispatches nothing',
        (tester) async {
      await pumpHome(tester);
      await enterGame(tester);
      final controller = container.read(gameControllerProvider.notifier);

      await leaveGame(tester);
      signalR.invocations.clear();

      // The connection recovery callback the old controller registered.
      await controller.onRecovered();
      await settleTransition(tester);

      expect(signalR.invocations, isEmpty,
          reason: 'a left session owns nothing on the hub');
    });

    testWidgets('the private entry dispatches nothing after leaving',
        (tester) async {
      await pumpHome(tester);
      await enterGame(tester, private: true);
      expect(signalR.countOf(PlayGameHubEvents.createPrivateGame), 1);
      signalR.invocations.clear();

      await pressBack(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await settleTransition(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(signalR.countOf(PlayGameHubEvents.createPrivateGame), 0);
      expect(signalR.countOf(PlayGameHubEvents.joinRandomGame), 0);
      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 1);
      expect(find.text('home'), findsOneWidget);
    });
  });

  group('D. re-entry starts clean', () {
    testWidgets('public: one JoinRandomGame for the second entry',
        (tester) async {
      await pumpHome(tester);
      await enterGame(tester);
      await leaveGame(tester);
      await settleTransition(tester);
      signalR.invocations.clear();

      await enterGame(tester);

      final session = container.read(gameControllerProvider);
      expect(session.result, isNull);
      expect(session.game, isNull);
      expect(session.me, isNull);
      expect(session.phase, GamePhase.waiting,
          reason: 'autoDispose gave the new entry a fresh controller');
      expect(signalR.countOf(PlayGameHubEvents.joinRandomGame), 1,
          reason: 'exactly one, from this entry only');
      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 0);
    });

    testWidgets('private: one CreatePrivateGame for the second entry',
        (tester) async {
      await pumpHome(tester);
      await enterGame(tester, private: true);
      await pressBack(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await settleTransition(tester);
      signalR.invocations.clear();

      await enterGame(tester, private: true);

      expect(signalR.countOf(PlayGameHubEvents.createPrivateGame), 1,
          reason: 'the previous entry\'s deferred ids cannot leak in');
      expect(container.read(gameControllerProvider).phase,
          GamePhase.lobbyPrivate);
    });

    testWidgets('the second entry does not immediately exit', (tester) async {
      await pumpHome(tester);
      await enterGame(tester);
      await leaveGame(tester);
      await settleTransition(tester);

      await enterGame(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.byType(GameControllerScreen), findsOneWidget,
          reason: 'it stays open');
      expect(gameRouteOnTop(), isTrue, reason: 'home plus the game');
    });
  });

  group('E. stale events after leaving change nothing', () {
    for (final event in [
      PlayGameHubEvents.playerLeft,
      PlayGameHubEvents.gameFinished,
      PlayGameHubEvents.gameOver,
      PlayGameHubEvents.gameTerminated,
      PlayGameHubEvents.error,
      PlayGameHubEvents.gameRestore,
    ]) {
      testWidgets('$event after the screen is gone', (tester) async {
        await pumpHome(tester);
        await enterGame(tester);
        await leaveGame(tester);
        await settleTransition(tester);
        signalR.invocations.clear();

        signalR.fire(event, [_localId, 'g1']);
        bindings.emit(event, {'arg0': _localId, 'arg1': 'g1'});
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        expect(signalR.invocations, isEmpty,
            reason: 'nothing dispatches for a session that is gone');
        expect(find.text('home'), findsOneWidget);
        expect(gameRouteOnTop(), isFalse, reason: 'no extra pop');
      });
    }
  });

  group('F. no black screen across repeated entries', () {
    testWidgets('Enter -> Back -> Enter -> Back -> Enter keeps home',
        (tester) async {
      await pumpHome(tester);

      for (var i = 0; i < 2; i++) {
        await enterGame(tester);
        expect(gameRouteOnTop(), isTrue,
            reason: 'home plus the game (round ${i + 1})');
        await leaveGame(tester);
        await settleTransition(tester);
        expect(find.text('home'), findsOneWidget,
            reason: 'home survives exit ${i + 1}');
        expect(gameRouteOnTop(), isFalse);
      }

      await enterGame(tester);

      expect(find.byType(GameControllerScreen), findsOneWidget);
      // Not built while an opaque route covers it — that is normal. What
      // matters is that a route is still *under* the game one: an emptied
      // navigator (the black screen) would leave nothing to pop back to.
      expect(gameRouteOnTop(), isTrue, reason: 'the navigator never emptied');
    });

    testWidgets('the same, private', (tester) async {
      await pumpHome(tester);

      for (var i = 0; i < 2; i++) {
        await enterGame(tester, private: true);
        await pressBack(tester);
        await tester.pump(const Duration(milliseconds: 400));
        await settleTransition(tester);
        expect(gameRouteOnTop(), isFalse,
            reason: 'exit ${i + 1} removed exactly one');
      }

      await enterGame(tester, private: true);
      expect(gameRouteOnTop(), isTrue);
    });
  });

  // B2. The event native gets when the game surface goes away. Emitted from
  // the single exit owner, GameControllerScreen._exitGame, so every path that
  // removes the route reports once and no path reports twice.
  //
  // This is the end-to-end half: a real Back gesture, a real host-initiated
  // leave, and real hub events, through the real screen. The bridge half —
  // that the engine forwards it to native as `onGameExited` — is in
  // game_engine_api_test.dart.
  group('H. onGameExited fires once per real exit', () {
    late int exits;

    /// Listens on the same handle PlayGameEngineHost reads. Called after
    /// pumpHome, since the container is built there.
    void watchExits() {
      exits = 0;
      final subscription = container
          .read(gameSessionHandleProvider)
          .onGameExited
          .listen((_) => exits++);
      addTearDown(subscription.cancel);
    }

    /// What PlayGameEngineHost.leaveGame does — the host-initiated path.
    void hostLeave() => container.read(gameSessionHandleProvider).leave();

    testWidgets('a Back exit reports exactly one', (tester) async {
      await pumpHome(tester);
      watchExits();
      await enterGame(tester);
      bindings.emit(PlayGameHubEvents.gameStarted, _roundGame());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(exits, 0, reason: 'a running game has not exited');

      await leaveGame(tester);
      await settleTransition(tester);

      expect(exits, 1);
      expect(find.byType(GameControllerScreen), findsNothing);
    });

    testWidgets('a host-initiated leaveGame reports exactly one',
        (tester) async {
      await pumpHome(tester);
      watchExits();
      await enterGame(tester);

      hostLeave();
      await settleTransition(tester);

      expect(exits, 1);
      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 1,
          reason: 'one leave, one event — the same single owner');
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('repeated leave requests still report one', (tester) async {
      await pumpHome(tester);
      watchExits();
      await enterGame(tester);

      hostLeave();
      hostLeave();
      hostLeave();
      await settleTransition(tester);

      expect(exits, 1, reason: 'the `_leaving` one-shot covers the event too');
    });

    testWidgets('Back and a host leave in the same frame report one',
        (tester) async {
      await pumpHome(tester);
      watchExits();
      await enterGame(tester);

      // Two different exit paths racing — the exact case the one-shot exists
      // for. They must not produce two events.
      await pressBack(tester);
      hostLeave();
      await settleTransition(tester);

      expect(exits, 1);
      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 1);
    });

    testWidgets('a finished game reports nothing until the route goes',
        (tester) async {
      await pumpHome(tester);
      watchExits();
      await enterGame(tester);
      bindings.emit(PlayGameHubEvents.gameStarted, _roundGame());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      // The server says the match is over and the result dialog comes up.
      // That is a finish, not an exit: the game route is still there.
      signalR.fire(PlayGameHubEvents.gameOver, [_localId, 'g1']);
      bindings.emit(
        PlayGameHubEvents.gameOver,
        {'arg0': _localId, 'arg1': 'g1'},
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(exits, 0,
          reason: 'game over is not an exit; the route has not been removed');
      expect(gameRouteOnTop(), isTrue);

      // Leaving afterwards is the exit, and reports once.
      hostLeave();
      await settleTransition(tester);

      expect(exits, 1);
    });

    testWidgets('round events during play report nothing', (tester) async {
      await pumpHome(tester);
      watchExits();
      await enterGame(tester);

      bindings.emit(PlayGameHubEvents.gameStarted, _roundGame());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      bindings.emit(PlayGameHubEvents.roundFinished, {'arg0': 'r1'});
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(exits, 0);
      expect(gameRouteOnTop(), isTrue);
    });

    testWidgets('two sessions report two exits, not one and not three',
        (tester) async {
      await pumpHome(tester);
      watchExits();

      await enterGame(tester);
      await leaveGame(tester);
      await settleTransition(tester);
      expect(exits, 1);

      await enterGame(tester);
      await leaveGame(tester);
      await settleTransition(tester);

      expect(exits, 2, reason: 'one per exit, not one per app run');
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a leave with no game running reports nothing',
        (tester) async {
      await pumpHome(tester);
      watchExits();

      hostLeave();
      await tester.pump();

      expect(exits, 0, reason: 'there was no route to remove');
    });
  });

  group('G. clearGameData keeps its own responsibilities', () {
    testWidgets('it still clears the launcher caches, and leaves the rest '
        'alone', (tester) async {
      await pumpHome(tester);
      await enterGame(tester);
      await leaveGame(tester);
      await settleTransition(tester);

      expect(_HostPageState.clearCalls, 1);
      expect(container.read(stickerCatalogProvider), isNull,
          reason: 'the caches it owns are still cleared');
      expect(container.read(playGameHubBindingsProvider).lastEvent, isNull);
      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 1,
          reason: 'and it no longer sends a LeaveGame of its own');
    });
  });
}
