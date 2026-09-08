import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/domain/game_mode.dart';
import 'package:play_game/features/games/domain/repositories/game_repository.dart';
import 'package:play_game/features/games/presentation/providers/game_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// GameRestore must not evict a private session to WaitingScreen.
//
// Verified by reading the code, not assumed:
//   - LobbyPrivateGameScreen listens on lobbyScreenEvents and routes
//     GameRestore to GameController.onLobbyGameRestore, which is a one-line
//     delegate to onWaitingGameRestore. The private lobby therefore runs the
//     *waiting* screen's restore handler.
//   - onWaitingGameRestore tries _routeByStatus first. That resolves only
//     when StatusGame.fromId(game?.status) lands in 1..4; a status that is
//     explicitly null, coerced to the 0 sentinel, or simply unrecognized
//     makes it return false (the same R-05 shapes covered by
//     restore_status_fallback_test.dart).
//   - Its fallback then named GamePhase.waiting outright. In a private
//     session that swapped LobbyPrivateGameScreen for WaitingScreen, whose
//     post-frame onWaitingShown dispatches JoinRandomGame — public
//     matchmaking, in a game that already has its own code and roster.
//   - The fix keeps GamePhase.lobbyPrivate when that is the phase already
//     showing. Public sessions still fall back to GamePhase.waiting.
//
// applySessionEvent's own GameRestore branch was already safe (it falls back
// to state.phase), but the private lobby does not go through it — _onHubEvent
// early-returns only for waiting/lobbyPlay — so both paths are asserted here.

const _localId = '47';
const _opponentId = '211403';
const _interestId = 88;

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  @override
  bool get hasLiveConnection => true;

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    invocations.add((method: methodName, args: args));
    return true;
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

class _FakeGameRepository implements GameRepository {
  @override
  Future<Result<String>> generateUrl({
    required int type,
    required String code,
  }) async =>
      Result.success('https://example.test/g/$code');
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

class _FakeStickersRepository implements StickersRepository {
  @override
  Future<Result<StickerPage>> getStickerGroups(
    StickerFilterParams params,
  ) async =>
      Result.success(
        const StickerPage(items: [], pageIndex: 0, pageSize: 20),
      );

  @override
  Future<Result<bool>> payStickerGroup(int id) async => Result.success(true);
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
  Future<void> playSfx(
    String asset, {
    String? package,
    double? volume,
  }) async {}
}

/// A private game exactly as `GameCreated` reports it.
Map<String, dynamic> _privateGame({
  int status = 1,
  String gameCode = '4821',
  bool withOpponent = false,
}) =>
    {
      'id': 'private-1',
      'status': status,
      'mode': GameMode.privatePvp,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': true,
      'gameCode': gameCode,
      'currentTimerValue': 0,
      'players': [
        {
          'id': _localId,
          'playerName': 'host',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
        if (withOpponent)
          {
            'id': _opponentId,
            'playerName': 'guest',
            'makeupTryCount': 0,
            'maxMakeupTryCount': 3,
          },
      ],
    };

/// A restore payload whose `status` cannot be resolved by _routeByStatus.
///
/// `status` is passed through as given so each shape in the matrix below can
/// be expressed exactly: explicitly null, the 0 sentinel, or an unrecognized
/// value. Omitting the key entirely is a separate shape — see [_restoreNoKey].
Map<String, dynamic> _restore({
  required Object? status,
  bool withOpponent = false,
}) =>
    {
      'id': 'private-1',
      'status': status,
      'mode': GameMode.privatePvp,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': true,
      'gameCode': '4821',
      'players': [
        {'id': _localId, 'playerName': 'host'},
        if (withOpponent) {'id': _opponentId, 'playerName': 'guest'},
      ],
    };

/// The same payload with the `status` key absent altogether.
Map<String, dynamic> _restoreNoKey() =>
    Map<String, dynamic>.from(_restore(status: null))..remove('status');

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;
  late _FakeHubBindings bindings;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  List<({String method, List<Object?>? args})> callsTo(String method) =>
      signalR.invocations.where((i) => i.method == method).toList();

  Future<void> newContainer() async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    bindings = _FakeHubBindings(signalR);
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider.overrideWithValue(bindings),
        stickersRepositoryProvider
            .overrideWithValue(_FakeStickersRepository()),
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
  }

