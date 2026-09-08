import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// R-03 (final audit) — "Lobby does not listen to Error".
//
// CHARACTERIZATION (unresolved) — see below. This is NOT an endorsement of
// the behavior it records, only a pin on what the repository currently does,
// per ENGINEERING_RULES.md #7.5.
//
// Inspection findings (verified by direct code reading, not guessed):
//   - packages/play_game/lib/constants/play_game_hub_events.dart:
//     `error` ('Error') is a member of waitingScreenEvents, sharedRoundEvents
//     and lifetimeEvents — but NOT of lobbyScreenEvents, and NOT of
//     hostScreenEvents.
//   - A repo-wide grep of packages/play_game/lib for
//     "PlayGameHubEvents.error" found exactly ONE explicit handler:
//     WaitingScreen.onEventReceived's `case PlayGameHubEvents.error:
//     _leaveToPreviousScreen();`. No other screen — not LobbyPlayGameScreen,
//     not GameControllerScreen, not any of the five round screens — has any
//     explicit Error handling.
//   - GameController.applySharedRoundEvent (game_controller.dart) has no
//     `if (name == PlayGameHubEvents.error)` branch — Error falls through
//     its generic tail, which only updates state.data/lastEventName (no
//     game/timer/turn field changes, since an Error payload does not look
//     like a CreatedGame snapshot). This applies identically whether the
//     phase is lobbyPlay or any round phase.
//   - No documentation anywhere under docs/ describes the Error event's
//     intended semantics, and no native/reference source exists in this
//     repository to consult (verified: no .kt/.java files beyond generic
//     Flutter host/plugin scaffolding).
//
// Conclusion: "Lobby ignores Error" is NOT an isolated gap unique to the
// lobby — it is the SAME behavior every round phase and finishRound already
// have. WaitingScreen's explicit leave-on-Error is the one special case in
// the whole app, not the norm the lobby is missing. Making the lobby leave
// on Error would be inventing a new (or removed) behavior with no repository
// evidence for what it should do, which the task explicitly prohibits
// ("If the repository shows that Lobby intentionally handles errors
// elsewhere, do not make a speculative change; report why R-03 is not a
// bug" — here it is not "elsewhere", it is the same-as-everywhere-else
// non-handling). No production code was changed for R-03; this file exists
// to pin the current behavior so a future change to it is deliberate, not
// silent.

const _localId = '47';

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

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  setUp(() async => setUpContainer());

  void enterLobby() {
    notifier().applySessionEvent(PlayGameHubEvents.gameJoined, {
      'id': 'g1',
      'status': 2,
      'type': 1,
      'groupId': 'grp',
      'players': [
        {'id': _localId, 'playerName': 'me'},
      ],
    });
  }

  group(
    'CHARACTERIZATION (unresolved) — Error is not specially handled in the '
    'lobby, matching every round phase',
    () {
      test('Error while in the lobby does not change phase or leave', () async {
        enterLobby();
        expect(current().phase, GamePhase.lobbyPlay, reason: 'sanity');

        bindings.emit(PlayGameHubEvents.error, {'message': 'boom'});
        await Future<void>.delayed(Duration.zero);

        expect(
          current().phase,
          GamePhase.lobbyPlay,
          reason: 'no navigation is triggered — same as every round phase',
        );
      });

      test(
        'Error during a round phase is equally a no-op — the lobby is not '
        'an isolated gap',
        () async {
          notifier().applySessionEvent(PlayGameHubEvents.gameStarted, {
            'id': 'g1',
            'status': 3,
            'type': 1,
            'groupId': 'grp',
            'players': [
              {'id': _localId, 'playerName': 'me'},
            ],
          });
          expect(current().phase, GamePhase.wdyk, reason: 'sanity');

          bindings.emit(PlayGameHubEvents.error, {'message': 'boom'});
          await Future<void>.delayed(Duration.zero);

          expect(
            current().phase,
            GamePhase.wdyk,
            reason: 'identical non-handling to the lobby — this is the '
                'established, repository-wide pattern, not something the '
                'lobby is missing',
          );
        },
      );

      test(
        "Error is processed exactly once in the lobby — GameController's "
        'own reducer sees it, since Error is absent from lobbyScreenEvents '
        "but present in sharedRoundEvents; no screen listener duplicates it",
        () async {
          enterLobby();
          final before = current().lastEventName;

          bindings.emit(PlayGameHubEvents.error, {'message': 'boom'});
          await Future<void>.delayed(Duration.zero);

          expect(
            current().lastEventName,
            PlayGameHubEvents.error,
            reason: 'the reducer did see it (single path), proving this is '
                'a deliberate no-op rather than the event never arriving',
          );
          expect(before, isNot(PlayGameHubEvents.error), reason: 'sanity');
        },
      );
    },
  );

  test(
    "existing WaitingScreen Error behavior is unaffected — it still leaves "
    "immediately (verified at the GameController level; WaitingScreen's own "
    'widget-level leave behavior is covered by '
    'waiting_screen_leave_guard_test.dart)',
    () {
      expect(
        PlayGameHubEvents.waitingScreenEvents,
        contains(PlayGameHubEvents.error),
        reason: 'WaitingScreen.listenHubEvents still includes Error — no '
            'production code for this task touched it',
      );
    },
  );
}
