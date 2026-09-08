import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The Private Lobby entry connection flow — the same shape
// waiting_connection_flow_test.dart pins for the public entry, applied to
// CreatePrivateGame.
//
// Ownership, traced through the code rather than assumed:
//   GameControllerScreen.initState -> post-frame -> _startPrivateGame()
//     -> enterPrivateLobby(), then _ensureHubConnected(), then
//        createPrivateGame(). _ensureHubConnected is the ONE place the entry
//        starts a connection, shared with the public path.
//   createPrivateGame gates on the connection instead of establishing one:
//     already connected -> dispatch CreatePrivateGame now
//     not connected     -> dispatch nothing, keep the ids, and let the
//                          entry's connect land. `recoveredStream` then
//                          fires `onRecovered`, which runs CheckPlayerGame
//                          and re-issues the create with its guard still
//                          open.
//
// `isConnected`, not `hasLiveConnection`: the latter is also true mid-connect,
// and a create must not ride a connect still in flight.

const _localId = '47';
const _interestIds = [88];

/// Models the socket the way the service does: `isConnected` is the state the
/// gate reads, and `invoke` only reaches the wire when it is true.
class _FakeSignalRService extends SignalRService {
  final invocations = <String>[];

  /// Every invoke() call, whether or not the hub accepted it. A dispatch
  /// attempted on a down hub would otherwise be invisible — and "never invoke
  /// CreatePrivateGame before the hub is connected" is what this file has to
  /// prove.
  final attempts = <String>[];

  /// The args of each accepted CreatePrivateGame, so the interest ids that
  /// actually reached the wire can be checked.
  final createArgs = <List<Object?>?>[];

  bool connected = false;

  /// Counts any attempt to establish a connection, so a second owner would be
  /// visible.
  int connectAttempts = 0;

  List<String> get creates => invocations
      .where((m) => m == PlayGameHubEvents.createPrivateGame)
      .toList();

  List<String> get checks => invocations
      .where((m) => m == PlayGameHubEvents.checkPlayerGame)
      .toList();

  @override
  bool get isConnected => connected;

  @override
  bool get hasLiveConnection => connected;

  @override
  Future<void> connect({
    required String url,
    Future<String> Function()? accessTokenFactory,
  }) async {
    connectAttempts++;
    connected = true;
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
    connectAttempts++;
    connected = true;
  }

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    attempts.add(methodName);
    if (!connected) {
      return false;
    }
    invocations.add(methodName);
    if (methodName == PlayGameHubEvents.createPrivateGame) {
      createArgs.add(args);
    }
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

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;

