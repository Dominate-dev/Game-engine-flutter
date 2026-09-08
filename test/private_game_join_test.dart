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

// Joining a private game by its invite code.
//
// The contract is the repository's own — docs/tasks/private-game-workflow.md:
//   JoinPrivateGame  <- one String, the game code
//   WrongGameCode    -> the code names no game
//   GameJoined       -> CreatedGame with mode 4, guest lobby
//
// Nothing here asserts anything about the REST `checkGame` pre-flight or
// `isHost`: neither is implemented, and this batch deliberately does not
// invent them.
//
// GameJoined routing is NOT re-implemented for join — `_routeByStatus` already
// sends any private payload (isPrivate, or mode 4) to GamePhase.lobbyPrivate.
// The tests below pin that it keeps doing so through the join entry.

const _localId = '47';
const _opponentId = '211403';
const _code = '4821';
const _interestId = 88;

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  @override
  bool get hasLiveConnection => true;

  @override
  bool get isConnected => true;

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

/// Reports every dispatch as never sent, so the guard's reopen path shows.
class _FailingSignalRService extends _FakeSignalRService {
  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    invocations.add((method: methodName, args: args));
    return false;
  }
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

/// `GameJoined` as the guest receives it: mode 4, both players seated.
Map<String, dynamic> _joinedGame({
  int status = 1,
  String gameCode = _code,
  bool withOpponent = true,
  bool isPrivate = true,
  int mode = GameMode.privatePvp,
}) =>
    {
      'id': 'joined-1',
      'status': status,
      'mode': mode,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': isPrivate,
      'gameCode': gameCode,
      'currentTimerValue': 0,
      'players': [
        {
          'id': _localId,
          'playerName': 'guest',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
        if (withOpponent)
          {
            'id': _opponentId,
            'playerName': 'host',
            'makeupTryCount': 0,
            'maxMakeupTryCount': 3,
          },
      ],
    };

/// A previous, unrelated game left on a reused controller.
Map<String, dynamic> _previousGame() => {
      'id': 'stale-1',
      'status': 2,
      'mode': 1,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': false,
      'currentTimerValue': 0,
      'players': [
        {'id': _localId, 'playerName': 'StaleMe'},
        {'id': _opponentId, 'playerName': 'StaleFoe'},
      ],
    };

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  List<({String method, List<Object?>? args})> callsTo(String method) =>
      signalR.invocations.where((i) => i.method == method).toList();

  Future<void> newContainer({bool failingDispatch = false}) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR =
        failingDispatch ? _FailingSignalRService() : _FakeSignalRService();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider
            .overrideWithValue(_FakeHubBindings(signalR)),
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

  /// Opens the join entry exactly as `PlayGame.openPrivateGameByCode` does.
  Future<void> pumpJoinEntry(
    WidgetTester tester, {
    String code = _code,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: GameControllerScreen(privateGameCode: code),
        ),
      ),
    );
    await tester.pump();
  }

  /// Unmounts and drains, so a controller seeded before the tree — which
  /// starts the session's own timers — leaves no pending work behind.
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Future<void> gameJoined(
    WidgetTester tester,
    Map<String, dynamic> game,
  ) async {
    notifier().applySessionEvent(PlayGameHubEvents.gameJoined, game);
    await tester.pump();
  }

  group('the join entry dispatches JoinPrivateGame', () {
    testWidgets('invoked exactly once with the code as a single String',
        (tester) async {
      await newContainer();
      await pumpJoinEntry(tester);

      final calls = callsTo(PlayGameHubEvents.joinPrivateGame);
      expect(calls, hasLength(1));
      expect(calls.single.args, [_code],
          reason: 'one hub parameter: the code itself, as a String');
    });

    testWidgets('not dispatched again on rebuild', (tester) async {
      await newContainer();
      await pumpJoinEntry(tester);
      await gameJoined(tester, _joinedGame());
      await tester.pump(const Duration(seconds: 1));

      expect(callsTo(PlayGameHubEvents.joinPrivateGame), hasLength(1));
    });

    testWidgets('a blank code dispatches nothing', (tester) async {
      await newContainer();
      await pumpJoinEntry(tester, code: '   ');
      await tester.pump(const Duration(seconds: 1));

      expect(callsTo(PlayGameHubEvents.joinPrivateGame), isEmpty);
    });

    testWidgets('an empty code dispatches nothing', (tester) async {
      await newContainer();
      await pumpJoinEntry(tester, code: '');
      await tester.pump(const Duration(seconds: 1));

      expect(callsTo(PlayGameHubEvents.joinPrivateGame), isEmpty);
    });

    testWidgets('the code is trimmed before it is sent', (tester) async {
      await newContainer();
      await pumpJoinEntry(tester, code: '  $_code  ');

      expect(callsTo(PlayGameHubEvents.joinPrivateGame).single.args, [_code]);
    });

    testWidgets('the join entry never invokes CreatePrivateGame',
        (tester) async {
      await newContainer();
      await pumpJoinEntry(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(callsTo(PlayGameHubEvents.createPrivateGame), isEmpty);
    });

    testWidgets('the join entry never invokes JoinRandomGame — including '
        "past WaitingScreen's own post-frame dispatch", (tester) async {
      await newContainer();
      await pumpJoinEntry(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(callsTo(PlayGameHubEvents.joinRandomGame), isEmpty);
      expect(find.byType(WaitingScreen), findsNothing);
    });
  });

  group('the dispatch guard', () {
    test('a failed dispatch reopens the guard for a retry', () async {
      await newContainer(failingDispatch: true);
      notifier().enterPrivateLobby();

      expect(await notifier().joinPrivateGame(_code), isFalse);
      expect(await notifier().joinPrivateGame(_code), isFalse);
      expect(
        signalR.invocations
            .where((i) => i.method == PlayGameHubEvents.joinPrivateGame)
            .length,
        2,
        reason: 'nothing left the device, so the attempt is retryable',
      );
    });

    test('a successful dispatch closes the guard', () async {
      await newContainer();
      notifier().enterPrivateLobby();

      expect(await notifier().joinPrivateGame(_code), isTrue);
      expect(await notifier().joinPrivateGame(_code), isFalse);
      expect(callsTo(PlayGameHubEvents.joinPrivateGame), hasLength(1));
    });

    test('a blank code leaves the guard open', () async {
      await newContainer();
      notifier().enterPrivateLobby();

      expect(await notifier().joinPrivateGame('  '), isFalse);
      expect(await notifier().joinPrivateGame(_code), isTrue,
          reason: 'no attempt was made, so nothing was consumed');
    });

    test('enterPrivateLobby reopens both private guards independently',
        () async {
      await newContainer();
      notifier().enterPrivateLobby();
      await notifier().joinPrivateGame(_code);
      await notifier().createPrivateGame(const [_interestId]);

      notifier().enterPrivateLobby();
      expect(await notifier().joinPrivateGame(_code), isTrue);
      expect(await notifier().createPrivateGame(const [_interestId]), isTrue);
    });

    test('joining does not consume the create guard, or the reverse',
        () async {
      await newContainer();
      notifier().enterPrivateLobby();

      expect(await notifier().joinPrivateGame(_code), isTrue);
      expect(await notifier().createPrivateGame(const [_interestId]), isTrue,
          reason: 'separate flags — one flow must not suppress the other');
    });
  });

  group('GameJoined routes into the private lobby', () {
    testWidgets('mode 4 lands in lobbyPrivate', (tester) async {
      await newContainer();
      await pumpJoinEntry(tester);
      await gameJoined(tester, _joinedGame());

      expect(current().phase, GamePhase.lobbyPrivate);
      expect(find.byType(LobbyPrivateGameScreen), findsOneWidget);
      expect(find.byType(LobbyPlayGameScreen), findsNothing);
    });

    testWidgets('mode 4 alone is enough, without isPrivate', (tester) async {
      await newContainer();
      await pumpJoinEntry(tester);
      await gameJoined(tester, _joinedGame(isPrivate: false));

      expect(current().phase, GamePhase.lobbyPrivate);
    });

    testWidgets('isPrivate alone is enough, without mode 4', (tester) async {
      await newContainer();
      await pumpJoinEntry(tester);
      await gameJoined(tester, _joinedGame(mode: 1));

      expect(current().phase, GamePhase.lobbyPrivate);
    });

    testWidgets('a joined game reported as isReady stays in the private '
        'lobby, not the public one', (tester) async {
      await newContainer();
      await pumpJoinEntry(tester);
      await gameJoined(tester, _joinedGame(status: 2));

      expect(current().phase, GamePhase.lobbyPrivate);
      expect(find.byType(LobbyPlayGameScreen), findsNothing);
    });

    testWidgets('the joined game code and roster render', (tester) async {
      await newContainer();
      await pumpJoinEntry(tester);
      await gameJoined(tester, _joinedGame());

      for (final digit in ['4', '8', '2', '1']) {
        expect(find.text(digit), findsOneWidget);
      }
      expect(find.text('guest'), findsOneWidget);
      expect(find.text('host'), findsOneWidget);
      expect(current().game?.id, 'joined-1');
      expect(current().lastEventName, PlayGameHubEvents.gameJoined);
    });

    testWidgets('a joined game with only the host seated leaves the opponent '
        'seat empty', (tester) async {
      await newContainer();
      await pumpJoinEntry(tester);
      await gameJoined(tester, _joinedGame(withOpponent: false));

      final strings = PlayGameStrings.forLanguage(AppLanguage.english);
      expect(current().opponent, isNull);
      expect(find.text(strings.waitingForPlayer), findsOneWidget);
    });
  });

  group('no stale state can reach the first join frame', () {
    testWidgets("the previous game's players are absent on the very first "
        'frame', (tester) async {
      await newContainer();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _previousGame(),
      );
      await pumpJoinEntry(tester);
      // No pump past the first build.

      expect(find.text('StaleMe'), findsNothing);
      expect(find.text('StaleFoe'), findsNothing);
      await drain(tester);
    });

    testWidgets('the previous game itself is dropped from the session',
        (tester) async {
      await newContainer();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _previousGame(),
      );
      await pumpJoinEntry(tester);
      await tester.pump();

      expect(current().game, isNull);
      expect(current().me, isNull);
      expect(current().opponent, isNull);
      expect(current().phase, GamePhase.lobbyPrivate);
      await drain(tester);
    });

    testWidgets('no mock or placeholder data appears before GameJoined',
        (tester) async {
      await newContainer();
      await pumpJoinEntry(tester);
      await tester.pump();

      expect(find.text('2580'), findsNothing);
      expect(find.text('Hassan Hasanat'), findsNothing);
    });
  });

  group('WrongGameCode is surfaced', () {
    testWidgets('a wrong code does not leave the player in an empty lobby',
        (tester) async {
      await newContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => PlayGame.openPrivateGameByCode(
                  context,
                  gameCode: _code,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(LobbyPrivateGameScreen), findsOneWidget);

      // A bare signal: no payload is read, because none is confirmed.
      final state = tester.state(find.byType(LobbyPrivateGameScreen));
      (state as dynamic).onEventReceived(
        PlayGameHubEvents.wrongGameCode,
        null,
      );
      await tester.pump();

      final strings = PlayGameStrings.forLanguage(AppLanguage.english);
      expect(find.text(strings.wrongGameCode), findsOneWidget,
          reason: 'the player is told, not left staring at an empty lobby');

      await tester.pumpAndSettle();
      expect(find.byType(LobbyPrivateGameScreen), findsNothing,
          reason: 'and the dead lobby is popped');
    });

    testWidgets('WrongGameCode is bound for the private lobby only',
        (tester) async {
      expect(
        PlayGameHubEvents.privateLobbyScreenEvents,
        contains(PlayGameHubEvents.wrongGameCode),
      );
      expect(
        PlayGameHubEvents.lobbyScreenEvents,
        isNot(contains(PlayGameHubEvents.wrongGameCode)),
        reason: 'the public lobby can never receive it',
      );
      expect(
        PlayGameHubEvents.privateLobbyScreenEvents,
        containsAll(PlayGameHubEvents.lobbyScreenEvents),
        reason: 'and it still gets every shared lobby event',
      );
    });

    testWidgets('both languages have the string', (tester) async {
      final en = PlayGameStrings.forLanguage(AppLanguage.english);
      final ar = PlayGameStrings.forLanguage(AppLanguage.arabic);
      expect(en.wrongGameCode, isNotEmpty);
      expect(ar.wrongGameCode, isNotEmpty);
      expect(ar.wrongGameCode, isNot(en.wrongGameCode));
    });
  });

  group('the other entries are unchanged', () {
    testWidgets('the create entry still invokes CreatePrivateGame and never '
        'JoinPrivateGame', (tester) async {
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
      await tester.pump(const Duration(seconds: 1));

      expect(callsTo(PlayGameHubEvents.createPrivateGame), hasLength(1));
      expect(callsTo(PlayGameHubEvents.joinPrivateGame), isEmpty);
      expect(callsTo(PlayGameHubEvents.joinRandomGame), isEmpty);
      expect(current().phase, GamePhase.lobbyPrivate);
    });

    testWidgets('the public entry still invokes JoinRandomGame only',
        (tester) async {
      await newContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameControllerScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(callsTo(PlayGameHubEvents.joinRandomGame), hasLength(1));
      expect(callsTo(PlayGameHubEvents.joinPrivateGame), isEmpty);
      expect(callsTo(PlayGameHubEvents.createPrivateGame), isEmpty);
      expect(current().phase, GamePhase.waiting);
    });

    testWidgets('a public game still reaches the public lobby',
        (tester) async {
      await newContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameControllerScreen()),
        ),
      );
      await tester.pump();
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

      expect(current().phase, GamePhase.lobbyPlay);
      expect(find.byType(LobbyPlayGameScreen), findsOneWidget);
    });
  });

  group('GameRestore still preserves the private lobby after a join', () {
    testWidgets('an unresolvable restore keeps lobbyPrivate', (tester) async {
      await newContainer();
      await pumpJoinEntry(tester);
      await gameJoined(tester, _joinedGame());

      notifier().onLobbyGameRestore({
        'id': 'joined-1',
        'status': null,
        'mode': GameMode.privatePvp,
        'isPrivate': true,
        'players': [
          {'id': _localId, 'playerName': 'guest'},
        ],
      });
      await tester.pump(const Duration(seconds: 1));

      expect(current().phase, GamePhase.lobbyPrivate);
      expect(callsTo(PlayGameHubEvents.joinRandomGame), isEmpty);
    });
  });
}
