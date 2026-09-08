import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/features/games/domain/repositories/game_repository.dart';
import 'package:play_game/features/games/presentation/providers/game_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Random Game after a Private Game, on a controller the previous entry left.
//
// A controller is normally per-entry (autoDispose), so a random entry got a
// session that was already `GameSessionState.initial()`. A host that keeps
// one cached FlutterEngine across entries keeps the provider alive instead:
// the random entry arrived on the private game's own controller, still at
// `GamePhase.lobbyPrivate` with `_leftGame` true, so `_bodyFor` re-opened the
// private lobby and `onWaitingShown` refused to dispatch `JoinRandomGame`.
//
// `enterWaiting()` is the public counterpart of `enterPrivateLobby()`, and
// the entry now runs it before anything else — the tests below keep the
// provider alive with a listener, which is what reproduces the device.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  final invocations = <String>[];

  @override
  bool get isConnected => true;

  @override
  bool get hasLiveConnection => true;

  int countOf(String method) => invocations.where((m) => m == method).length;

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    invocations.add(methodName);
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

class _FakeGameRepository implements GameRepository {
  @override
  Future<Result<String>> generateUrl({
    required int type,
    required String code,
  }) async =>
      Result.success('https://example.test/g/$code');
}

/// The private game the previous entry leaves behind — seated players and a
/// `lobbyPrivate` phase, exactly what the next random entry inherited.
Map<String, dynamic> _privateGame() => {
      'id': 'private-1',
      'status': 1,
      'mode': 4,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': true,
      'currentTimerValue': 0,
      'players': [
        {
          'id': _localId,
          'playerName': 'Me',
          'profileImageUrl': 'http://example.test/me.png',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
        {
          'id': _opponentId,
          'playerName': 'Foe',
          'profileImageUrl': 'http://example.test/foe.png',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
      ],
    };

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;

  GameController notifier() => container.read(gameControllerProvider.notifier);

  int joins() => signalR.countOf(PlayGameHubEvents.joinRandomGame);
  int creates() => signalR.countOf(PlayGameHubEvents.createPrivateGame);

  Future<void> newContainer() async {
    SharedPreferences.setMockInitialValues({'user_id': _localId});
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
    // What the cached engine does: the controller outlives the screen, so a
    // later entry lands on the session the previous one left.
    final sub = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(sub.close);
  }

  Future<void> mount(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      ),
    );
    // One pump for the entry's post-frame reset, one for the frame it causes.
    await tester.pump();
    await tester.pump();
  }

  Future<void> mountPrivate(WidgetTester tester) =>
      mount(tester, const GameControllerScreen(privateInterestIds: [2]));

  Future<void> mountPublic(WidgetTester tester) =>
      mount(tester, const GameControllerScreen());

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// Plays a whole private game entry through to its exit, leaving the
  /// controller exactly as the device leaves it.
  Future<void> privateEntryThenLeave(WidgetTester tester) async {
    await mountPrivate(tester);
    notifier().applySessionEvent(
      PlayGameHubEvents.gameUpdated,
      _privateGame(),
    );
    await tester.pump();
    await notifier().leaveGame();
    await unmount(tester);
  }

  void expectFreshWaitingSession() {
    final session = container.read(gameControllerProvider);
    expect(session.phase, GamePhase.waiting);
    expect(session.result, isNull);
    expect(session.game, isNull);
    expect(session.me, isNull);
    expect(session.opponent, isNull);
    expect(session.data, isNull);
    expect(session.lastEventName, isNull);
    expect(notifier().hasLeftGame, isFalse);
  }

  setUp(() async => newContainer());

  group('1. the reported scenario', () {
    testWidgets('private game, leave, then random — the join goes out',
        (tester) async {
      await privateEntryThenLeave(tester);

      // The state the random entry used to inherit.
      expect(
        container.read(gameControllerProvider).phase,
        GamePhase.lobbyPrivate,
      );
      expect(notifier().hasLeftGame, isTrue);
      expect(joins(), 0);

      await mountPublic(tester);

      expectFreshWaitingSession();
      expect(
        find.byType(WaitingScreen),
        findsOneWidget,
        reason: 'the random entry must open Waiting, not the private lobby',
      );
      expect(
        joins(),
        1,
        reason: 'the dispatch the stale _leftGame used to suppress',
      );

      await unmount(tester);
    });

    testWidgets('the stale private lobby is never rendered, not even on the '
        'first frame', (tester) async {
      await privateEntryThenLeave(tester);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: GameControllerScreen()),
        ),
      );
      expect(
        find.byType(LobbyPrivateGameScreen),
        findsNothing,
        reason: 'frame zero still holds the private phase; nothing routes on '
            'it',
      );
      expect(
        find.byType(WaitingScreen),
        findsNothing,
        reason: 'and Waiting must not mount before the reset either — its '
            'own mount is what dispatches the join',
      );

      await tester.pump();
      await tester.pump();

      expect(find.byType(WaitingScreen), findsOneWidget);
      expect(find.byType(LobbyPrivateGameScreen), findsNothing);
      expect(joins(), 1);

      await unmount(tester);
    });
  });

  group('2. the flows that already worked still do', () {
    testWidgets('a fresh random game, with nothing before it', (tester) async {
      await mountPublic(tester);

      expectFreshWaitingSession();
      expect(find.byType(WaitingScreen), findsOneWidget);
      expect(joins(), 1);

      await unmount(tester);
    });

    testWidgets('one join per session, however many frames it gets',
        (tester) async {
      await mountPublic(tester);
      await tester.pump();
      await tester.pump();

      expect(joins(), 1);

      await unmount(tester);
    });

    testWidgets('private, random, private, random — every entry dispatches '
        'its own', (tester) async {
      await privateEntryThenLeave(tester);
      expect(creates(), 1);

      await mountPublic(tester);
      expect(find.byType(WaitingScreen), findsOneWidget);
      expect(joins(), 1);
      await notifier().leaveGame();
      await unmount(tester);

      await privateEntryThenLeave(tester);
      expect(creates(), 2, reason: 'the private second-entry fix still holds');

      await mountPublic(tester);
      expect(find.byType(WaitingScreen), findsOneWidget);
      expect(joins(), 2);

      await unmount(tester);
    });
  });

  group('3. a left session keeps every protection it had', () {
    test('leaving a random game still blocks a second join on that session',
        () async {
      notifier().enterWaiting();
      await notifier().onWaitingShown();
      expect(joins(), 1);

      await notifier().leaveGame();

      await notifier().onWaitingShown();
      expect(
        joins(),
        1,
        reason: 'the left session may not queue the player into a new game',
      );
    });

    test('and still blocks recovery for that session', () async {
      notifier().enterWaiting();
      await notifier().leaveGame();

      await notifier().onRecovered();

      expect(signalR.countOf(PlayGameHubEvents.checkPlayerGame), 0);
      expect(joins(), 0);
    });

    test('within one session the join guard stays claimed', () async {
      notifier().enterWaiting();

      await notifier().onWaitingShown();
      await notifier().onWaitingShown();

      expect(joins(), 1);
    });

    test('enterWaiting starts a new session that may join and leave for '
        'itself', () async {
      notifier().enterWaiting();
      await notifier().onWaitingShown();
      await notifier().leaveGame();

      notifier().enterWaiting();
      await notifier().onWaitingShown();
      await notifier().leaveGame();

      expect(joins(), 2);
      expect(signalR.countOf(PlayGameHubEvents.leaveGame), 2);
    });
  });
}