  /// Opens the private entry exactly as `PlayGame.openPrivateGame` does.
  Future<void> pumpPrivateEntry(WidgetTester tester) async {
    await newContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: GameControllerScreen(privateInterestIds: [_interestId]),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpPublicEntry(WidgetTester tester) async {
    await newContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameControllerScreen()),
      ),
    );
    await tester.pump();
  }

  Future<void> gameCreated(
    WidgetTester tester,
    Map<String, dynamic> game,
  ) async {
    notifier().applySessionEvent(PlayGameHubEvents.gameCreated, game);
    await tester.pump();
  }

  group('GameCreated → unresolvable GameRestore keeps the private lobby', () {
    testWidgets('the phase stays lobbyPrivate', (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());
      expect(current().phase, GamePhase.lobbyPrivate, reason: 'sanity');

      notifier().onLobbyGameRestore(_restore(status: null));
      await tester.pump();

      expect(
        current().phase,
        GamePhase.lobbyPrivate,
        reason: 'before the fix this became GamePhase.waiting — the '
            'handler named it outright',
      );
    });

    testWidgets('WaitingScreen is never mounted', (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      notifier().onLobbyGameRestore(_restore(status: null));
      await tester.pump();

      expect(find.byType(LobbyPrivateGameScreen), findsOneWidget);
      expect(find.byType(WaitingScreen), findsNothing);
    });

    testWidgets('JoinRandomGame is not dispatched', (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      notifier().onLobbyGameRestore(_restore(status: null));
      // Well past WaitingScreen's own post-frame dispatch, had it mounted.
      await tester.pump(const Duration(seconds: 1));

      expect(
        callsTo(PlayGameHubEvents.joinRandomGame),
        isEmpty,
        reason: 'public matchmaking must never start inside a private game',
      );
    });

    testWidgets('the restore payload is still applied to the session',
        (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      notifier().onLobbyGameRestore(_restore(status: null));
      await tester.pump();

      expect(current().game?.id, 'private-1');
      expect(current().game?.gameCode, '4821');
      expect(current().lastEventName, PlayGameHubEvents.gameRestore);
    });
  });

  group('no visual flash between GameCreated and GameRestore', () {
    testWidgets('every frame from creation through restore shows the '
        'private lobby and never WaitingScreen', (tester) async {
      await pumpPrivateEntry(tester);

      final phases = <GamePhase>[current().phase];
      final sub = container.listen<GameSessionState>(
        gameControllerProvider,
        (_, next) => phases.add(next.phase),
      );
      addTearDown(sub.close);

      await gameCreated(tester, _privateGame());
      expect(find.byType(WaitingScreen), findsNothing);

      notifier().onLobbyGameRestore(_restore(status: null));
      await tester.pump();
      expect(find.byType(WaitingScreen), findsNothing);
      expect(find.byType(LobbyPrivateGameScreen), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));

      expect(
        phases,
        everyElement(GamePhase.lobbyPrivate),
        reason: 'not one intermediate state carried GamePhase.waiting, so '
            'WaitingScreen never got a frame to flash in',
      );
    });
  });

  group('restore-shape matrix — every unresolvable status', () {
    // _routeByStatus resolves only StatusGame 1..4. Each shape below fails
    // that check for its own reason and must therefore reach the fallback.
    final unresolvable = <String, Map<String, dynamic>>{
      'status explicitly null': _restore(status: null),
      'status as the 0 sentinel': _restore(status: 0),
      'status unrecognized (99)': _restore(status: 99),
      'status as an unparsable string': _restore(status: 'unknown'),
      'status key absent entirely': _restoreNoKey(),
    };

    unresolvable.forEach((shape, payload) {
      testWidgets('$shape keeps lobbyPrivate', (tester) async {
        await pumpPrivateEntry(tester);
        await gameCreated(tester, _privateGame());

        notifier().onLobbyGameRestore(payload);
        await tester.pump(const Duration(seconds: 1));

        expect(current().phase, GamePhase.lobbyPrivate);
        expect(find.byType(WaitingScreen), findsNothing);
        expect(callsTo(PlayGameHubEvents.joinRandomGame), isEmpty);
      });
    });

    testWidgets('a resolvable status is untouched by the fix — a private '
        'waiting-for-players restore still routes through _routeByStatus '
        'to the same lobby', (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      notifier().onLobbyGameRestore(_restore(status: 1));
      await tester.pump();

      expect(current().phase, GamePhase.lobbyPrivate);
    });

    testWidgets('an in-progress restore still leaves the lobby for its round',
        (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      notifier().onLobbyGameRestore({
        ..._restore(status: 3),
        'type': 1, // WDYK
      });
      await tester.pump();

      expect(
        current().phase,
        GamePhase.wdyk,
        reason: 'the fix guards only the unresolvable fallback; started '
            'games must still route normally',
      );
    });
  });

  group('both entry paths reach the same guard', () {
    testWidgets('direct onLobbyGameRestore (the screen listener path)',
        (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      notifier().onLobbyGameRestore(_restore(status: null));
      await tester.pump();

      expect(current().phase, GamePhase.lobbyPrivate);
    });

    testWidgets('onWaitingGameRestore called directly', (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      notifier().onWaitingGameRestore(_restore(status: null));
      await tester.pump();

      expect(current().phase, GamePhase.lobbyPrivate);
    });

    testWidgets('applySessionEvent (the hub pipeline path)', (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _restore(status: null),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(current().phase, GamePhase.lobbyPrivate);
      expect(callsTo(PlayGameHubEvents.joinRandomGame), isEmpty);
    });

    testWidgets('the live bindings stream, end to end', (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      bindings.emit(PlayGameHubEvents.gameRestore, _restore(status: null));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(current().phase, GamePhase.lobbyPrivate);
      expect(find.byType(WaitingScreen), findsNothing);
      expect(callsTo(PlayGameHubEvents.joinRandomGame), isEmpty);
    });
  });

  group('seating is unchanged by the fix', () {
    testWidgets('a host-only restore leaves the opponent seat empty',
        (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());
      expect(current().opponent, isNull, reason: 'sanity');

      notifier().onLobbyGameRestore(_restore(status: null));
      await tester.pump();

      expect(current().me?.playerName, 'host');
      expect(
        current().opponent,
        isNull,
        reason: 'no opponent in the payload and none seated before — the '
            'guard must not invent one',
      );
      final strings = PlayGameStrings.forLanguage(AppLanguage.english);
      expect(find.text(strings.waitingForPlayer), findsOneWidget);
      expect(find.text('guest'), findsNothing);
    });

    testWidgets('a restore carrying both players seats the opponent',
        (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      notifier().onLobbyGameRestore(
        _restore(status: null, withOpponent: true),
      );
      await tester.pump();

      expect(current().phase, GamePhase.lobbyPrivate);
      expect(current().opponent?.playerName, 'guest');
    });
  });

  group('the public fallback is unchanged', () {
    testWidgets('a public session with an unresolvable status still falls '
        'back to GamePhase.waiting', (tester) async {
      await pumpPublicEntry(tester);
      expect(current().phase, GamePhase.waiting, reason: 'sanity');

      notifier().onWaitingGameRestore({
        'id': 'public-1',
        'status': null,
        'mode': 1,
        'type': 0,
        'groupId': 'grp',
        'isPrivate': false,
        'players': [
          {'id': _localId, 'playerName': 'me'},
        ],
      });
      await tester.pump();

      expect(current().phase, GamePhase.waiting);
      expect(find.byType(WaitingScreen), findsOneWidget);
      expect(current().game?.id, 'public-1');
    });

    testWidgets('a public lobby session with an unresolvable status also '
        'falls back to GamePhase.waiting, exactly as before', (tester) async {
      await pumpPublicEntry(tester);
      notifier().applySessionEvent(PlayGameHubEvents.gameJoined, {
        'id': 'public-1',
        'status': 2,
        'mode': 1,
        'type': 0,
        'groupId': 'grp',
        'isPrivate': false,
        'players': [
          {'id': _localId, 'playerName': 'me'},
          {'id': _opponentId, 'playerName': 'them'},
        ],
      });
      await tester.pump();
      expect(current().phase, GamePhase.lobbyPlay, reason: 'sanity');

      notifier().onLobbyGameRestore({
        'id': 'public-1',
        'status': null,
        'mode': 1,
        'type': 0,
        'groupId': 'grp',
        'isPrivate': false,
        'players': [
          {'id': _localId, 'playerName': 'me'},
          {'id': _opponentId, 'playerName': 'them'},
        ],
      });
      await tester.pump();

      expect(
        current().phase,
        GamePhase.waiting,
        reason: 'the pre-existing public behaviour, deliberately untouched',
      );
    });
  });
}