  Future<void> setUpContainer() async {
    SharedPreferences.setMockInitialValues({'user_id': _localId});
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider
            .overrideWithValue(_FakeHubBindings(signalR)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(sub.close);
  }

  GameController notifier() => container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  /// The private entry, minus the widget: the same two controller calls
  /// GameControllerScreen._startPrivateGame makes around its connect step.
  Future<bool> enterPrivateLobby() async {
    notifier().enterPrivateLobby();
    return notifier().createPrivateGame(_interestIds);
  }

  setUp(() async => setUpContainer());

  group('A. already connected', () {
    test('entering the lobby creates the game at once and starts no '
        'connection', () async {
      signalR.connected = true;

      final sent = await enterPrivateLobby();

      expect(sent, isTrue);
      expect(signalR.creates, hasLength(1));
      expect(signalR.createArgs.single, [_interestIds],
          reason: 'one hub parameter, which is itself the list — unchanged');
      expect(signalR.connectAttempts, 0,
          reason: 'neither connect() nor recoverConnection() may be called '
              'when the hub is already up');
      expect(current().phase, GamePhase.lobbyPrivate,
          reason: 'the lobby is shown regardless — routing is unchanged');
    });

    test('a second entry does not create a second game', () async {
      signalR.connected = true;

      await enterPrivateLobby();
      // Re-entering resets the guard by design, but the create itself is
      // still one per entry — this is the repeated-dispatch case.
      await notifier().createPrivateGame(_interestIds);
      await notifier().createPrivateGame(_interestIds);

      expect(signalR.creates, hasLength(1));
      expect(signalR.connectAttempts, 0);
    });
  });

  group('B. disconnected', () {
    test('entering the lobby dispatches nothing and starts no connection of '
        'its own', () async {
      final sent = await enterPrivateLobby();

      expect(sent, isFalse);
      expect(signalR.creates, isEmpty,
          reason: 'nothing may ride a hub that is not connected');
      expect(signalR.attempts, isEmpty,
          reason: 'not even attempted — a refused invoke still leaves the '
              'device and loses the create silently');
      expect(signalR.connectAttempts, 0,
          reason: 'GameControllerScreen owns the connect; the private lobby '
              'must not start a second one');
    });

    test('the lobby is still shown while the create waits', () async {
      await enterPrivateLobby();

      expect(current().phase, GamePhase.lobbyPrivate,
          reason: 'the deferral is about the dispatch, not the routing');
    });

    test('the guard stays open, so the create is still owed', () async {
      await enterPrivateLobby();
      expect(signalR.creates, isEmpty);

      signalR.connected = true;
      final sent = await notifier().createPrivateGame(_interestIds);

      expect(sent, isTrue);
      expect(signalR.creates, hasLength(1));
    });

    test('once the entry connect lands, recovery creates the game exactly '
        'once', () async {
      await enterPrivateLobby();
      expect(signalR.creates, isEmpty);

      // The entry's connect completes; the service notifies recovery.
      signalR.connected = true;
      await notifier().onRecovered();

      expect(
        signalR.invocations,
        [
          PlayGameHubEvents.checkPlayerGame,
          PlayGameHubEvents.createPrivateGame,
        ],
        reason: 'CheckPlayerGame first, then the deferred create',
      );
      expect(signalR.createArgs.single, [_interestIds],
          reason: 'the interest ids the entry asked for, replayed verbatim');
    });

    test('a connect still in flight does not dispatch either', () async {
      // hasLiveConnection would be true mid-connect in the real service; the
      // gate reads isConnected precisely so this case is still refused.
      signalR.connected = false;
      await enterPrivateLobby();

      expect(signalR.creates, isEmpty);
      expect(signalR.attempts, isEmpty);
    });

    test('a hub that never comes up never creates', () async {
      await enterPrivateLobby();
      await notifier().onRecovered();
      await notifier().createPrivateGame(_interestIds);

      expect(signalR.creates, isEmpty);
      expect(signalR.checks, isEmpty,
          reason: 'CheckPlayerGame is itself refused by a down hub');
    });
  });

  group('C. concurrent and repeated entry', () {
    test('two callers arriving together create exactly once', () async {
      signalR.connected = true;
      notifier().enterPrivateLobby();

      await Future.wait([
        notifier().createPrivateGame(_interestIds),
        notifier().createPrivateGame(_interestIds),
      ]);

      expect(signalR.creates, hasLength(1),
          reason: 'the flag is claimed before the await');
    });

    test('a deferred entry plus a concurrent recovery still creates once',
        () async {
      await enterPrivateLobby();
      signalR.connected = true;

      await Future.wait([
        notifier().createPrivateGame(_interestIds),
        notifier().onRecovered(),
      ]);

      expect(signalR.creates, hasLength(1));
    });

    test('repeated recoveries do not stack creates', () async {
      await enterPrivateLobby();
      signalR.connected = true;

      await notifier().onRecovered();
      await notifier().onRecovered();
      await notifier().onRecovered();

      expect(signalR.creates, hasLength(1));
      expect(signalR.checks, hasLength(3),
          reason: 'CheckPlayerGame is per recovery, and is unchanged');
    });

    test('no caller in the private flow starts a connection', () async {
      await enterPrivateLobby();
      signalR.connected = true;
      await notifier().onRecovered();
      await notifier().createPrivateGame(_interestIds);

      expect(signalR.connectAttempts, 0,
          reason: 'exactly one owner — GameControllerScreen — and it is not '
              'exercised here');
    });
  });

  group('D. the recovery retry is owed, not automatic', () {
    test('a recovery with no private entry behind it creates nothing',
        () async {
      signalR.connected = true;

      await notifier().onRecovered();

      expect(signalR.creates, isEmpty,
          reason: 'a reconnect alone is not a reason to create a game');
      expect(signalR.checks, hasLength(1));
    });

    test('a create that already succeeded is not re-issued on recovery',
        () async {
      signalR.connected = true;
      await enterPrivateLobby();
      expect(signalR.creates, hasLength(1));

      await notifier().onRecovered();

      expect(signalR.creates, hasLength(1));
    });

    test('re-entering the lobby drops the previous entry\'s owed create',
        () async {
      await enterPrivateLobby();

      // A fresh entry replaces the session; the old owed create ends with it.
      notifier().enterPrivateLobby();
      signalR.connected = true;
      await notifier().onRecovered();

      expect(signalR.creates, isEmpty,
          reason: 'the new entry records its own ids when it asks');
    });

    test('a session past the private lobby is not created on recovery',
        () async {
      await enterPrivateLobby();
      signalR.connected = true;
      notifier().applySessionEvent(PlayGameHubEvents.gameStarted, {
        'id': 'g1',
        'status': 3,
        'type': 1,
        'groupId': 'grp',
        'players': [
          {'id': _localId, 'playerName': 'me'},
        ],
      });

      await notifier().onRecovered();

      expect(signalR.creates, isEmpty);
      expect(signalR.checks, hasLength(1),
          reason: 'CheckPlayerGame still runs on every recovery');
    });
  });

  group('E. behaviour deliberately preserved', () {
    test('a concluded game is never created, connected or not', () async {
      signalR.connected = true;
      notifier().enterPrivateLobby();
      notifier().endGame(result: GameResult.ended);

      expect(await notifier().createPrivateGame(_interestIds), isFalse,
          reason: 'the existing result guard is unchanged');
      expect(signalR.creates, isEmpty);
    });

    test('a dispatch the hub refuses reopens the guard', () async {
      final refusing = _RefusingSignalRService();
      final local = ProviderContainer(
        overrides: [
          sharedPrefsProvider
              .overrideWithValue(container.read(sharedPrefsProvider)),
          signalRServiceProvider.overrideWithValue(refusing),
          playGameHubBindingsProvider
              .overrideWithValue(_FakeHubBindings(refusing)),
        ],
      );
      addTearDown(local.dispose);
      final sub = local.listen(gameControllerProvider, (_, __) {});
      addTearDown(sub.close);

      final controller = local.read(gameControllerProvider.notifier);
      controller.enterPrivateLobby();
      await controller.createPrivateGame(_interestIds);
      expect(refusing.attempts, 1);

      await controller.createPrivateGame(_interestIds);
      expect(refusing.attempts, 2,
          reason: 'the guard reopened, so a retry is still possible');
    });

    test('JoinPrivateGame is untouched by this change', () async {
      signalR.connected = true;
      notifier().enterPrivateLobby();

      expect(await notifier().joinPrivateGame('ABC123'), isTrue);
      expect(
        signalR.invocations,
        [PlayGameHubEvents.joinPrivateGame],
        reason: 'the join path keeps its own separate guard and behaviour',
      );
    });
  });
}

/// Reports connected but refuses every dispatch — the `sent == false` arm.
class _RefusingSignalRService extends SignalRService {
  int attempts = 0;

  @override
  bool get isConnected => true;

  @override
  bool get hasLiveConnection => true;

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    if (methodName == PlayGameHubEvents.createPrivateGame) {
      attempts++;
    }
    return false;
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
