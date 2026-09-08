import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// GameOver -> result dialog -> Collect Rewards returns to Home without a
// LeaveGame call (the server already considers the match concluded).
// _leaveGame() is unchanged and still used by explicit exit / PlayerLeft.

const _localId = '47';
const _opponentId = '211403';

/// One hub event listener, named so the map and its iteration share a type.
typedef HubHandler = void Function(List<Object?>?);

class _TrackingFiringSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];
  final _handlers = <String, List<HubHandler>>{};

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    invocations.add((method: methodName, args: args));
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

  @override
  void reattachEventHandlers() {}

  void fire(String eventName, [List<Object?>? args]) {
    for (final handler
        in List.of(_handlers[eventName] ?? const <HubHandler>[])) {
      handler(args);
    }
  }
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

class _FakeStickersRepository implements StickersRepository {
  @override
  Future<Result<StickerPage>> getStickerGroups(
    StickerFilterParams params,
  ) async =>
      Result.success(const StickerPage(items: [], pageIndex: 0, pageSize: 20));

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
  Future<void> playSfx(String asset, {String? package, double? volume}) async {}
}

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

Map<String, dynamic> _wdykGame() => {
      'id': 'g1',
      'status': 3,
      'type': 1, // WDYK
      'groupId': 'grp',
      'currentTurn': _localId,
      'players': [
        {'id': _localId, 'playerName': 'me'},
        {'id': _opponentId, 'playerName': 'them'},
      ],
      'currentQuestion': {
        'id': 1,
        'text': 'q1',
        'textEn': 'q1',
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
    };

Map<String, dynamic> _gameOverPayload({required String winnerId}) => {
      'gameId': 'g1',
      'winnerId': winnerId,
      'gameResultPlayers': <dynamic>[],
    };

void main() {
  late ProviderContainer container;
  late _TrackingFiringSignalRService signalR;
  late _FakeHubBindings bindings;
  late GlobalKey<NavigatorState> navigatorKey;

  Iterable<({String method, List<Object?>? args})> leaveGameCalls() =>
      signalR.invocations.where((i) => i.method == PlayGameHubEvents.leaveGame);

  Future<void> pumpGameScreen(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _TrackingFiringSignalRService();
    bindings = _FakeHubBindings(signalR);
    navigatorKey = GlobalKey<NavigatorState>();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider.overrideWithValue(bindings),
        stickersRepositoryProvider.overrideWithValue(_FakeStickersRepository()),
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
  }

  Future<void> enterWdykRound(WidgetTester tester) async {
    bindings.emit(PlayGameHubEvents.gameStarted, _wdykGame());
    await tester.pump();
    // Let the round-intro dialog build and auto-dismiss (its own 2s Timer),
    // matching the established pattern used elsewhere in this suite —
    // otherwise it stacks with whatever this test drives next.
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  }

  testWidgets(
    'GameOver(win) -> WinDialog -> Collect Rewards returns to Home '
    'without invoking LeaveGame',
    (tester) async {
      await pumpGameScreen(tester);
      await enterWdykRound(tester);

      bindings.emit(
        PlayGameHubEvents.gameOver,
        _gameOverPayload(winnerId: _localId),
      );
      await tester.pump();
      await tester.pump();

      final strings = container.read(playGameStringsProvider);
      expect(find.byType(WinDialog), findsOneWidget, reason: 'sanity');
      expect(find.text(strings.collectRewards), findsOneWidget);

      await tester.tap(find.text(strings.collectRewards));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.byType(GameControllerScreen), findsNothing);
      expect(find.byType(_HomePlaceholder), findsOneWidget);
      expect(
        leaveGameCalls(),
        isEmpty,
        reason: 'GameOver already means the server considers the match '
            'concluded — no LeaveGame call belongs in this flow',
      );
    },
  );

  testWidgets(
    'GameOver(loss) -> LossDialog -> Collect Rewards returns to Home '
    'without invoking LeaveGame',
    (tester) async {
      await pumpGameScreen(tester);
      await enterWdykRound(tester);

      bindings.emit(
        PlayGameHubEvents.gameOver,
        _gameOverPayload(winnerId: _opponentId),
      );
      await tester.pump();
      await tester.pump();

      final strings = container.read(playGameStringsProvider);
      expect(find.byType(LossDialog), findsOneWidget, reason: 'sanity');
      expect(find.text(strings.collectRewards), findsOneWidget);

      await tester.tap(find.text(strings.collectRewards));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.byType(GameControllerScreen), findsNothing);
      expect(find.byType(_HomePlaceholder), findsOneWidget);
      expect(leaveGameCalls(), isEmpty);
    },
  );

  testWidgets(
    'a round dialog open when GameOver occurs does not stop Collect '
    'Rewards from returning to Home, and no LeaveGame call is made — '
    '_leaveGame() (the one method that blindly pops whatever is on top) '
    'is never invoked by this flow at all',
    (tester) async {
      await pumpGameScreen(tester);
      await enterWdykRound(tester);

      // A round dialog (ChangeTurn's "your turn" overlay) is opened and
      // left up — the exact shape of the previously-investigated stacking
      // scenario. Let it fully drain via its own timer, as it always does
      // whether or not GameOver happens to land while it is up (this fix
      // does not redesign the round-dialog queue or add any "pop every
      // stacked route" logic).
      signalR.fire(PlayGameHubEvents.changeTurn, [_localId, 'g1']);
      await tester.pump();
      await tester.pump();
      expect(find.byType(RoundLottieDialog), findsOneWidget, reason: 'sanity');

      bindings.emit(
        PlayGameHubEvents.gameOver,
        _gameOverPayload(winnerId: _localId),
      );
      // The round dialog's own dismiss timer runs its course independently
      // of GameOver/the result dialog.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byType(RoundLottieDialog), findsNothing, reason: 'sanity');

      final strings = container.read(playGameStringsProvider);
      expect(find.byType(WinDialog), findsOneWidget, reason: 'sanity');

      await tester.tap(find.text(strings.collectRewards));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(
        find.byType(GameControllerScreen),
        findsNothing,
        reason: 'Home is reached cleanly',
      );
      expect(find.byType(_HomePlaceholder), findsOneWidget);
      expect(
        leaveGameCalls(),
        isEmpty,
        reason: '_leaveGame() — the method whose blind pop could target a '
            'round dialog instead of the screen — is never called by the '
            'result-dialog flow now, regardless of round-dialog activity',
      );
    },
  );

  testWidgets(
    'explicit back/exit during an active game still uses the existing '
    'LeaveGame flow, unchanged',
    (tester) async {
      await pumpGameScreen(tester);
      await enterWdykRound(tester);

      await navigatorKey.currentState!.maybePop();
      await tester.pump();

      final strings = container.read(playGameStringsProvider);
      expect(
        find.byType(ShowDialogGame),
        findsOneWidget,
        reason: 'explicit exit still asks for confirmation, unchanged',
      );
      expect(leaveGameCalls(), isEmpty, reason: 'not yet confirmed');

      await tester.tap(find.text(strings.exitTheGame));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(
        leaveGameCalls(),
        hasLength(1),
        reason: 'confirmed explicit exit still goes through _leaveGame() '
            'and dispatches LeaveGame, exactly as before',
      );
      expect(find.byType(GameControllerScreen), findsNothing);
      expect(find.byType(_HomePlaceholder), findsOneWidget);
    },
  );
}
