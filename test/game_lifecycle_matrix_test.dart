import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/features/games/domain/repositories/game_repository.dart';
import 'package:play_game/features/games/presentation/providers/game_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Leave one game, start another — every combination of entry type.
//
// The engine runs behind a cached FlutterEngine, so the controller is not
// guaranteed to be rebuilt between entries. Everything an entry claims —
// `_didCreatePrivateGame`, `_didJoinPrivateGame`, `_didJoinRandom`,
// `_leftGame`, `_pendingPrivateInterestIds`, the session itself — therefore
// has to be released or re-established by the *next* entry rather than by
// disposal. This file walks the real screens through those transitions and
// checks, at every one, that nothing of the previous game is still holding on.
//
// The harness is game_exit_lifecycle_test.dart's, with one correction: there,
// screen listeners (`signalR.fire`) and the controller stream
// (`bindings.emit`) are fed separately, so a test can silently exercise only
// half the app. Here the fake bindings register on the fake service exactly as
// PlayGameHubBindings does, so one `fire()` reaches both — which is what the
// PlayerLeft -> GameFinished bug turned on.

const _localId = '47';
const _opponentId = '211403';
const _interestIds = [88];

final _routeObserver = RouteObserver<PageRoute<dynamic>>();

/// Event names more than one listener carries, so a leaked subscription
/// would show up as a growing count.
const _watchedEvents = <String>[
  PlayGameHubEvents.gameUpdated,
  PlayGameHubEvents.playerLeft,
  PlayGameHubEvents.gameRestore,
  PlayGameHubEvents.gameStarted,
];

/// The highest listener count seen so far in the current test.
final _listenerHighWater = <String, int>{};

typedef HubHandler = void Function(List<Object?>?);

/// How a game is entered. The three real entry points of
/// [GameControllerScreen], and the only three there are.
enum _Entry {
  public,
  privateCreate,
  privateJoin;

  bool get isPrivate => this != _Entry.public;

  String get label => switch (this) {
        _Entry.public => 'Normal',
        _Entry.privateCreate => 'Private Create',
        _Entry.privateJoin => 'Private Join',
      };

  /// The single hub method this entry is expected to dispatch.
  String get dispatch => switch (this) {
        _Entry.public => PlayGameHubEvents.joinRandomGame,
        _Entry.privateCreate => PlayGameHubEvents.createPrivateGame,
        _Entry.privateJoin => PlayGameHubEvents.joinPrivateGame,
      };

  /// The event the server answers that dispatch with.
  String get answer => switch (this) {
        _Entry.public => PlayGameHubEvents.gameUpdated,
        _Entry.privateCreate => PlayGameHubEvents.gameCreated,
        _Entry.privateJoin => PlayGameHubEvents.gameJoined,
      };
}

class _FiringSignalRService extends SignalRService {
  final _handlers = <String, List<HubHandler>>{};

  /// Every invoke, in order — the wire log these tests assert against.
  final invocations = <({String method, List<Object?>? args})>[];

  bool connected = true;

  @override
  bool get isConnected => connected;

  @override
  bool get hasLiveConnection => connected;

  @override
  Future<void> connect({
    required String url,
    Future<String> Function()? accessTokenFactory,
  }) async {
    connected = true;
  }

  @override
  Future<void> connectIfNeeded({
    required String url,
    Future<String> Function()? accessTokenFactory,
  }) async {
    connected = true;
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

  /// The hub delivering one event to everything listening for it.
  void fire(String eventName, [List<Object?>? args]) {
    for (final handler
        in List.of(_handlers[eventName] ?? const <HubHandler>[])) {
      handler(args);
    }
  }

  /// How many live listeners a name has — the duplicate-subscription check.
  int handlerCountFor(String eventName) => _handlers[eventName]?.length ?? 0;

  List<String> get methods => [for (final i in invocations) i.method];

  int countOf(String method) => methods.where((m) => m == method).length;
}

/// The real bindings' behaviour: subscribe on the service, republish as
/// [GameHubEvent] on the stream the controller listens to.
class _WiredHubBindings extends PlayGameHubBindings {
  _WiredHubBindings(this._signalR) : super(_signalR);

  final _FiringSignalRService _signalR;
  final _events = StreamController<GameHubEvent>.broadcast();
  final _bound = <String>{};

  @override
  Stream<GameHubEvent> get stream => _events.stream;

  @override
  void bindAll() => bindEvents(PlayGameHubEvents.lifetimeEvents);

