import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// R-05 (final audit) — "GameRestore without a status field can fall back to
// stale state.phase".
//
// Inspection findings (verified by direct code reading, not guessed):
//   - applySessionEvent (game_controller.dart) tries _routeByStatus first
//     (status 1..4 -> waiting/lobby/round-by-type/ended). Only if that
//     returns false does a GameRestore fall through to its own branch, which
//     — before this fix — called `showPhase(state.phase, ...)`: the phase
//     the controller happened to be showing *before* the restore, not
//     anything derived from the restore itself.
//   - _routeByStatus derives its status from StatusGame.fromId(game?.status),
//     which returns null (routing fails) for: status genuinely absent from a
//     *first-ever* game (no previous CreatedGame to merge onto — fromJson's
//     default is 0, not in the 1..4 enum), status explicitly present as
//     `null` (see below), or status present but not one of 1..4.
//   - CreatedGameModel.merge (created_game_model.dart) treats status
//     differently depending on whether the key is *present*, not just
//     whether its value is meaningful:
//       * status ABSENT (JsonValue.hasField false) and a previous CreatedGame
//         exists -> merge passes `null` to CreatedGame.copyWith(status: ...),
//         whose `status ?? this.status` fallback then REUSES the previous
//         game's own (real, valid) status. In practice this means
//         _routeByStatus still succeeds off that carried-over status, and —
//         because StatusGame.inProgress routes through _goToRound, which
//         derives phase from the *merged* (fresh) `game.type` — the round
//         still ends up correct. This is the "absent status, prior game
//         exists" case, and it was already safe before this fix.
//       * status explicitly `null` (JsonValue.hasField true, the key exists)
//         -> merge computes `incoming.status` via GameJson.integer, which
//         coerces a null value to the sentinel `0` (not the 1..4 enum) —
//         *not* `null` — so copyWith's `??` fallback does NOT kick in and the
//         stale status is NOT reused. `game.status` becomes `0`,
//         StatusGame.fromId(0) is null, and _routeByStatus returns false.
//         This is the case that actually reaches applySessionEvent's own
//         GameRestore fallback.
//       * status present but unrecognized (e.g. 99) behaves the same way:
//         StatusGame.fromId(99) is null, _routeByStatus returns false.
//   - showPhase(phase, ...) sets `state.phase` to exactly the `phase`
//     argument it is given — it never re-derives phase from `game.type`
//     itself. So the old `showPhase(state.phase, ...)` fallback ignored
//     `game.type` entirely, even when the merged `game` (built from the very
//     same restore payload, one line above) reported a *different* round.
//   - GameType.fromId(int?).phase (game_type.dart) is the SAME, already-
//     established type -> phase mapping _goToRound already uses for every
//     other in-progress routing path (_routeByStatus's StatusGame.inProgress
//     case, GameStarted, NextRoundStarted). This is not an invented mapping.
//   - GamePhase == waiting or lobbyPlay never reaches this code at all:
//     _onHubEvent (the real bindings.stream pipeline) early-returns for any
//     event in waitingScreenEvents/lobbyScreenEvents (GameRestore is in
//     both) while state.phase is waiting/lobbyPlay — that event is instead
//     the exclusive responsibility of WaitingScreen/LobbyPlayGameScreen's own
//     onWaitingGameRestore/onLobbyGameRestore listener, which has its own,
//     separate, already-correct fallback (an explicit GamePhase.waiting, not
//     a stale value) and is unmodified by this task.
//
// Fix: applySessionEvent's GameRestore branch now tries
// GameType.fromId(game?.type)?.phase before falling back to state.phase —
// re-deriving the round from the same restore payload's own `type` field
// when status could not decide it, instead of blindly keeping whatever
// phase happened to be on screen already. When type cannot resolve either
// (still fully undetermined), the original, safe "stay on state.phase"
// behavior is unchanged — no phase is invented.

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

List<Map<String, dynamic>> _players() => [
      {'id': _localId, 'playerName': 'me'},
      {'id': _opponentId, 'playerName': 'them'},
    ];

