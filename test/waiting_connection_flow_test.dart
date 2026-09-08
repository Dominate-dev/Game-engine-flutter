import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The Waiting entry connection flow.
//
// Ownership, traced through the code rather than assumed:
//   GameControllerScreen.initState -> post-frame -> _ensureHubConnected()
//     is the ONLY place the public entry starts a connection.
//   WaitingScreen.initState -> post-frame -> onWaitingShown()
//     dispatches the join, and must not start a second connection.
//
// So `onWaitingShown` gates on the connection instead of establishing one:
//   already connected -> dispatch JoinRandomGame now
//   not connected     -> dispatch nothing, and let the entry's connect land.
//                        `recoveredStream` then fires `onRecovered`, which
//                        runs CheckPlayerGame and re-enters onWaitingShown
//                        with the guard still open.
//
// `isConnected`, not `hasLiveConnection`: the latter is also true mid-connect,
// and a connect in flight must not carry a join.

const _localId = '47';

/// Models the socket the way the service does: `isConnected` is the state the
/// gate reads, and `invoke` only reaches the wire when it is true.
class _FakeSignalRService extends SignalRService {
  final invocations = <String>[];

  /// Every invoke() call, whether or not the hub accepted it. `invocations`
  /// only records accepted ones, so a dispatch attempted on a down hub
  /// would otherwise be invisible — and "never invoke while disconnected"
  /// is precisely what this file has to prove.
  final attempts = <String>[];

  bool connected = false;

  /// Counts any attempt to establish a connection, so a second owner would
  /// be visible.
  int connectAttempts = 0;

  List<String> get joins =>
      invocations.where((m) => m == PlayGameHubEvents.joinRandomGame).toList();

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

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  setUp(() async => setUpContainer());

  group('A. already connected', () {
    test('entering Waiting starts no connection and joins once', () async {
      signalR.connected = true;

      await notifier().onWaitingShown();

      expect(signalR.connectAttempts, 0,
          reason: 'neither connect() nor recoverConnection() may be called '
              'when the hub is already up');
      expect(signalR.joins, hasLength(1));
    });

    test('a second entry does not join again', () async {
      signalR.connected = true;

      await notifier().onWaitingShown();
      await notifier().onWaitingShown();

      expect(signalR.joins, hasLength(1));
      expect(signalR.connectAttempts, 0);
    });

    test('recovery on an already-connected hub still runs the existing '
        'CheckPlayerGame -> JoinRandomGame flow', () async {
      signalR.connected = true;

      await notifier().onRecovered();

      expect(
        signalR.invocations,
        [PlayGameHubEvents.checkPlayerGame, PlayGameHubEvents.joinRandomGame],
        reason: 'CheckPlayerGame first, then the join — unchanged',
      );
    });
  });

  group('B. disconnected', () {
    test('entering Waiting dispatches nothing and starts no connection of '
        'its own', () async {
      await notifier().onWaitingShown();

      expect(signalR.joins, isEmpty,
          reason: 'nothing may ride a hub that is not connected');
      expect(signalR.attempts, isEmpty,
          reason: 'not even attempted — a refused invoke still leaves the '
              'device and loses the join silently');
      expect(signalR.connectAttempts, 0,
          reason: 'GameControllerScreen owns the connect; Waiting must not '
              'start a second one');
    });

    test('the guard stays open, so the join is still owed', () async {
      await notifier().onWaitingShown();
      expect(signalR.joins, isEmpty);

      signalR.connected = true;
      await notifier().onWaitingShown();

      expect(signalR.joins, hasLength(1));
    });

    test('once the entry connect lands, recovery runs CheckPlayerGame then '
        'the join', () async {
      await notifier().onWaitingShown();
      expect(signalR.joins, isEmpty);

      // The entry's connect completes; the service notifies recovery.
      signalR.connected = true;
      await notifier().onRecovered();

      expect(
        signalR.invocations,
        [PlayGameHubEvents.checkPlayerGame, PlayGameHubEvents.joinRandomGame],
      );
    });

    test('a connect still in flight does not dispatch either', () async {
      // hasLiveConnection would be true mid-connect in the real service; the
      // gate reads isConnected precisely so this case is still refused.
      signalR.connected = false;
      await notifier().onWaitingShown();

      expect(signalR.joins, isEmpty);
      expect(signalR.attempts, isEmpty);
    });

    test('a hub that never comes up never joins', () async {
      await notifier().onWaitingShown();
      await notifier().onRecovered();
      await notifier().onWaitingShown();

      expect(signalR.joins, isEmpty);
      expect(signalR.checks, isEmpty,
          reason: 'CheckPlayerGame is itself refused by a down hub');
    });
  });

  group('C. concurrent entry and recovery', () {
    test('two callers arriving together join exactly once', () async {
      signalR.connected = true;

      await Future.wait([
        notifier().onWaitingShown(),
        notifier().onRecovered(),
      ]);

      expect(signalR.joins, hasLength(1));
    });

    test('repeated recoveries do not stack joins', () async {
      await notifier().onWaitingShown();
      signalR.connected = true;

      await notifier().onRecovered();
      await notifier().onRecovered();
      await notifier().onRecovered();

      expect(signalR.joins, hasLength(1));
      expect(signalR.checks, hasLength(3),
          reason: 'CheckPlayerGame is per recovery, and is unchanged');
    });

    test('no caller in the Waiting flow starts a connection', () async {
      await notifier().onWaitingShown();
      signalR.connected = true;
      await notifier().onRecovered();
      await notifier().onWaitingShown();

      expect(signalR.connectAttempts, 0,
          reason: 'exactly one owner — GameControllerScreen — and it is not '
              'exercised here');
    });
  });

  group('E. behaviour deliberately preserved', () {
    test('a concluded game is never joined, connected or not', () async {
      signalR.connected = true;
      notifier().endGame(result: GameResult.ended);

      await notifier().onWaitingShown();

      expect(signalR.joins, isEmpty, reason: 'R-07 guard is unchanged');
    });

    test('a session past waiting is not joined on recovery', () async {
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

      expect(signalR.joins, isEmpty);
      expect(signalR.checks, hasLength(1),
          reason: 'CheckPlayerGame still runs on every recovery');
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
      await controller.onWaitingShown();
      expect(refusing.attempts, 1);

      await controller.onWaitingShown();
      expect(refusing.attempts, 2,
          reason: 'the guard reopened, so a retry is still possible');
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
    if (methodName == PlayGameHubEvents.joinRandomGame) {
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