  @override
  void bindEvents(Iterable<String> eventNames) {
    for (final name in eventNames) {
      if (!_bound.add(name)) {
        continue;
      }
      _signalR.addEventListener(name, (args) {
        if (!_events.isClosed) {
          _events.add(
            GameHubEvent(name: name, data: HubEventPayload.mapFromArgs(args)),
          );
        }
      });
    }
  }

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
  Future<void> playMusic(
    String asset, {
    String? package,
    bool loop = true,
    double? volume,
  }) async {}

  @override
  Future<void> playSfx(String asset, {String? package, double? volume}) async {}
}

class _FakeGameRepository implements GameRepository {
  @override
  Future<Result<String>> generateUrl({
    required int type,
    required String code,
  }) async =>
      Result.success('https://example.test/g/$code');
}

/// The debug launcher's shape: RouteAware, calling the real
/// [PlayGame.clearGameData] on didPopNext, exactly as the host page does.
class _HostPage extends ConsumerStatefulWidget {
  const _HostPage();

  @override
  ConsumerState<_HostPage> createState() => _HostPageState();
}

class _HostPageState extends ConsumerState<_HostPage> with RouteAware {
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
    unawaited(PlayGame.clearGameData(ref));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('home')),
      );
}

/// The game the server answers an entry's dispatch with. `status` 1/2 keeps
/// it in its lobby; the roster is what identity is checked against.
Map<String, dynamic> _lobbyGame(_Entry entry, {required String id}) => {
      'id': id,
      'status': entry.isPrivate ? 1 : 2,
      'mode': entry.isPrivate ? 4 : 1,
      'type': 0,
      'groupId': 'grp-$id',
      'isPrivate': entry.isPrivate,
      if (entry.isPrivate) 'gameCode': id,
      'currentTimerValue': 0,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
    };

