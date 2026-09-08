import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// R-07 (final audit) — "Abrupt GameOver in Waiting can render result over
// Waiting; retry logic not cross-checked".
//
// Inspection findings (verified by direct code reading):
//   - endGame() (game_controller.dart) deliberately sets `phase: state.phase`
//     — it never changes phase. So a GameOver/GameFinished/GameTerminated
//     landing while `state.phase == GamePhase.waiting` sets `state.result`
//     (when it reaches endGame at all — see below) while phase stays
//     `waiting`.
//   - _onHubEvent's very first guard drops any event in waitingScreenEvents
//     while phase is `waiting`, *before* it ever reaches applySessionEvent.
//     waitingScreenEvents = [gameUpdated, gameRestore, gameFinished, error].
//     GameFinished IS in that list — so GameFinished while Waiting is
//     intercepted here and never reaches endGame(); it is instead handled
//     exclusively by WaitingScreen's own onEventReceived
//     (`case gameFinished: _leaveToPreviousScreen();`), which simply leaves
//     — no result is ever set, no result dialog is ever shown. This is a
//     real, pre-existing difference in how GameFinished is treated compared
//     to GameOver/GameTerminated while Waiting, and it is intentional: it
//     matches "the search itself concluded" rather than "a real game was
//     played and lost/won" — this file characterizes it, unchanged.
//   - GameOver and GameTerminated are NOT in waitingScreenEvents, so neither
//     is intercepted by that guard. Both reach applySessionEvent -> endGame,
//     setting state.result while state.phase stays `waiting`.
//     GameControllerScreen's own ref.listen(gameControllerProvider) reacts
//     to state.result regardless of phase, and schedules the same
//     WinDialog/LossDialog result flow shown for a round-phase termination —
//     which then renders as an overlay on top of WaitingScreen's still-
//     mounted body. This is the existing, working, established
//     result-authoritative architecture (BUG-01/02's own comments describe
//     result as authoritative once set) — confirmed intentional, not
//     something this task changes. WaitingScreen itself has no listener for
//     GameOver/GameTerminated (neither name appears in waitingScreenEvents),
//     so there is no competing/duplicate leave path for this scenario:
//     exactly one mechanism (GameControllerScreen's own
//     _showResultDialog -> _leaveGame(), already guarded by its own
//     `_leaving` flag) ever pops the screen here.
//   - The confirmed gap: onWaitingShown() (waiting_screen_handler.dart) is
//     called from two places — WaitingScreen.initState()'s postFrame, and
//     onRecovered()'s reconnect retry (game_controller.dart) — and, before
//     this fix, only checked `_didJoinRandom`. onRecovered()'s own condition
//     only checks `state.phase == GamePhase.waiting`, which — because
//     endGame leaves phase untouched — is STILL true after an abrupt
//     GameOver/GameTerminated while Waiting. If the original join never
//     went out (_didJoinRandom still false: e.g. a dropped connection when
//     WaitingScreen first mounted), a reconnect arriving *after* the
//     terminal result would still dispatch a brand new JoinRandomGame for a
//     game that is already over and already showing its result dialog.
//     Fixed by also checking `state.result == null` inside onWaitingShown()
//     itself — the one place that performs the actual invoke, covering both
//     call sites with a single change.
//
// This file exercises both: the real event-driven controller behaviour
// (all three terminal events, and the reconnect-retry gap/fix), and a real
// widget-level GameControllerScreen mount proving the result dialog does
// render over WaitingScreen and that closing it performs exactly one clean
// pop — no duplicate navigation.

const _localId = '47';

