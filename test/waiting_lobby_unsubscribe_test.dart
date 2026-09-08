import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// R-02 (final audit) — dead/miscopied unsubscribe loops.
//
// WaitingScreen.dispose() and LobbyPlayGameScreen.dispose() both looped
// over PlayGameHubEvents.waitingScreenEvents calling signalR.unsubscribe(
// event) — LobbyPlayGameScreen even referenced the wrong constant (should
// have been lobbyScreenEvents, evidence of a copy-paste from WaitingScreen).
//
// Confirmed by inspection (packages/coreapp/lib/signalr/signalr_service.dart):
// SignalRService.unsubscribe() only ever removes an entry from
// _primaryUnsubscribers, which is populated exclusively by subscribe() — a
// method with zero call sites anywhere in this repository (grep-confirmed).
// Both screens actually register their listeners through HubEventMixin's
// addEventListener(), tracked in the separate _eventListeners map, which
// unsubscribe() never touches. So the loop was unconditionally a no-op
// (debug logging aside) regardless of which event list it iterated — it was
// removed rather than "corrected", since correcting the list would still
// leave dead code.
//
// The REAL cleanup path is HubEventMixin.dispose(), which stores and calls
// every addEventListener() unregister closure. This file proves that path
// still works exactly as before the dead loops were removed.

const _localId = '47';

/// Tracks how many listeners are currently registered per event name, so a
/// test can directly observe whether a disposed screen's listener was
/// actually removed.
class _TrackingSignalRService extends SignalRService {
  final _handlers = <String, List<void Function(List<Object?>?)>>{};

  int handlerCountFor(String eventName) => _handlers[eventName]?.length ?? 0;

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async => true;

  @override
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) {
    final list = _handlers.putIfAbsent(eventName, () => []);
    list.add(handler);
    return () => list.remove(handler);
  }

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

void main() {
  late ProviderContainer container;
  late _TrackingSignalRService signalR;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  Future<void> pumpHost(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _TrackingSignalRService();
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
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameControllerScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'WaitingScreen registers its listeners on mount, and '
    "HubEventMixin.dispose() (not the removed dead loop) actually removes "
    'them when the screen leaves',
    (tester) async {
      await pumpHost(tester);
      expect(find.byType(WaitingScreen), findsOneWidget, reason: 'sanity');

      // waitingScreenEvents includes gameUpdated — confirm WaitingScreen
      // really did register a listener for it.
      expect(signalR.handlerCountFor(PlayGameHubEvents.gameUpdated), 1);

      // Moves the session out of `waiting`, disposing WaitingScreen and
      // mounting LobbyPlayGameScreen — lobbyScreenEvents also includes
      // gameUpdated, so this proves the OLD listener was actually removed
      // rather than just being outnumbered by a new one: if it hadn't been,
      // the count below would be 2, not 1.
      notifier().applySessionEvent(PlayGameHubEvents.gameJoined, {
        'id': 'g1',
        'status': 2,
        'type': 1,
        'groupId': 'grp',
        'players': [
          {'id': _localId, 'playerName': 'me'},
        ],
      });
      await tester.pump();

      expect(find.byType(WaitingScreen), findsNothing, reason: 'sanity');
      expect(find.byType(LobbyPlayGameScreen), findsOneWidget,
          reason: 'sanity');
      expect(
        signalR.handlerCountFor(PlayGameHubEvents.gameUpdated),
        1,
        reason: "WaitingScreen's own listener must be gone — this "
            "would read 2 if HubEventMixin's real cleanup had stopped "
            'working',
      );
    },
  );

  testWidgets(
    'LobbyPlayGameScreen also registers and unregisters its own listeners '
    'correctly',
    (tester) async {
      await pumpHost(tester);
      notifier().applySessionEvent(PlayGameHubEvents.gameJoined, {
        'id': 'g1',
        'status': 2,
        'type': 1,
        'groupId': 'grp',
        'players': [
          {'id': _localId, 'playerName': 'me'},
        ],
      });
      await tester.pump();
      expect(find.byType(LobbyPlayGameScreen), findsOneWidget,
          reason: 'sanity');
      expect(signalR.handlerCountFor(PlayGameHubEvents.playerReady), 1,
          reason: 'a lobbyScreenEvents-only event, registered by Lobby');

      // Moving into a round disposes LobbyPlayGameScreen.
      notifier().applySessionEvent(PlayGameHubEvents.gameStarted, {
        'id': 'g1',
        'status': 3,
        'type': 1,
        'groupId': 'grp',
        'currentQuestion': {
          'id': 1,
          'text': 'q',
          'textEn': 'q',
          'answers': [
            {'id': 10, 'text': 'a1', 'textEn': 'a1'},
          ],
        },
        'players': [
          {'id': _localId, 'playerName': 'me'},
        ],
      });
      await tester.pump();

      expect(find.byType(LobbyPlayGameScreen), findsNothing,
          reason: 'sanity');
      expect(
        signalR.handlerCountFor(PlayGameHubEvents.playerReady),
        0,
        reason: 'no round screen listens for playerReady, so this must '
            "drop to zero if LobbyPlayGameScreen's listener was actually "
            'removed',
      );
    },
  );
}