void main() {
  late ProviderContainer container;
  late _FiringSignalRService signalR;
  late GlobalKey<NavigatorState> navigatorKey;

  GameController notifier() => container.read(gameControllerProvider.notifier);
  GameSessionState session() => container.read(gameControllerProvider);

  setUp(_listenerHighWater.clear);

  Future<void> pumpHome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FiringSignalRService();
    // The real provider calls bindAll() as it builds; an overrideWithValue
    // does not, so the wiring happens here.
    final bindings = _WiredHubBindings(signalR)..bindAll();
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
        gameRepositoryProvider.overrideWithValue(_FakeGameRepository()),
      ],
    );
    addTearDown(container.dispose);

    // The whole point of this file.
    //
    // `gameControllerProvider` is autoDispose, so if nothing outside the game
    // route watches it, popping that route disposes the controller and the
    // next entry gets a brand new one — every stale-state bug this suite
    // exists to catch becomes unreproducible. A cached FlutterEngine does not
    // work that way: its container outlives the route, the controller with
    // it, and the next entry lands on the session the previous one left.
    // This listener holds the provider open the same way, so leaving and
    // re-entering exercises the reset logic instead of skipping past it.
    final retain = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(retain.close);

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

  /// A bounded settle. `pumpAndSettle` does not terminate with these lobbies
  /// on screen, so a fixed number of frames is pumped instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Pushes the real game route for [entry].
  Future<void> enterGame(
    WidgetTester tester,
    _Entry entry, {
    String code = '0000',
  }) async {
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => switch (entry) {
            _Entry.public => const GameControllerScreen(),
            _Entry.privateCreate =>
              const GameControllerScreen(privateInterestIds: _interestIds),
            _Entry.privateJoin => GameControllerScreen(privateGameCode: code),
          },
        ),
      ),
    );
    await settle(tester);
  }

  /// Back, then the exit dialog if the phase raises one.
  Future<void> leaveGame(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final strings = PlayGameStrings.forLanguage(AppLanguage.english);
    final button = find.widgetWithText(GameButton, strings.exitTheGame);
    if (button.evaluate().isNotEmpty) {
      await tester.tap(button);
    }
    await settle(tester);
  }

  /// Everything the previous game left must be gone by the time an entry has
  /// dispatched, and the entry's own claims must be exactly right.
  void expectEntryIsClean(
    _Entry entry,
    List<({String method, List<Object?>? args})> since, {
    required String code,
  }) {
    final why = entry.label;

    // The one dispatch this entry owes, and nothing else on the wire.
    final dispatches =
        since.where((i) => i.method == entry.dispatch).toList();
    expect(dispatches, hasLength(1),
        reason: '$why must dispatch ${entry.dispatch} exactly once');
    expect(
      since.where((i) => i.method == PlayGameHubEvents.leaveGame),
      isEmpty,
      reason: 'no LeaveGame may be triggered for the new $why game',
    );
    // The other two entries' dispatches must not fire — a stale guard from a
    // previous game is exactly what would let one through, or suppress this
    // one.
    for (final other in _Entry.values.where((e) => e != entry)) {
      expect(
        since.where((i) => i.method == other.dispatch),
        isEmpty,
        reason: '$why must not dispatch ${other.dispatch}',
      );
    }
    if (entry == _Entry.privateJoin) {
      expect(dispatches.single.args, [code],
          reason: 'the code this entry was opened with, not a previous one');
    }
    if (entry == _Entry.privateCreate) {
      expect(dispatches.single.args, [_interestIds]);
    }
  }

  /// The state an entry must be sitting in before the server has answered.
  void expectFreshSession(_Entry entry) {
    final s = session();
    expect(s.result, isNull, reason: 'no previous result leaked in');
    expect(s.gameOver, isNull);
    expect(notifier().hasLeftGame, isFalse,
        reason: '_leftGame must not block the new entry');
    expect(
      notifier().isPrivateGameCreator,
      entry == _Entry.privateCreate,
      reason: 'the create guard reflects THIS entry, not a previous one',
    );
    if (entry.isPrivate) {
      expect(s.phase, GamePhase.lobbyPrivate);
      expect(s.game, isNull, reason: 'a private entry starts from nothing');
      expect(s.me, isNull);
      expect(s.opponent, isNull);
    } else {
      expect(s.phase, GamePhase.waiting);
    }
  }

  /// The screen an entry must be showing.
  ///
  /// Before the server answers, a public entry is still searching
  /// ([WaitingScreen]); once its GameUpdated arrives with a lobby status it
  /// moves to [LobbyPlayGameScreen], which is the public flow working. A
  /// private entry opens in its own lobby and stays there either way.
  void expectCorrectLobby(
    WidgetTester tester,
    _Entry entry, {
    required bool answered,
  }) {
    expect(find.byType(GameControllerScreen), findsOneWidget);
    if (entry.isPrivate) {
      expect(find.byType(LobbyPrivateGameScreen), findsOneWidget);
      expect(find.byType(WaitingScreen), findsNothing);
      expect(find.byType(LobbyPlayGameScreen), findsNothing);
      return;
    }
    expect(find.byType(LobbyPrivateGameScreen), findsNothing);
    if (answered) {
      expect(find.byType(LobbyPlayGameScreen), findsOneWidget);
    } else {
      expect(find.byType(WaitingScreen), findsOneWidget);
    }
  }

  void expectNoLeakedOverlay() {
    expect(find.byType(ShowDialogGame), findsNothing,
        reason: 'no dialog from the previous game may still be up');
    expect(find.byType(EndGameDialog), findsNothing);
    expect(find.byType(WinDialog), findsNothing);
    expect(find.byType(LossDialog), findsNothing);
  }

  /// One whole entry: push the route, check it started clean, let the server
  /// answer, and check the answer lands on this game.
  Future<void> enterAndVerify(
    WidgetTester tester,
    _Entry entry, {
    required String gameId,
    String? code,
  }) async {
    final before = signalR.invocations.length;
    await enterGame(tester, entry, code: code ?? gameId);
    final since = signalR.invocations.sublist(before);

    expectEntryIsClean(entry, since, code: code ?? gameId);
    expectFreshSession(entry);
    expectCorrectLobby(tester, entry, answered: false);
    expectNoLeakedOverlay();

    // The new game proceeds: the server answers, and the answer is applied to
    // THIS game.
    signalR.fire(entry.answer, [_lobbyGame(entry, id: gameId)]);
    await settle(tester);

    expect(session().game?.id, gameId,
        reason: '${entry.label} must be showing its own game');
    expect(session().me?.id, _localId,
        reason: 'identity survives the transition');
    expect(session().opponent?.id, _opponentId);
    expect(session().result, isNull);
    expectCorrectLobby(tester, entry, answered: true);
    expectNoLeakedOverlay();

    // Listener hygiene. The absolute count differs by phase (the controller's
    // bindings, plus whichever screens are mounted), so what is checked is
    // that it does not GROW as entries repeat — a screen that failed to
    // unsubscribe on the way out is exactly what would make it climb.
    for (final name in _watchedEvents) {
      final count = signalR.handlerCountFor(name);
      final seen = _listenerHighWater[name];
      if (seen == null) {
        _listenerHighWater[name] = count;
        continue;
      }
      expect(
        count,
        lessThanOrEqualTo(seen),
        reason: 'listeners for $name grew from $seen to $count across '
            'entries — a previous screen never unsubscribed',
      );
    }
  }

  /// Runs a whole sequence, leaving between each entry, and returns to home
  /// at the end.
  Future<void> runSequence(WidgetTester tester, List<_Entry> entries) async {
    await pumpHome(tester);
    var n = 0;
    for (final entry in entries) {
      n++;
      await enterAndVerify(
        tester,
        entry,
        gameId: 'g$n',
        code: entry == _Entry.privateJoin ? 'code-$n' : null,
      );
      await leaveGame(tester);
      expect(find.text('home'), findsOneWidget,
          reason: 'step $n (${entry.label}) must return to the host page');
      expect(find.byType(GameControllerScreen), findsNothing);
    }
  }

  group('public / random flows', () {
    testWidgets('1. Normal -> Normal', (tester) async {
      await runSequence(tester, [_Entry.public, _Entry.public]);
    });

    testWidgets('2. Normal -> Private Create -> Normal', (tester) async {
      await runSequence(
        tester,
        [_Entry.public, _Entry.privateCreate, _Entry.public],
      );
    });

    testWidgets('3. Normal -> Private Create -> Private Create',
        (tester) async {
      await runSequence(
        tester,
        [_Entry.public, _Entry.privateCreate, _Entry.privateCreate],
      );
    });
  });

  group('private flows', () {
    testWidgets('4. Private Create -> Private Create', (tester) async {
      await runSequence(
        tester,
        [_Entry.privateCreate, _Entry.privateCreate],
      );
    });

    testWidgets('5. Private Create -> Normal -> Private Create',
        (tester) async {
      await runSequence(
        tester,
        [_Entry.privateCreate, _Entry.public, _Entry.privateCreate],
      );
    });

    testWidgets('6. Private Join -> Private Join, with a new code',
        (tester) async {
      await runSequence(tester, [_Entry.privateJoin, _Entry.privateJoin]);
    });

    testWidgets('7. Private Join -> Normal -> Private Join', (tester) async {
      await runSequence(
        tester,
        [_Entry.privateJoin, _Entry.public, _Entry.privateJoin],
      );
    });

    testWidgets('8. Private Create -> Private Join -> Private Create',
        (tester) async {
      await runSequence(
        tester,
        [_Entry.privateCreate, _Entry.privateJoin, _Entry.privateCreate],
      );
    });

    testWidgets('9. Private Join -> Private Create -> Private Join',
        (tester) async {
      await runSequence(
        tester,
        [_Entry.privateJoin, _Entry.privateCreate, _Entry.privateJoin],
      );
    });
  });

  group('mixed stress sequence', () {
    testWidgets(
        'Normal -> Create -> Create -> Join -> Normal -> Join, leaving between '
        'every one', (tester) async {
      await runSequence(tester, [
        _Entry.public,
        _Entry.privateCreate,
        _Entry.privateCreate,
        _Entry.privateJoin,
        _Entry.public,
        _Entry.privateJoin,
      ]);
    });
  });

  group('what a transition must not carry over', () {
    testWidgets('a finished game leaves no result behind the next entry',
        (tester) async {
      await pumpHome(tester);
      await enterAndVerify(tester, _Entry.public, gameId: 'g1');

      // Drive the first game to a real end, then leave through the dialog.
      signalR.fire(PlayGameHubEvents.gameOver, [
        {'gameId': 'g1', 'winnerId': _opponentId},
      ]);
      await settle(tester);
      expect(session().result, isNotNull, reason: 'sanity: the game ended');

      await leaveGame(tester);
      await settle(tester);

      await enterAndVerify(tester, _Entry.privateCreate, gameId: 'g2');
    });

    testWidgets('a private game left mid-lobby owes no create to the next '
        'entry', (tester) async {
      await pumpHome(tester);
      await enterAndVerify(tester, _Entry.privateCreate, gameId: 'g1');
      await leaveGame(tester);

      // onRecovered re-issues a create only while one is genuinely owed. A
      // left entry owes nothing, and a public entry owes nothing either.
      await notifier().onRecovered();
      await settle(tester);

      expect(
        signalR.countOf(PlayGameHubEvents.createPrivateGame),
        1,
        reason: 'the previous entry must not re-issue its create',
      );

      await enterAndVerify(tester, _Entry.public, gameId: 'g2');
    });

    testWidgets('the roster of the previous game never seats the next one',
        (tester) async {
      await pumpHome(tester);
      await enterAndVerify(tester, _Entry.privateJoin, gameId: 'g1',
          code: 'code-1');
      await leaveGame(tester);

      await enterGame(tester, _Entry.privateCreate);

      expect(session().me, isNull);
      expect(session().opponent, isNull);
      expect(session().game, isNull,
          reason: 'the new private lobby starts from nothing at all');

      await leaveGame(tester);
    });
  });
}