void main() {
  late ProviderContainer container;
  late _FakeHubBindings bindings;

  Future<void> setUpContainer() async {
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
  }

  GameSessionState current() => container.read(gameControllerProvider);

  setUp(() async => setUpContainer());

  /// Seats the player into an in-progress Bell round (type 3), exactly the
  /// way a real GameStarted/GameUpdated would — establishing a real,
  /// non-null `state.game` with a real `status`/`type`, matching every
  /// scenario below's starting point.
  Future<void> startBellRound() async {
    bindings.emit(PlayGameHubEvents.gameStarted, {
      'id': 'g1',
      'status': 3,
      'type': 3,
      'groupId': 'grp',
      'players': _players(),
    });
    await Future<void>.delayed(Duration.zero);
    expect(current().phase, GamePhase.bell, reason: 'sanity');
  }

  group('R-05 — GameRestore status fallback', () {
    test(
      'valid status routes normally (baseline, unaffected by this fix)',
      () async {
        await startBellRound();

        bindings.emit(PlayGameHubEvents.gameRestore, {
          'id': 'g1',
          'status': 3,
          'type': 3,
          'currentTurn': _localId,
          'players': _players(),
        });
        await Future<void>.delayed(Duration.zero);

        expect(current().phase, GamePhase.bell);
        expect(current().game?.currentTurn, _localId);
      },
    );

    test(
      'status explicitly null, with a different round type: '
      're-derives the phase from the restore\'s own type instead of '
      'keeping the stale phase (the confirmed bug)',
      () async {
        await startBellRound();

        bindings.emit(PlayGameHubEvents.gameRestore, {
          'id': 'g1',
          'status': null,
          'type': 1, // WDYK — a different round than the stale `bell` phase
          'currentTurn': _localId,
          'players': _players(),
        });
        await Future<void>.delayed(Duration.zero);

        expect(
          current().phase,
          GamePhase.wdyk,
          reason: 'before the fix this stayed GamePhase.bell — the stale '
              'phase — even though the restore itself reports type 1 (WDYK)',
        );
      },
    );

    test(
      'unrecognized status value (not 1..4), with a different round type: '
      'same re-derivation applies',
      () async {
        await startBellRound();

        bindings.emit(PlayGameHubEvents.gameRestore, {
          'id': 'g1',
          'status': 99,
          'type': 1,
          'currentTurn': _localId,
          'players': _players(),
        });
        await Future<void>.delayed(Duration.zero);

        expect(current().phase, GamePhase.wdyk);
      },
    );

    test(
      'status field entirely absent, with a different round type: already '
      'safe before this fix — _routeByStatus succeeds off the previous '
      "game's own carried-over status, and _goToRound derives the phase "
      'from the merged (fresh) type',
      () async {
        await startBellRound();

        bindings.emit(PlayGameHubEvents.gameRestore, {
          'id': 'g1',
          'type': 1,
          'currentTurn': _localId,
          'players': _players(),
        });
        await Future<void>.delayed(Duration.zero);

        expect(current().phase, GamePhase.wdyk);
      },
    );

    test(
      'neither status nor type can be determined: falls back to the '
      'current phase, unchanged — no phase is invented',
      () async {
        await startBellRound();

        bindings.emit(PlayGameHubEvents.gameRestore, {
          'id': 'g1',
          'status': null,
          'type': null,
          'players': _players(),
        });
        await Future<void>.delayed(Duration.zero);

        expect(
          current().phase,
          GamePhase.bell,
          reason: 'GameType.fromId(0) and StatusGame.fromId(0) both fail to '
              'resolve — the only safe option left is to stay put',
        );
      },
    );

    test(
      'a GameRestore while still in GamePhase.waiting never reaches '
      "applySessionEvent's fallback at all — _onHubEvent hands it "
      "exclusively to WaitingScreen's own onWaitingGameRestore listener "
      '(unmodified by this task), so this controller-only test (no '
      'WaitingScreen mounted) correctly sees no state change',
      () async {
        expect(current().phase, GamePhase.waiting, reason: 'sanity');

        bindings.emit(PlayGameHubEvents.gameRestore, {
          'id': 'g1',
          'status': null,
          'type': null,
          'players': _players(),
        });
        await Future<void>.delayed(Duration.zero);

        expect(current().phase, GamePhase.waiting);
        expect(current().game, isNull);
      },
    );

    test(
      'a GameRestore while in the lobby is likewise handed exclusively to '
      "LobbyPlayGameScreen's own onLobbyGameRestore listener, not this "
      'branch',
      () async {
        bindings.emit(PlayGameHubEvents.gameJoined, {
          'id': 'g1',
          'status': 2,
          'type': 1,
          'groupId': 'grp',
          'players': _players(),
        });
        await Future<void>.delayed(Duration.zero);
        expect(current().phase, GamePhase.lobbyPlay, reason: 'sanity');

        bindings.emit(PlayGameHubEvents.gameRestore, {
          'id': 'g1',
          'status': null,
          'type': null,
          'players': _players(),
        });
        await Future<void>.delayed(Duration.zero);

        expect(current().phase, GamePhase.lobbyPlay);
      },
    );
  });
}
