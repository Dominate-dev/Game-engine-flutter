import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Seating and identity resolution.
//
// Backend semantics these tests encode (confirmed by the repository owner):
//   - The persisted login user_id and hub player ids share one namespace.
//   - Hub player values can name EITHER player; they are not inherently local.
//   - PlayerLeft arrives as [playerId, gameId] and carries the player id
//     directly: playerId == persisted user_id means the local player left.
//
// Ids below use the observed session: 47 = local player, 211403 = opponent.

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

Map<String, dynamic> _playerJson(
  String id, {
  String? userId,
  int? penalty,
  int? points,
}) =>
    {
      'id': id,
      if (userId != null) 'userId': userId,
      'playerName': 'p$id',
      if (penalty != null) 'penalty': penalty,
      if (points != null) 'points': points,
    };

Map<String, dynamic> _lobbyJson(List<Map<String, dynamic>> players) => {
      'id': 'g1',
      'status': 2,
      'type': 1,
      'groupId': 'grp',
      'players': players,
    };

// A WDYK game already in progress (status 3, type 1).
Map<String, dynamic> _roundJson(List<Map<String, dynamic>> players) => {
      'id': 'g1',
      'status': 3,
      'type': 1,
      'groupId': 'grp',
      'players': players,
    };

// The same round with no 'status' field. It parses as 0, which
// StatusGame.fromId leaves unmapped.
Map<String, dynamic> _statuslessRoundJson(
  List<Map<String, dynamic>> players,
) =>
    {
      'id': 'g1',
      'type': 1,
      'groupId': 'grp',
      'players': players,
    };

// PlayerLeft [playerId, gameId] as the hub delivers it — positional args
// normalised by the real HubEventPayload, not a hand-built map.
Map<String, dynamic>? _positionalPlayerLeft(String playerId) =>
    HubEventPayload.mapFromArgs([playerId, 'g1']);

