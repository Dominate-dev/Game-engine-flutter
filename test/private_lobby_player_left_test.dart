import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/features/games/domain/repositories/game_repository.dart';
import 'package:play_game/features/games/presentation/providers/game_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// `PlayerLeft | args: [playerId, gameId]` in the private lobby.
//
// The other player leaving ends the lobby, and until now it ended it
// silently: onLobbyPlayerLeft cleared them from the roster and the local
// player sat in a lobby that was never going to start. Their own leave is
// already on its way out through the exit that produced it, so it must stay
// silent — the dialog is for the other case only.

const _localId = '91';
const _opponentId = '211403';
const _gameId = 'private-1';

const _enTerminated = 'Creator has terminated the game';
const _arTerminated = 'قام مُنشئ الملعب بإنهاء اللعبة';

/// The screen the lobby was opened from, so its restoration is observable.
const _previousScreenText = 'previous-screen';

/// The neutral end-of-game text that must never appear in this flow.
const _enGameIsOver = 'The game is over';

/// Records screen listeners so a test can push a real hub event at them.
class _FakeSignalRService extends SignalRService {
  final _handlers = <String, List<void Function(List<Object?>?)>>{};
  final invocations = <String>[];

  @override
  bool get isConnected => true;

  @override
  bool get hasLiveConnection => true;

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    invocations.add(methodName);
    return true;
  }

  @override
  void Function() addEventListener(
    String eventName,
    void Function(List<Object?>?) handler,
  ) {
    final list = _handlers.putIfAbsent(eventName, () => []);
    list.add(handler);
    return () => list.remove(handler);
  }

  /// The hub delivering an event to everything currently listening for it.
  void emit(String eventName, List<Object?> args) {
    for (final handler in [...?_handlers[eventName]]) {
      handler(args);
    }
  }

  @override
  void reattachEventHandlers() {}
}

/// Feeds the controller's stream the way the real bindings do.
///
/// A no-op fake here would leave `GameController._onHubEvent` deaf, and this
/// file's whole subject is what happens when the *same* hub event reaches both
/// the lobby screen and the controller stream. So `bindAll` really registers
/// on the fake service, and an emit lands on both — exactly the double
/// delivery the private lobby had.
class _FakeHubBindings extends PlayGameHubBindings {
  _FakeHubBindings(this._signalR) : super(_signalR);

  final _FakeSignalRService _signalR;
  final _events = StreamController<GameHubEvent>.broadcast();
  final _bound = <String>{};

  @override
  Stream<GameHubEvent> get stream => _events.stream;

  @override
  void bindAll() => bindEvents(PlayGameHubEvents.lifetimeEvents);

  @override
  void bindEvents(Iterable<String> eventNames) {
    for (final name in eventNames) {
      if (!_bound.add(name)) {
        continue;
      }
      _signalR.addEventListener(name, (args) {
        if (!_events.isClosed) {
          _events.add(
            GameHubEvent(name: name, data: HubEventPayload.mapFromArgs(args)),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _events.close();
  }
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

class _FakeGameRepository implements GameRepository {
  @override
  Future<Result<String>> generateUrl({
    required int type,
    required String code,
  }) async =>
      Result.success('https://example.test/g/$code');
}

Map<String, dynamic> _privateGame() => {
      'id': _gameId,
      'status': 1,
      'mode': 4,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': true,
      'gameCode': '4821',
      'currentTimerValue': 0,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'host'},
      ],
    };

Map<String, dynamic> _publicGame() => {
      'id': 'public-1',
      'status': 2,
      'mode': 1,
      'type': 0,
      'groupId': 'grp',
      'isPrivate': false,
      'currentTimerValue': 0,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
    };

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;

  GameController notifier() => container.read(gameControllerProvider.notifier);

  Future<void> newContainer({String language = AppLanguage.english}) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': language,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    // The real provider calls bindAll() when it builds; an overrideWithValue
    // does not, so the fake is wired up here instead.
    final bindings = _FakeHubBindings(signalR)..bindAll();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider.overrideWithValue(bindings),
        stickersRepositoryProvider
            .overrideWithValue(_FakeStickersRepository()),
        audioServiceProvider.overrideWithValue(_FakeAudioService()),
        networkInfoProvider.overrideWithValue(_FakeNetworkInfo()),
        hasInternetProvider.overrideWith((ref) => Stream<bool>.value(true)),
        signalRStatusProvider.overrideWith(
          (ref) => Stream<SignalRStatus>.value(SignalRStatus.connected),
        ),
        gameRepositoryProvider.overrideWithValue(_FakeGameRepository()),
      ],
    );
    addTearDown(container.dispose);
    AppStrings.setLanguage(language);
  }

