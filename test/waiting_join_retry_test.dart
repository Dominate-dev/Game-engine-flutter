import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// S5 — the join guard must close only on a dispatched JoinRandomGame, and a
// recovery must re-attempt the join only while the session is still waiting.
//
// _didJoinRandom is private, so it is observed through invocation counts,
// which is what actually matters to a player.

const _localId = '47';

class _FakeSignalRService extends SignalRService {
  final invocations = <String>[];

  /// Drives invoke()'s return the way a real disconnected hub would.
  bool connected = true;

  /// The socket state a real hub reports. onWaitingShown gates on this, so
  /// the fake must answer it with the same truth it gives invoke().
  @override
  bool get isConnected => connected;

  List<String> get joins =>
      invocations.where((m) => m == PlayGameHubEvents.joinRandomGame).toList();

  List<String> get checks => invocations
      .where((m) => m == PlayGameHubEvents.checkPlayerGame)
      .toList();

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
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

Map<String, dynamic> _gameJson({required int status, int type = 1}) => {
      'id': 'g1',
      'status': status,
      'type': type,
      'groupId': 'grp',
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': '211403', 'playerName': 'them'},
      ],
    };

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
  GameSessionState current() => container.read(gameControllerProvider);

  setUp(() async => setUpContainer());

  group('the join guard closes only on a dispatched call', () {
    test('a dispatched join closes the guard', () async {
      await notifier().onWaitingShown();
      expect(signalR.joins, hasLength(1));

      await notifier().onWaitingShown();
      expect(signalR.joins, hasLength(1), reason: 'guard is closed');
    });

    test('a skipped join leaves the guard open', () async {
      signalR.connected = false;
      await notifier().onWaitingShown();
      expect(signalR.joins, isEmpty);

      signalR.connected = true;
      await notifier().onWaitingShown();
      expect(signalR.joins, hasLength(1), reason: 'retry was still allowed');
    });
  });

  group('recovery retries only a join that never went out', () {
    test('disconnected join, then recovery while still waiting, retries',
        () async {
      signalR.connected = false;
      await notifier().onWaitingShown();
      expect(signalR.joins, isEmpty);

      signalR.connected = true;
      await notifier().onRecovered();

      expect(current().phase, GamePhase.waiting);
      expect(signalR.checks, hasLength(1), reason: 'CheckPlayerGame first');
      expect(signalR.joins, hasLength(1), reason: 'join retried');
      expect(
        signalR.invocations,
        [PlayGameHubEvents.checkPlayerGame, PlayGameHubEvents.joinRandomGame],
        reason: 'recovery runs before the retry',
      );
    });

    test('a session that has moved out of waiting is not re-joined', () async {
      signalR.connected = false;
      await notifier().onWaitingShown();
      signalR.connected = true;

      // Recovery routed the player onward, as GameRestore would.
      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _gameJson(status: 2),
      );
      expect(current().phase, GamePhase.lobbyPlay);

      await notifier().onRecovered();

      expect(signalR.checks, hasLength(1));
      expect(signalR.joins, isEmpty, reason: 'already in a game');
    });

    test('an in-progress round is not re-joined either', () async {
      signalR.connected = false;
      await notifier().onWaitingShown();
      signalR.connected = true;

      notifier().applySessionEvent(
        PlayGameHubEvents.gameRestore,
        _gameJson(status: 3),
      );
      expect(current().phase, GamePhase.wdyk);

      await notifier().onRecovered();
      expect(signalR.joins, isEmpty);
    });

    test('an already-joined session is not re-joined on reconnect', () async {
      await notifier().onWaitingShown();
      expect(signalR.joins, hasLength(1));

      await notifier().onRecovered();

      expect(current().phase, GamePhase.waiting);
      expect(signalR.checks, hasLength(1));
      expect(signalR.joins, hasLength(1), reason: 'no duplicate join');
    });

    test('repeated recoveries do not stack joins once one succeeds', () async {
      signalR.connected = false;
      await notifier().onWaitingShown();
      signalR.connected = true;

      await notifier().onRecovered();
      await notifier().onRecovered();
      await notifier().onRecovered();

      expect(signalR.checks, hasLength(3));
      expect(signalR.joins, hasLength(1));
    });
  });

  group('existing recovery behaviour is preserved', () {
    test('onRecovered still invokes CheckPlayerGame', () async {
      await notifier().onRecovered();
      expect(signalR.checks, hasLength(1));
      expect(signalR.invocations.first, PlayGameHubEvents.checkPlayerGame);
    });

    test('CheckPlayerGame is invoked even when the retry does not fire',
        () async {
      await notifier().onWaitingShown();
      signalR.invocations.clear();

      await notifier().onRecovered();
      expect(signalR.invocations, [PlayGameHubEvents.checkPlayerGame]);
    });

    test('GameRestore routing is unchanged — waiting stays waiting', () {
      notifier().onWaitingGameRestore(_gameJson(status: 1));
      expect(current().phase, GamePhase.waiting);
    });

    test('GameRestore routing is unchanged — status routes onward', () {
      notifier().onWaitingGameRestore(_gameJson(status: 2));
      expect(current().phase, GamePhase.lobbyPlay);
    });

    test('GameRestore into an in-progress round still routes by type', () {
      notifier().onWaitingGameRestore(_gameJson(status: 3, type: 2));
      expect(current().phase, GamePhase.auction);
    });
  });
}