void main() {
  late ProviderContainer container;

  Future<void> setUpContainer({String userId = _localId}) async {
    SharedPreferences.setMockInitialValues({'user_id': userId});
    final prefs = await SharedPrefsService.init();
    final signalR = _FakeSignalRService();
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

  void seatBothPlayers({bool localFirst = true}) {
    final players = localFirst
        ? [_playerJson(_localId), _playerJson(_opponentId)]
        : [_playerJson(_opponentId), _playerJson(_localId)];
    notifier().applySessionEvent(
      PlayGameHubEvents.gameJoined,
      _lobbyJson(players),
    );
  }

  setUp(() async => setUpContainer());

  group('seating', () {
    test('local player seated as me when listed first', () {
      seatBothPlayers(localFirst: true);
      expect(current().me?.id, _localId);
      expect(current().opponent?.id, _opponentId);
    });

    test('local player seated as me when listed second', () {
      seatBothPlayers(localFirst: false);
      expect(current().me?.id, _localId);
      expect(current().opponent?.id, _opponentId);
    });

    test('local player matched on the account userId when ids are opaque', () {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameJoined,
        _lobbyJson([
          _playerJson('guid-a', userId: _opponentId),
          _playerJson('guid-b', userId: _localId),
        ]),
      );
      expect(current().me?.id, 'guid-b');
      expect(current().opponent?.id, 'guid-a');
    });

    test('a roster containing only the local player has no opponent', () {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameJoined,
        _lobbyJson([_playerJson(_localId)]),
      );
      expect(current().me?.id, _localId);
      expect(current().opponent, isNull);
    });

    // S9b: seating by list position could seat the local user as the wrong
    // player. With no identity match, seats must be left alone.
    test('a roster with no matching id does not seat anyone by position', () {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameJoined,
        _lobbyJson([_playerJson('900'), _playerJson('901')]),
      );
      expect(current().me, isNull);
      expect(current().opponent, isNull);
    });

    test('a roster of strangers does not displace already-seated players', () {
      seatBothPlayers();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _lobbyJson([_playerJson('900'), _playerJson('901')]),
      );
      expect(current().me?.id, _localId);
      expect(current().opponent?.id, _opponentId);
    });
  });

  group('isCurrentUser', () {
    test('the local id is the current user', () {
      seatBothPlayers();
      expect(notifier().isCurrentUser(_localId), isTrue);
    });

    test('the opponent id is not the current user', () {
      seatBothPlayers();
      expect(notifier().isCurrentUser(_opponentId), isFalse);
    });

    // S9: the old logic returned true for anything that was not the opponent.
    test('an id belonging to neither player is not the current user', () {
      seatBothPlayers();
      expect(notifier().isCurrentUser('999999'), isFalse);
    });

    // S9: with no opponent seated the old logic claimed every id was local.
    test('resolution does not depend on an opponent being seated', () {
      expect(current().opponent, isNull);
      expect(notifier().isCurrentUser(_localId), isTrue);
      expect(notifier().isCurrentUser(_opponentId), isFalse);
      expect(notifier().isCurrentUser('999999'), isFalse);
    });

    test('null and empty ids are never the current user', () {
      expect(notifier().isCurrentUser(null), isFalse);
      expect(notifier().isCurrentUser(''), isFalse);
    });

    test('id comparison tolerates whitespace and numeric formatting', () {
      expect(notifier().isCurrentUser(' 47 '), isTrue);
      expect(notifier().isCurrentUser('047'), isTrue);
    });
  });

  group('PlayerLeft routing', () {
    test('positional [47, gameId] reports the local player as having left', () {
      seatBothPlayers();
      expect(
        notifier().isLocalPlayerLeft(_positionalPlayerLeft(_localId)),
        isTrue,
      );
    });

    test('positional [211403, gameId] reports the opponent as having left', () {
      seatBothPlayers();
      expect(
        notifier().isLocalPlayerLeft(_positionalPlayerLeft(_opponentId)),
        isFalse,
      );
    });

    test('map-shaped payloads resolve identically to positional ones', () {
      seatBothPlayers();
      expect(
        notifier().isLocalPlayerLeft({'playerId': _localId}),
        isTrue,
      );
      expect(
        notifier().isLocalPlayerLeft({'playerId': _opponentId}),
        isFalse,
      );
    });

    // S9a: positional payloads previously yielded no id at all, so a local
    // departure was never detected regardless of who left.
    test('resolution does not depend on an opponent being seated', () {
      expect(current().opponent, isNull);
      expect(
        notifier().isLocalPlayerLeft(_positionalPlayerLeft(_localId)),
        isTrue,
      );
      expect(
        notifier().isLocalPlayerLeft(_positionalPlayerLeft(_opponentId)),
        isFalse,
      );
    });

    test('a payload with no identifiable player is not the local user', () {
      expect(notifier().isLocalPlayerLeft(null), isFalse);
      expect(notifier().isLocalPlayerLeft({}), isFalse);
      expect(notifier().isLocalPlayerLeft({'playerId': ''}), isFalse);
    });

    test('the opponent leaving removes them from the lobby roster', () {
      seatBothPlayers();
      final localLeft =
          notifier().onLobbyPlayerLeft({'playerId': _opponentId});
      expect(localLeft, isFalse);
      expect(current().game?.players?.map((p) => p.id), [_localId]);
    });
  });

  // W-1: shared round events refreshed the game snapshot but left
  // state.me / state.opponent frozen, so the WDYK score and strike UI —
  // which read those two fields — went stale for the whole round.
  group('round-event player refresh', () {
    void startWdykRound() {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _roundJson([
          _playerJson(_localId, penalty: 0, points: 0),
          _playerJson(_opponentId, penalty: 0, points: 0),
        ]),
      );
    }

    test('a round event carrying an updated roster refreshes both seats', () {
      startWdykRound();
      expect(current().phase, GamePhase.wdyk);
      expect(current().me?.penalty, 0);
      expect(current().me?.points, 0);

      notifier().applySharedRoundEvent(PlayGameHubEvents.penalty, {
        'players': [
          _playerJson(_localId, penalty: 2, points: 10),
          _playerJson(_opponentId, penalty: 1, points: 5),
        ],
      });

      expect(current().me?.id, _localId);
      expect(current().me?.penalty, 2);
      expect(current().me?.points, 10);
      expect(current().opponent?.id, _opponentId);
      expect(current().opponent?.penalty, 1);
      expect(current().opponent?.points, 5);
    });

    test('the roster refresh does not depend on the local player position', () {
      startWdykRound();
      notifier().applySharedRoundEvent(PlayGameHubEvents.correctAnswer, {
        'players': [
          _playerJson(_opponentId, penalty: 3, points: 1),
          _playerJson(_localId, penalty: 0, points: 20),
        ],
      });

      expect(current().me?.id, _localId);
      expect(current().me?.points, 20);
      expect(current().opponent?.id, _opponentId);
      expect(current().opponent?.penalty, 3);
    });

    // S9: seats move only on a positive match against the persisted user_id.
    test('a roster naming neither player leaves the seats alone', () {
      startWdykRound();
      notifier().applySharedRoundEvent(PlayGameHubEvents.penalty, {
        'players': [
          _playerJson('900', penalty: 3, points: 99),
          _playerJson('901', penalty: 3, points: 99),
        ],
      });

      expect(current().me?.id, _localId);
      expect(current().me?.penalty, 0);
      expect(current().opponent?.id, _opponentId);
    });

    test('a round event with no roster leaves the seats alone', () {
      startWdykRound();
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.timeStarted,
        HubEventPayload.mapFromArgs(['', 'g1']),
      );

      expect(current().me?.id, _localId);
      expect(current().me?.penalty, 0);
      expect(current().opponent?.id, _opponentId);
      expect(current().game?.isTimerStarted, isTrue);
    });
  });

  // The same refresh, reached through the other branch of
  // applySharedRoundEvent. A game snapshot with no `status` parses as 0,
  // which StatusGame.fromId leaves unmapped, so _routeByStatus declines and
  // the event falls through to the generic tail — the path that never
  // reseated. GameStarted carries the round without repeating the status.
  group('round-event player refresh — unrouted status', () {
    void startWdykRoundWithoutStatus() {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _statuslessRoundJson([
          _playerJson(_localId, penalty: 0, points: 0),
          _playerJson(_opponentId, penalty: 0, points: 0),
        ]),
      );
    }

    test('a tail-routed round event refreshes both seats', () {
      startWdykRoundWithoutStatus();
      expect(current().phase, GamePhase.wdyk);
      expect(current().me?.penalty, 0);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.penalty,
        _statuslessRoundJson([
          _playerJson(_localId, penalty: 2, points: 10),
          _playerJson(_opponentId, penalty: 1, points: 5),
        ]),
      );

      expect(current().me?.id, _localId);
      expect(current().me?.penalty, 2);
      expect(current().me?.points, 10);
      expect(current().opponent?.id, _opponentId);
      expect(current().opponent?.penalty, 1);
      expect(current().opponent?.points, 5);
    });

    test('a tail-routed roster naming neither player leaves the seats alone',
        () {
      startWdykRoundWithoutStatus();
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.penalty,
        _statuslessRoundJson([
          _playerJson('900', penalty: 3, points: 99),
          _playerJson('901', penalty: 3, points: 99),
        ]),
      );

      expect(current().me?.id, _localId);
      expect(current().me?.penalty, 0);
      expect(current().opponent?.id, _opponentId);
    });

    test('the round-specific mutation still applies alongside the refresh', () {
      startWdykRoundWithoutStatus();
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.timeStarted,
        _statuslessRoundJson([
          _playerJson(_localId, penalty: 1, points: 4),
          _playerJson(_opponentId, penalty: 0, points: 0),
        ]),
      );

      expect(current().me?.penalty, 1);
      expect(current().game?.isTimerStarted, isTrue);
    });
  });

  // W-IMPL residual, now closed: the session-path twin of the round-path
  // reseat covered by 'round-event player refresh' above. An event routed
  // through applySessionEvent whose phase cannot be resolved took the
  // `phase == null` branch, which replaced `game` but left me/opponent
  // holding the previous roster.
  group('session-event player refresh — unresolvable phase', () {
    /// A payload with no status, no screen/round/roundType and no usable
    /// type, so _routeByStatus fails and no phase can be derived — the exact
    /// shape that reaches the branch.
    Map<String, dynamic> unroutable(List<Map<String, dynamic>> players) => {
          'id': 'g1',
          'groupId': 'grp',
          'status': null,
          'type': null,
          'players': players,
        };

    test('a refreshed roster reseats me and opponent', () {
      seatBothPlayers();
      expect(current().me?.penalty, isNot(2), reason: 'sanity');

      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        unroutable([
          _playerJson(_localId, penalty: 2),
          _playerJson(_opponentId, penalty: 1),
        ]),
      );

      expect(current().me?.id, _localId);
      expect(current().me?.penalty, 2,
          reason: 'before the fix this kept the previously seated roster');
      expect(current().opponent?.penalty, 1);
    });

    test('the game snapshot is still applied alongside the reseat', () {
      seatBothPlayers();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        unroutable([_playerJson(_localId, penalty: 3)]),
      );

      expect(current().game?.id, 'g1');
      expect(current().lastEventName, PlayGameHubEvents.gameUpdated);
    });

    test('seating survives a swapped roster order', () {
      seatBothPlayers();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        unroutable([
          _playerJson(_opponentId, penalty: 1),
          _playerJson(_localId, penalty: 2),
        ]),
      );

      expect(current().me?.id, _localId,
          reason: 'identity, not list position, decides the seat');
      expect(current().opponent?.id, _opponentId);
    });

    test('an empty roster does not wipe the seated players', () {
      seatBothPlayers();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        unroutable(const []),
      );

      expect(current().me?.id, _localId,
          reason: '_findPlayers returns the existing seats for an empty list');
      expect(current().opponent?.id, _opponentId);
    });

    test('a roster that does not name me leaves both seats untouched',
        () {
      seatBothPlayers();
      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        unroutable([_playerJson(_opponentId, penalty: 3)]),
      );

      // _findPlayers makes no positional guess: without me in the roster it
      // returns the existing pair rather than reseating from position, so
      // the reseat added here inherits that safety rather than overriding it.
      expect(current().me?.id, _localId);
      expect(current().opponent?.id, _opponentId);
      expect(current().opponent?.penalty, 0,
          reason: 'the partial roster is not applied — seating the wrong '
              'player is worse than seating none');
    });
  });
}