class _TrackingSignalRService extends SignalRService {
  final invocations = <String>[];
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

Map<String, dynamic> _gameOverPayload({String winnerId = _localId}) => {
      'gameId': 'g1',
      'winnerId': winnerId,
      'gameResultPlayers': <dynamic>[],
    };

void main() {
  group('R-07 — controller-level event/reconnect behaviour', () {
    late ProviderContainer container;
    late _TrackingSignalRService signalR;
    late _FakeHubBindings bindings;

    Future<void> setUpContainer() async {
      SharedPreferences.setMockInitialValues({'user_id': _localId});
      final prefs = await SharedPrefsService.init();
      signalR = _TrackingSignalRService();
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

    test(
      'an abrupt GameOver while Waiting sets a terminal result but leaves '
      'phase at waiting (endGame\'s existing, documented behaviour)',
      () async {
        bindings.emit(PlayGameHubEvents.gameOver, _gameOverPayload());
        await Future<void>.delayed(Duration.zero);

        expect(current().phase, GamePhase.waiting);
        expect(current().result, GameResult.win);
      },
    );

    test(
      'an abrupt GameTerminated while Waiting behaves the same way',
      () async {
        bindings.emit(PlayGameHubEvents.gameTerminated, _gameOverPayload());
        await Future<void>.delayed(Duration.zero);

        expect(current().phase, GamePhase.waiting);
        expect(current().result, GameResult.win);
      },
    );

    test(
      'GameFinished while Waiting does NOT set a result — intercepted '
      "earlier by _onHubEvent's waitingScreenEvents guard, unlike GameOver/"
      'GameTerminated (characterization, unaffected by this fix)',
      () async {
        bindings.emit(PlayGameHubEvents.gameFinished, _gameOverPayload());
        await Future<void>.delayed(Duration.zero);

        expect(current().phase, GamePhase.waiting);
        expect(current().result, isNull);
      },
    );

    test(
      'R-07 fix: a reconnect after an abrupt GameOver while Waiting does '
      'not re-issue JoinRandomGame for the already-finished game',
      () async {
        signalR.connected = false;
        await notifier().onWaitingShown();
        expect(signalR.joins, isEmpty, reason: 'sanity — join never went out');

        signalR.connected = true;
        bindings.emit(PlayGameHubEvents.gameOver, _gameOverPayload());
        await Future<void>.delayed(Duration.zero);
        expect(current().result, GameResult.win, reason: 'sanity');

        await notifier().onRecovered();

        expect(
          signalR.joins,
          isEmpty,
          reason: 'before this fix, onRecovered saw phase == waiting (still '
              'true — endGame never changes it) and !_didJoinRandom (still '
              'true — the original join failed) and retried the join for a '
              'game that had already ended',
        );
        expect(
          signalR.checks,
          hasLength(1),
          reason: 'CheckPlayerGame itself is unaffected by this fix',
        );
      },
    );

    test(
      'R-07 fix: the same holds for GameTerminated',
      () async {
        signalR.connected = false;
        await notifier().onWaitingShown();
        signalR.connected = true;

        bindings.emit(PlayGameHubEvents.gameTerminated, _gameOverPayload());
        await Future<void>.delayed(Duration.zero);

        await notifier().onRecovered();

        expect(signalR.joins, isEmpty);
      },
    );

    test(
      'onWaitingShown itself is a no-op once a result has landed — covers '
      "WaitingScreen's own initState call site directly, not just "
      'onRecovered',
      () async {
        bindings.emit(PlayGameHubEvents.gameOver, _gameOverPayload());
        await Future<void>.delayed(Duration.zero);

        await notifier().onWaitingShown();

        expect(signalR.joins, isEmpty);
      },
    );

    test(
      'existing behaviour is preserved: a reconnect BEFORE any terminal '
      'event still retries a join that never went out',
      () async {
        signalR.connected = false;
        await notifier().onWaitingShown();
        expect(signalR.joins, isEmpty);

        signalR.connected = true;
        await notifier().onRecovered();

        expect(current().phase, GamePhase.waiting);
        expect(signalR.joins, hasLength(1), reason: 'no result yet — retry is still allowed');
      },
    );
  });

  group('R-07 — real widget/event flow: result over Waiting', () {
    testWidgets(
      'an abrupt GameOver while WaitingScreen is showing renders the '
      'result dialog over it, and closing the dialog performs exactly one '
      'clean pop — no duplicate navigation',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'user_id': _localId,
          'app_language': AppLanguage.english,
        });
        final prefs = await SharedPrefsService.init();
        final signalR = _TrackingSignalRService();
        final bindings = _FakeHubBindings(signalR);
        final container = ProviderContainer(
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
          ],
        );
        addTearDown(container.dispose);

        final navigatorKey = GlobalKey<NavigatorState>();
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
        expect(find.byType(WaitingScreen), findsOneWidget, reason: 'sanity');

        bindings.emit(PlayGameHubEvents.gameOver, _gameOverPayload());
        await tester.pump();
        await tester.pump();

        final strings = container.read(playGameStringsProvider);
        expect(
          find.text(strings.collectRewards),
          findsOneWidget,
          reason: 'the result dialog is showing on top of WaitingScreen — '
              'confirmed intentional, matching every other termination path',
        );
        expect(
          find.byType(WaitingScreen),
          findsOneWidget,
          reason: 'WaitingScreen is still mounted underneath — the dialog '
              'is an overlay, not a screen replacement',
        );
        expect(find.byType(GameControllerScreen), findsOneWidget);

        await tester.tap(find.text(strings.collectRewards));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();

        expect(
          find.byType(GameControllerScreen),
          findsNothing,
          reason: 'exactly one pop closed the whole screen — no leftover '
              'route, no crash from a duplicate pop',
        );
        expect(find.byType(_HomePlaceholder), findsOneWidget);
      },
    );
  });
}
