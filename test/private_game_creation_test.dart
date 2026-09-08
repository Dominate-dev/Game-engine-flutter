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

// T1 — private game creation → private lobby.
//
// Entry invokes CreatePrivateGame(interestIds), the server answers with
// GameCreated carrying the CreatedGame, and the session lands in the private
// lobby showing that game's own data. Nothing here asserts anything about
// JoinPrivateGame, GenerateURL or deep links — none of those exist yet.

const _localId = '47';
const _opponentId = '211403';
const _interestId = 88;

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  /// Entry connects before creating; the fake is already "connected" so the
  /// screen's own guard short-circuits and no real connect is attempted.
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

/// The private lobby asks for its invite link (T2). Stubbed here so these
/// tests never reach the network; the link itself is asserted on in
/// private_game_generate_url_test.dart, not here.
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

/// A private game exactly as `GameCreated` reports it: mode 4, isPrivate,
/// its own code, and only the host seated.
Map<String, dynamic> _privateGame({
  int status = 1,
  String gameCode = '4821',
  bool withOpponent = false,
  bool isPrivate = true,
  int mode = GameMode.privatePvp,
}) =>
    {
      'id': 'private-1',
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

/// A public game, for the no-regression checks.
Map<String, dynamic> _publicGame({int status = 1}) => {
      'id': 'public-1',
      'status': status,
      'mode': 1,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': false,
      'currentTimerValue': 0,
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
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

  Future<void> newContainer() async {
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

  Future<void> gameCreated(
    WidgetTester tester,
    Map<String, dynamic> game,
  ) async {
    notifier().applySessionEvent(PlayGameHubEvents.gameCreated, game);
    await tester.pump();
  }

  group('entry creates the private game', () {
    testWidgets('CreatePrivateGame is invoked with the caller\'s ids',
        (tester) async {
      await pumpPrivateEntry(tester);

      final calls = callsTo(PlayGameHubEvents.createPrivateGame);
      expect(calls, hasLength(1));
      expect(calls.single.args, [
        [_interestId],
      ], reason: 'one hub parameter, which is itself the list: [[88]]');
    });

    testWidgets('JoinRandomGame is never dispatched for a private entry',
        (tester) async {
      await pumpPrivateEntry(tester);
      // Well past WaitingScreen's own post-frame dispatch.
      await tester.pump(const Duration(seconds: 1));

      expect(callsTo(PlayGameHubEvents.joinRandomGame), isEmpty,
          reason: 'the public matchmaking flow must never start here');
    });

    testWidgets('the lobby is shown before any server round-trip',
        (tester) async {
      await pumpPrivateEntry(tester);

      expect(current().phase, GamePhase.lobbyPrivate);
      expect(find.byType(LobbyPrivateGameScreen), findsOneWidget);
      expect(find.byType(WaitingScreen), findsNothing);
    });

    testWidgets('creation is dispatched once, not per rebuild',
        (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());
      await tester.pump(const Duration(seconds: 1));

      expect(callsTo(PlayGameHubEvents.createPrivateGame), hasLength(1));
    });

    testWidgets('the public entry still dispatches JoinRandomGame and never '
        'CreatePrivateGame', (tester) async {
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
      expect(callsTo(PlayGameHubEvents.createPrivateGame), isEmpty);
      expect(current().phase, GamePhase.waiting);
    });
  });

  group('GameCreated is applied and routed', () {
    testWidgets('the CreatedGame is preserved on the session',
        (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      final game = current().game;
      expect(game, isNotNull);
      expect(game!.id, 'private-1');
      expect(game.gameCode, '4821');
      expect(game.isPrivate, isTrue);
      expect(game.mode, GameMode.privatePvp);
      expect(game.status, 1);
      expect(current().lastEventName, PlayGameHubEvents.gameCreated);
    });

    testWidgets('the host is seated from the payload roster', (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      expect(current().me?.playerName, 'host');
      expect(current().opponent, isNull);
    });

    testWidgets('GameCreated keeps the session in the private lobby',
        (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      expect(current().phase, GamePhase.lobbyPrivate);
      expect(find.byType(LobbyPrivateGameScreen), findsOneWidget);
    });

    testWidgets('a private game reported as isReady stays in the private '
        'lobby, not the public one', (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame(status: 2, withOpponent: true));

      expect(current().phase, GamePhase.lobbyPrivate);
      expect(find.byType(LobbyPlayGameScreen), findsNothing);
    });

    testWidgets('mode 4 alone is enough to route privately', (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame(isPrivate: false));

      expect(current().phase, GamePhase.lobbyPrivate);
    });

    testWidgets('the isPrivate flag alone is enough to route privately',
        (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame(mode: 1));

      expect(current().phase, GamePhase.lobbyPrivate);
    });
  });

  group('the lobby renders the real game, never placeholders', () {
    testWidgets('the server code is shown digit by digit', (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame(gameCode: '4821'));

      for (final digit in ['4', '8', '2', '1']) {
        expect(find.text(digit), findsOneWidget);
      }
      // The old mock code and mock players must not appear anywhere.
      expect(find.text('2580'), findsNothing);
      expect(find.text('Hassan Hasanat'), findsNothing);
      expect(find.text('Mahmoud Salih'), findsNothing);
    });

    testWidgets('the seated player names come from the payload',
        (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame(withOpponent: true));

      expect(find.text('host'), findsOneWidget);
      expect(find.text('guest'), findsOneWidget);
    });

    testWidgets('before GameCreated no code and no invented player is shown',
        (tester) async {
      await pumpPrivateEntry(tester);

      expect(find.text('2580'), findsNothing);
      expect(find.text('Hassan Hasanat'), findsNothing);
      final strings = PlayGameStrings.forLanguage(AppLanguage.english);
      expect(find.text(strings.waitingForPlayer), findsOneWidget,
          reason: 'the empty opponent seat, not a fabricated one');
    });

    testWidgets('Ready invokes ReadyForGame with the created game id',
        (tester) async {
      await pumpPrivateEntry(tester);
      await gameCreated(tester, _privateGame());

      final strings = PlayGameStrings.forLanguage(AppLanguage.english);
      await tester.tap(find.text(strings.iAmReady));
      await tester.pump();

      final calls = callsTo(PlayGameHubEvents.readyForGame);
      expect(calls, hasLength(1));
      expect(calls.single.args, ['private-1'],
          reason: 'the real game id, not a local flag');
    });
  });

  group('the public lobby flow is unaffected', () {
    testWidgets('a public game reported as isReady still shows the public '
        'lobby', (tester) async {
      await newContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameControllerScreen()),
        ),
      );
      await tester.pump();

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _publicGame(status: 2),
      );
      await tester.pump();

      expect(current().phase, GamePhase.lobbyPlay);
      expect(find.byType(LobbyPlayGameScreen), findsOneWidget);
      expect(find.byType(LobbyPrivateGameScreen), findsNothing);
    });

    testWidgets('a public game waiting for players still shows WaitingScreen',
        (tester) async {
      await newContainer();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameControllerScreen()),
        ),
      );
      await tester.pump();

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _publicGame(),
      );
      await tester.pump();

      expect(current().phase, GamePhase.waiting);
      expect(find.byType(WaitingScreen), findsOneWidget);
    });
  });
}