  /// A bounded settle.
  ///
  /// `pumpAndSettle` does not terminate with this lobby on screen — something
  /// in it keeps scheduling frames — so a fixed number of frames is pumped
  /// instead. Deterministic, and enough for a dialog to open, a route to pop
  /// and the leave that follows it.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Opens the private lobby through one of its two real entries.
  ///
  /// Which entry it was is the whole point: it is what tells this device
  /// whether the other seat is the creator or the guest, exactly as native
  /// derives `isHost` from the create vs join route.
  Future<void> mountPrivateLobby(
    WidgetTester tester, {
    required bool asCreator,
  }) async {
    // Pushed over a previous screen rather than being the app's home, so
    // "returns to the screen that opened the lobby" is actually observable.
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text(_previousScreenText)),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(_previousScreenText), findsOneWidget, reason: 'sanity');

    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => asCreator
              ? const GameControllerScreen(privateInterestIds: [88])
              : const GameControllerScreen(privateGameCode: '4821'),
        ),
      ),
    );
    // The entry runs post-frame and dispatches through the connect step, so
    // the create/join flag is only claimed after those futures settle.
    await settle(tester);
    expect(
      notifier().isPrivateGameCreator,
      asCreator,
      reason: 'sanity: the entry that opened this lobby is what decides it',
    );
    notifier().applySessionEvent(
      asCreator
          ? PlayGameHubEvents.gameCreated
          : PlayGameHubEvents.gameJoined,
      _privateGame(),
    );
    await tester.pump();
    expect(find.byType(LobbyPrivateGameScreen), findsOneWidget,
        reason: 'sanity: the private lobby is what is on screen');
  }

  Future<void> mountPublicLobby(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: GameControllerScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    notifier().applySessionEvent(
      PlayGameHubEvents.gameUpdated,
      _publicGame(),
    );
    await tester.pump();
    expect(find.byType(LobbyPlayGameScreen), findsOneWidget,
        reason: 'sanity: the public lobby is what is on screen');
  }

  /// The hub event exactly as the server sends it: `[playerId, gameId]`.
  Future<void> playerLeft(WidgetTester tester, String playerId) async {
    signalR.emit(PlayGameHubEvents.playerLeft, [playerId, _gameId]);
    await tester.pump();
    await tester.pump();
  }

  /// `GameFinished | args: [true]`, as the device log records it.
  Future<void> gameFinished(WidgetTester tester) async {
    signalR.emit(PlayGameHubEvents.gameFinished, [true]);
    await tester.pump();
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  setUp(() async => newContainer());

  testWidgets('the creator leaving raises the dialog for the guest',
      (tester) async {
    await mountPrivateLobby(tester, asCreator: false);

    await playerLeft(tester, _opponentId);

    expect(find.byType(ShowDialogGame), findsOneWidget);
    expect(find.text(_enTerminated), findsOneWidget);

    await unmount(tester);
  });

  group('the real device sequence: PlayerLeft(creator) then GameFinished', () {
    testWidgets('the creator-terminated dialog survives GameFinished',
        (tester) async {
      await mountPrivateLobby(tester, asCreator: false);

      await playerLeft(tester, _opponentId);
      expect(find.byType(ShowDialogGame), findsOneWidget, reason: 'sanity');

      await gameFinished(tester);
      await settle(tester);

      expect(
        find.text(_enTerminated),
        findsOneWidget,
        reason: 'the dialog the creator leaving raised is still the one up',
      );
      expect(
        find.byType(EndGameDialog),
        findsNothing,
        reason: 'GameFinished in this lobby means the creator terminated it, '
            'not that a game reached a result',
      );
      expect(
        find.text(_enGameIsOver),
        findsNothing,
        reason: 'the neutral end-of-game text must never appear here',
      );

      await unmount(tester);
    });

    testWidgets('GameFinished sets no result on the session', (tester) async {
      await mountPrivateLobby(tester, asCreator: false);

      await playerLeft(tester, _opponentId);
      await gameFinished(tester);
      await settle(tester);

      expect(
        container.read(gameControllerProvider).result,
        isNull,
        reason: 'endGame must not run for this event in the private lobby',
      );

      await unmount(tester);
    });

    testWidgets('GameFinished does not leave while the dialog waits',
        (tester) async {
      await mountPrivateLobby(tester, asCreator: false);

      await playerLeft(tester, _opponentId);
      await gameFinished(tester);
      await settle(tester);

      expect(
        signalR.invocations,
        isNot(contains(PlayGameHubEvents.leaveGame)),
        reason: 'the exit belongs to the Confirm button, not to GameFinished',
      );
      expect(find.byType(LobbyPrivateGameScreen), findsOneWidget);
      expect(find.text(_previousScreenText), findsNothing);

      await unmount(tester);
    });

    testWidgets('confirming after GameFinished leaves and goes back',
        (tester) async {
      await mountPrivateLobby(tester, asCreator: false);
      await playerLeft(tester, _opponentId);
      await gameFinished(tester);
      await settle(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(ShowDialogGame),
          matching: find.byType(GameButton),
        ),
      );
      await settle(tester);

      expect(signalR.invocations, contains(PlayGameHubEvents.leaveGame));
      expect(find.byType(LobbyPrivateGameScreen), findsNothing);
      expect(find.text(_previousScreenText), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('GameFinished on its own still leaves silently',
        (tester) async {
      // No PlayerLeft first, so no dialog owns the exit — the behaviour this
      // lobby has always had is unchanged.
      await mountPrivateLobby(tester, asCreator: false);

      await gameFinished(tester);
      await settle(tester);

      expect(find.byType(ShowDialogGame), findsNothing);
      expect(signalR.invocations, contains(PlayGameHubEvents.leaveGame));
      expect(find.text(_previousScreenText), findsOneWidget);

      await unmount(tester);
    });

    testWidgets('the creator seeing the guest leave is untouched by it',
        (tester) async {
      await mountPrivateLobby(tester, asCreator: true);

      await playerLeft(tester, _opponentId);
      await settle(tester);

      expect(find.byType(ShowDialogGame), findsNothing);
      expect(find.byType(EndGameDialog), findsNothing);
      expect(find.byType(LobbyPrivateGameScreen), findsOneWidget);
      expect(
        signalR.invocations,
        isNot(contains(PlayGameHubEvents.leaveGame)),
      );

      await unmount(tester);
    });
  });

  testWidgets('nothing moves until the guest confirms', (tester) async {
    await mountPrivateLobby(tester, asCreator: false);

    await playerLeft(tester, _opponentId);
    // Let anything that was going to happen on its own, happen.
    await settle(tester);

    expect(
      find.byType(ShowDialogGame),
      findsOneWidget,
      reason: 'the dialog does not close itself',
    );
    expect(
      find.byType(LobbyPrivateGameScreen),
      findsOneWidget,
      reason: 'the lobby is still there behind it',
    );
    expect(
      signalR.invocations,
      isNot(contains(PlayGameHubEvents.leaveGame)),
      reason: 'the leave waits for the button, it does not run ahead of it',
    );

    await unmount(tester);
  });

  testWidgets('a tap outside the dialog does not dismiss it', (tester) async {
    await mountPrivateLobby(tester, asCreator: false);
    await playerLeft(tester, _opponentId);

    // The barrier: the top-left corner is outside the card in both
    // directionalities.
    await tester.tapAt(const Offset(4, 4));
    await settle(tester);

    expect(find.byType(ShowDialogGame), findsOneWidget);
    expect(signalR.invocations, isNot(contains(PlayGameHubEvents.leaveGame)));

    await unmount(tester);
  });

  testWidgets('there is no close icon to bypass it with', (tester) async {
    await mountPrivateLobby(tester, asCreator: false);
    await playerLeft(tester, _opponentId);

    final dialog = tester.widget<ShowDialogGame>(find.byType(ShowDialogGame));
    expect(
      dialog.isCancelable,
      isFalse,
      reason: 'the close icon is the other way out of this dialog',
    );

    await unmount(tester);
  });

  testWidgets('the system back gesture does not dismiss it', (tester) async {
    await mountPrivateLobby(tester, asCreator: false);
    await playerLeft(tester, _opponentId);

    await tester.binding.handlePopRoute();
    await settle(tester);

    expect(
      find.byType(ShowDialogGame),
      findsOneWidget,
      reason: 'GameDialog carries no PopScope of its own — the call site adds '
          'one, or back pops the dialog and skips the confirmation',
    );
    expect(signalR.invocations, isNot(contains(PlayGameHubEvents.leaveGame)));

    await unmount(tester);
  });

  testWidgets('the guest leaving keeps the creator in the lobby',
      (tester) async {
    await mountPrivateLobby(tester, asCreator: true);

    await playerLeft(tester, _opponentId);

    expect(
      find.byType(ShowDialogGame),
      findsNothing,
      reason: 'the creator owns the lobby; the guest going does not end it',
    );
    expect(
      find.byType(LobbyPrivateGameScreen),
      findsOneWidget,
      reason: 'and the creator stays in it, waiting for another join',
    );
    expect(
      signalR.invocations,
      isNot(contains(PlayGameHubEvents.leaveGame)),
      reason: 'nothing left automatically',
    );

    await unmount(tester);
  });

  testWidgets('the guest seat is still cleared when the guest leaves',
      (tester) async {
    await mountPrivateLobby(tester, asCreator: true);

    await playerLeft(tester, _opponentId);

    expect(
      container.read(gameControllerProvider).opponent,
      isNull,
      reason: 'onLobbyPlayerLeft still empties the seat — unchanged',
    );

    await unmount(tester);
  });

  testWidgets('the local player leaving raises nothing, either way',
      (tester) async {
    for (final asCreator in [true, false]) {
      await newContainer();
      await mountPrivateLobby(tester, asCreator: asCreator);

      await playerLeft(tester, _localId);

      expect(
        find.byType(ShowDialogGame),
        findsNothing,
        reason: 'your own leave is already on its way out (asCreator: '
            '$asCreator)',
      );
      await unmount(tester);
    }
  });

  testWidgets('Arabic gets the Arabic string', (tester) async {
    await newContainer(language: AppLanguage.arabic);
    await mountPrivateLobby(tester, asCreator: false);

    await playerLeft(tester, _opponentId);

    expect(find.text(_arTerminated), findsOneWidget);
    expect(find.text(_enTerminated), findsNothing);

    await unmount(tester);
  });

  testWidgets('a second PlayerLeft does not stack a second dialog',
      (tester) async {
    await mountPrivateLobby(tester, asCreator: false);

    await playerLeft(tester, _opponentId);
    await playerLeft(tester, _opponentId);

    expect(find.byType(ShowDialogGame), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('confirming leaves the game and restores the previous screen',
      (tester) async {
    await mountPrivateLobby(tester, asCreator: false);
    await playerLeft(tester, _opponentId);
    expect(find.byType(ShowDialogGame), findsOneWidget, reason: 'sanity');
    expect(find.text(_previousScreenText), findsNothing, reason: 'sanity');

    await tester.tap(
      find.descendant(
        of: find.byType(ShowDialogGame),
        matching: find.byType(GameButton),
      ),
    );
    await settle(tester);

    expect(find.byType(ShowDialogGame), findsNothing);
    expect(
      signalR.invocations,
      contains(PlayGameHubEvents.leaveGame),
      reason: 'the same single exit owner every other leave here uses',
    );
    expect(find.byType(LobbyPrivateGameScreen), findsNothing);
    expect(
      find.text(_previousScreenText),
      findsOneWidget,
      reason: 'back to whatever opened the lobby, through the existing pop',
    );

    await unmount(tester);
  });

  testWidgets('the public lobby is untouched — no dialog there',
      (tester) async {
    await mountPublicLobby(tester);

    await playerLeft(tester, _opponentId);

    expect(
      find.byType(ShowDialogGame),
      findsNothing,
      reason: 'this behaviour is the private lobby flow only',
    );
    expect(find.byType(LobbyPlayGameScreen), findsOneWidget);

    await unmount(tester);
  });
}
