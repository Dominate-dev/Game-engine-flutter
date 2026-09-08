import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// R-01 (final audit) — Lobby PopScope duplication.
//
// GameControllerScreen wraps every phase, including lobbyPlay, in its own
// PopScope(canPop: false, onPopInvokedWithResult: -> _confirmExit()).
// LobbyPlayGameScreen additionally wraps its own content in a SECOND nested
// PopScope(canPop: false, onPopInvokedWithResult: -> _leaveToHome()) — both
// register as separate PopEntry instances on the SAME ModalRoute (confirmed
// by reading the Flutter SDK: pop_scope.dart's _PopScopeState registers via
// ModalRoute.registerPopEntry, and routes.dart's
// ModalRouteMixin.onPopInvokedWithResult loops over every entry in
// `_popEntries` and calls each one — there is no "innermost wins" behavior).
//
// So a single back-gesture attempt while in the lobby fires BOTH callbacks.
// Empirically (see the widget test below, run against the unmodified code
// before this fix): leaveGame() fired immediately from _leaveToHome(), but
// the two PopScopes' colliding push (_confirmExit()'s showDialog) and pop
// (_leaveToHome()'s Navigator.pop()) on the same route/gesture left the
// screen stuck on the lobby — leaveGame() had already been dispatched, but
// the confirmation dialog never appeared and the screen never actually
// navigated away. This file proves that broken interaction is gone: only
// the Lobby's own existing, unconfirmed-exit behavior remains — matching
// its own "Exit the game" button, which already calls _leaveToHome()
// directly with no confirmation — and other phases keep their existing
// confirm-before-exit behavior unchanged.

const _localId = '47';

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    invocations.add((method: methodName, args: args));
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

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;
  late GlobalKey<NavigatorState> navigatorKey;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  Future<void> pumpHost(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    navigatorKey = GlobalKey<NavigatorState>();
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
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const _HomePlaceholder(),
        ),
      ),
    );
    await tester.pump();

    // Pushed as a real second route, matching how the app actually
    // navigates into GameControllerScreen, so a pop has somewhere to land.
    unawaited(
      navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const GameControllerScreen()),
    ));
    await tester.pump();
    await tester.pump();

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
    expect(
      container.read(gameControllerProvider).phase,
      GamePhase.lobbyPlay,
      reason: 'sanity',
    );
  }

  Iterable<({String method, List<Object?>? args})> leaveGameCalls() =>
      signalR.invocations.where((i) => i.method == PlayGameHubEvents.leaveGame);

  testWidgets(
    'a single back-gesture attempt in the lobby leaves cleanly through '
    "LobbyPlayGameScreen's own handler, with no competing confirmation "
    'dialog',
    (tester) async {
      await pumpHost(tester);

      final popped = await navigatorKey.currentState!.maybePop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(popped, isTrue);
      expect(
        leaveGameCalls(),
        hasLength(1),
        reason: 'leaveGame() fires exactly once — not duplicated by a '
            'second competing handler',
      );
      expect(
        find.byType(ShowDialogGame),
        findsNothing,
        reason: "GameControllerScreen's own confirmation dialog must not "
            "fire for the lobby phase — LobbyPlayGameScreen's existing, "
            'unconfirmed exit is the only owner of this gesture, matching '
            "its exit button's identical behavior",
      );
      expect(
        find.byType(LobbyPlayGameScreen),
        findsNothing,
        reason: 'the screen actually leaves — before this fix, the two '
            "competing PopScopes' simultaneous firing left the screen "
            'stuck on the lobby even though leaveGame() had already fired',
      );
      expect(find.byType(_HomePlaceholder), findsOneWidget);
    },
  );

  testWidgets(
    'a non-lobby phase (waiting, the default) still shows the confirmation '
    'dialog on a back-gesture, unaffected by the lobby-only guard',
    (tester) async {
      // A deliberately minimal pump that never fires gameJoined, so the
      // session stays in its default GamePhase.waiting — this avoids
      // needing a full round-question payload just to prove the guard is
      // correctly scoped to lobbyPlay only.
      SharedPreferences.setMockInitialValues({
        'user_id': _localId,
        'app_language': AppLanguage.english,
      });
      final prefs = await SharedPrefsService.init();
      signalR = _FakeSignalRService();
      navigatorKey = GlobalKey<NavigatorState>();
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
          child: MaterialApp(
            navigatorKey: navigatorKey,
            home: const _HomePlaceholder(),
          ),
        ),
      );
      await tester.pump();
      unawaited(
        navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const GameControllerScreen()),
      ));
      await tester.pump();
      await tester.pump();
      expect(
        container.read(gameControllerProvider).phase,
        GamePhase.waiting,
        reason: 'sanity',
      );

      await navigatorKey.currentState!.maybePop();
      await tester.pump();

      expect(
        find.byType(ShowDialogGame),
        findsOneWidget,
        reason: 'existing non-lobby exit-confirmation behavior is '
            'unchanged by this fix',
      );
      expect(
        leaveGameCalls(),
        isEmpty,
        reason: 'leaving still waits for the confirmation, as before',
      );
    },
  );

  testWidgets(
    "the lobby's own exit button is unaffected — it still leaves "
    'immediately with no confirmation',
    (tester) async {
      await pumpHost(tester);

      await tester.tap(find.text(
        PlayGameStrings.forLanguage(AppLanguage.english).exitTheGame,
      ));
      await tester.pump();

      expect(find.byType(ShowDialogGame), findsNothing,
          reason: 'the exit button never went through PopScope at all');
      expect(leaveGameCalls(), hasLength(1));
    },
  );
}
