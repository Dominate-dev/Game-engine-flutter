import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// onWaitingGameUpdated ignored `status` entirely and always opened Lobby,
// unlike onWaitingGameRestore's sibling handling of the same event while
// waiting. Now routes by status first, via the same _routeByStatus every
// other GameUpdated handler already uses, falling back to Lobby only when
// status can't be resolved (this event's own pre-existing default).

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async => true;

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

Map<String, dynamic> _gameJson({
  required int status,
  int type = 1,
  List<Map<String, dynamic>>? players,
}) =>
    {
      'id': 'g1',
      'status': status,
      'type': type,
      'groupId': 'grp',
      if (players != null) 'players': players,
    };

const _players = [
  {'id': _localId, 'playerName': 'me'},
  {'id': _opponentId, 'playerName': 'them'},
];

void main() {
  late ProviderContainer container;

  Future<void> setUpContainer() async {
    SharedPreferences.setMockInitialValues({'user_id': _localId});
    final prefs = await SharedPrefsService.init();
    final signalR = _FakeSignalRService();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider.overrideWithValue(_FakeHubBindings(signalR)),
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

  group('R-14 — onWaitingGameUpdated routes by status', () {
    test('status 2 (isReady) still goes to Lobby — unaffected baseline',
        () {
      expect(current().phase, GamePhase.waiting, reason: 'sanity');

      notifier().onWaitingGameUpdated(_gameJson(status: 2, players: _players));

      expect(current().phase, GamePhase.lobbyPlay);
      expect(current().me?.id, _localId);
      expect(current().opponent?.id, _opponentId);
    });

    test(
      'status 1 (waitingPlayers) stays on Waiting — the confirmed fix: '
      'still searching for a second player must not jump to Lobby early',
      () {
        notifier().onWaitingGameUpdated(_gameJson(status: 1));

        expect(current().phase, GamePhase.waiting);
      },
    );

    test(
      'status 3 (inProgress) routes to the round named by type, not Lobby '
      '— a reconnect landing mid-search on a game already under way',
      () {
        notifier().onWaitingGameUpdated(
          _gameJson(status: 3, type: 3, players: _players), // Bell
        );

        expect(current().phase, GamePhase.bell);
      },
    );

    test(
      'status 4 (ended) ends the game rather than opening Lobby on a '
      'finished match',
      () {
        notifier().onWaitingGameUpdated(_gameJson(status: 4));

        expect(current().result, GameResult.ended);
      },
    );

    test(
      'status absent falls back to the original, unchanged behavior — '
      'straight to Lobby',
      () {
        notifier().onWaitingGameUpdated({
          'id': 'g1',
          'groupId': 'grp',
          'players': _players,
        });

        expect(current().phase, GamePhase.lobbyPlay);
      },
    );

    test(
      'an unrecognized status value also falls back to the original Lobby '
      'default',
      () {
        notifier().onWaitingGameUpdated(_gameJson(status: 99));

        expect(current().phase, GamePhase.lobbyPlay);
      },
    );
  });
}
