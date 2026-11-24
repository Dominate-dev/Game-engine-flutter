import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Events for another game must never change the one being played.
//
// The hub delivers by user, not by game, so a player can still receive events
// from a game they just left (a late GameOver, a ChangeTurn, the next
// question) while a new one is running. Before this guard the controller
// applied them to whatever game was on screen: a stale GameOver ended a live
// game, a stale question replaced the current one.

const _localId = '47';
const _opponentId = '211403';
const _gameA = '0f8fad5b-d9cb-469f-a165-70867728950e';
const _gameB = '7c9e6679-7425-40de-944b-e07fc1f90ae7';

const _players = [
  {'id': _localId, 'playerName': 'me'},
  {'id': _opponentId, 'playerName': 'them'},
];

Map<String, dynamic> _gameJson(String id, {int status = 3, int type = 1, String? currentTurn}) => {
      'id': id,
      'status': status,
      'type': type,
      'groupId': 'grp',
      'players': _players,
      if (currentTurn != null) 'currentTurn': currentTurn,
    };

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

  void emit(String name, [Map<String, dynamic>? data]) =>
      _events.add(GameHubEvent(name: name, data: data));

  @override
  void dispose() {
    _events.close();
  }
}

void main() {
  group('HubEventPayload keeps the game id', () {
    test('a trailing game id survives a map-first payload', () {
      final data = HubEventPayload.mapFromArgs([
        {'id': 5, 'text': 'q'},
        _gameA,
      ]);
      expect(data?['text'], 'q');
      expect(HubEventPayload.gameIdOf(data), _gameA);
    });

    test('every positional argument is kept, so a fourth one is not lost', () {
      final data = HubEventPayload.mapFromArgs(['text', 'textEn', _localId, _gameA]);
      expect(data?['arg3'], _gameA);
      expect(HubEventPayload.gameIdOf(data), _gameA);
    });

    test('a player id is never mistaken for a game id', () {
      final data = HubEventPayload.mapFromArgs([_localId]);
      expect(HubEventPayload.gameIdOf(data), isNull);
    });
  });

  group('controller ignores events for another game', () {
    late ProviderContainer container;
    late _FakeHubBindings bindings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'user_id': _localId,
        'app_language': AppLanguage.english,
      });
      final prefs = await SharedPrefsService.init();
      final signalR = _FakeSignalRService();
      bindings = _FakeHubBindings(signalR);
      container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          signalRServiceProvider.overrideWithValue(signalR),
          playGameHubBindingsProvider.overrideWithValue(bindings),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(gameControllerProvider, (_, __) {});
      addTearDown(sub.close);
    });

    GameSessionState current() => container.read(gameControllerProvider);

    Future<void> emit(String name, Map<String, dynamic>? data) async {
      bindings.emit(name, data);
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> playGameA() async {
      await emit(PlayGameHubEvents.gameStarted,
          HubEventPayload.mapFromArgs([_gameJson(_gameA), _gameA]));
      expect(current().game?.id, _gameA, reason: 'sanity');
    }

    test('a GameOver from another game does not end this one', () async {
      await playGameA();

      await emit(PlayGameHubEvents.gameOver, {
        'gameId': _gameB,
        'winnerId': _opponentId,
        'gameResultPlayers': <dynamic>[],
      });

      expect(current().result, isNull);
    });

    test('a turn change from another game does not move this one', () async {
      await playGameA();
      final turn = current().game?.currentTurn;

      await emit(PlayGameHubEvents.changeTurn,
          HubEventPayload.mapFromArgs([_opponentId, _gameB]));

      expect(current().game?.currentTurn, turn);
    });

    test('a GameUpdated from another game does not replace this one', () async {
      await playGameA();

      await emit(PlayGameHubEvents.gameUpdated,
          HubEventPayload.mapFromArgs([_gameJson(_gameB, type: 2), _gameB]));

      expect(current().game?.id, _gameA);
    });

    test('events for this game still apply', () async {
      await playGameA();

      await emit(PlayGameHubEvents.gameOver, {
        'gameId': _gameA,
        'winnerId': _localId,
        'gameResultPlayers': <dynamic>[],
      });

      expect(current().result, isNotNull);
    });

    test("GameRestore is the server's word and is always applied", () async {
      await playGameA();

      await emit(PlayGameHubEvents.gameRestore,
          HubEventPayload.mapFromArgs([_gameJson(_gameB, type: 2)]));

      expect(current().game?.id, _gameB);
    });
  });
}
