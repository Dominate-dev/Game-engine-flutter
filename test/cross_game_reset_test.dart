import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// R-04 (final audit) — "Cross-game reset relies on the host popping the
// screen".
//
// Inspection findings (verified by direct code reading):
//   - gameControllerProvider is `NotifierProvider.autoDispose`. GameController
//     .build() registers no `ref.keepAlive()` — autoDispose's default
//     watcher-count-based disposal is never overridden.
//   - GameControllerScreen() is constructed in exactly one place in the
//     whole package: play_game_launcher.dart's PlayGame.openWaiting(),
//     which always pushes a FRESH MaterialPageRoute.
//   - A repo-wide grep of every `gameControllerProvider` reference (14
//     files) found that every persistent `ref.watch`/`ref.listen`
//     subscription lives inside GameControllerScreen's own widget subtree
//     (the screen itself, WaitingScreen, LobbyPlayGameScreen, the four round
//     screens, and the shared round_score_column.dart/round_player_avatar
//     .dart widgets they use). The only consumers OUTSIDE that subtree
//     (lobby_private_game_screen.dart, interaction_dialog.dart,
//     round_report_button.dart) all use a one-shot `ref.read(...)` inside a
//     callback, never `.watch`/`.listen` — they do not keep the provider
//     alive.
//   - So once GameControllerScreen's entire subtree is popped and disposed,
//     the watcher count for gameControllerProvider reaches zero and
//     Riverpod's autoDispose recreates it fresh (GameSessionState.initial())
//     the next time anything reads it — this is the PRIMARY guarantee, and
//     it does not depend on the host popping any *particular* screen, only
//     on GameControllerScreen's own subtree being unmounted (which is what
//     every leave path in this codebase already does via Navigator.pop()).
//   - packages/play_game/lib/presentation/play_game_launcher.dart also
//     exposes PlayGame.clearGameData(), an EXPLICIT, additional safety net:
//     it calls ref.invalidate(gameControllerProvider) unconditionally. It is
//     invoked by lib/features/home/presentation/pages/home_launcher_page
//     .dart (this repo's debug entry point) both on first mount and on every
//     RouteAware.didPopNext() — i.e. every time the player returns to Home
//     after a game. This is a belt-and-suspenders mechanism specific to the
//     debug launcher, not the primary guarantee, and is unchanged by this
//     task.
//
// This file exercises the PRIMARY guarantee directly — a real
// ProviderContainer, no manual invalidate() — proving autoDispose alone,
// driven purely by GameControllerScreen's own widget lifecycle, is
// sufficient: Game A is driven into a deliberately "dirty" state, its
// screen is popped (the same Navigator.pop() every real leave path already
// performs), and a brand new GameControllerScreen for Game B reads a
// completely fresh GameSessionState before any Game B event arrives.

const _gameAId = '47';
const _gameAOpponentId = '211403';

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
  testWidgets(
    'Game A -> leave -> Game B: autoDispose alone (no manual invalidate) '
    'resets GameSessionState before Game B reads anything',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'user_id': _gameAId,
        'app_language': AppLanguage.english,
      });
      final prefs = await SharedPrefsService.init();
      final signalR = _FakeSignalRService();
      // A single, real, app-lifetime-scoped ProviderContainer — matching
      // production, where GameControllerScreen instances come and go but
      // the container itself does not. No override of gameControllerProvider
      // itself, and no manual ref.invalidate() anywhere in this test — the
      // reset under test is autoDispose's own, unmodified behavior.
      final container = ProviderContainer(
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

      // --- Game A: pushed exactly the way PlayGame.openWaiting() does. ---
      unawaited(
        navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const GameControllerScreen()),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byType(GameControllerScreen), findsOneWidget,
          reason: 'sanity');

      // Deliberately dirty Game A's state across several unrelated fields —
      // roster, an active round with a turn/timer, Bell-armed, an emote,
      // and a terminal result — so a leaked instance would be obviously
      // wrong for Game B, not just coincidentally empty.
      container.read(gameControllerProvider.notifier).applySessionEvent(
        PlayGameHubEvents.gameStarted,
        {
          'id': 'game-a',
          'status': 3,
          'type': 3, // Bell
          'groupId': 'grp-a',
          'currentTurn': _gameAId,
          'isTimerStarted': true,
          'currentTimerValue': 7.0,
          'players': [
            {
              'id': _gameAId,
              'playerName': 'Game A me',
              'points': 40,
            },
            {
              'id': _gameAOpponentId,
              'playerName': 'Game A opponent',
              'points': 12,
            },
          ],
        },
      );
      await tester.pump();
      final dirty = container.read(gameControllerProvider);
      expect(dirty.phase, GamePhase.bell, reason: 'sanity');
      expect(dirty.me?.id, _gameAId, reason: 'sanity');
      expect(dirty.opponent?.id, _gameAOpponentId, reason: 'sanity');
      expect(dirty.game?.id, 'game-a', reason: 'sanity');

      // Entering the Bell phase also scheduled its own round-intro dialog
      // (RoundLottieDialog, round_screen_handler.dart's showRoundIntro),
      // which self-dismisses via an internal 2s Timer started in its own
      // initState (round_lottie_dialog.dart). Let it run its course —
      // matching real gameplay, where a GameOver arrives long after the
      // intro has already closed itself — instead of leaving it stacked
      // underneath WinDialog, which would make a single "collect rewards"
      // tap close the wrong route. A plain pump() first is required so the
      // dialog actually builds and starts its Timer *before* the clock is
      // advanced past it — advancing the clock in the same pump as the push
      // jumps forward before the Timer exists, and it never fires.
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      container.read(gameControllerProvider.notifier).applySessionEvent(
        PlayGameHubEvents.gameOver,
        {
          'gameId': 'game-a',
          'winnerId': _gameAId,
          'gameResultPlayers': <dynamic>[],
        },
      );
      await tester.pump();
      expect(container.read(gameControllerProvider).result, GameResult.win,
          reason: 'sanity');

      // --- Leave Game A: not a manual navigatorKey.pop() — that would pop
      // whatever route is currently on top, and by this point GameOver's
      // result already triggered GameControllerScreen's own ref.listen,
      // which schedules a post-frame callback that pushes WinDialog *above*
      // GameControllerScreen's route (proven empirically: an earlier version
      // of this test called navigatorKey.currentState!.pop() here and it
      // closed WinDialog instead of unmounting the screen). So this test
      // drives the actual production chain instead: tap WinDialog's
      // "collect rewards" button (GameButton.onPressed: () =>
      // Navigator.of(context).pop()), which resolves _showResultDialog's
      // `await showAppDialog(...)`, which then runs `await _leaveGame()` —
      // the same Navigator.of(context).pop() every leave path in this
      // codebase already performs. No manual provider reset anywhere here.
      final strings = container.read(playGameStringsProvider);
      await tester.pump();
      expect(find.text(strings.collectRewards), findsOneWidget,
          reason: 'sanity — WinDialog is showing');

      await tester.tap(find.text(strings.collectRewards));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.byType(GameControllerScreen), findsNothing,
          reason: 'sanity — Game A fully unmounted');
      expect(find.byType(_HomePlaceholder), findsOneWidget, reason: 'sanity');

      // --- Game B: a brand new GameControllerScreen instance, same
      // ProviderContainer, no event fired yet. ---
      unawaited(
        navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const GameControllerScreen()),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byType(GameControllerScreen), findsOneWidget,
          reason: 'sanity');

      final fresh = container.read(gameControllerProvider);
      expect(fresh.phase, GamePhase.waiting,
          reason: 'autoDispose recreated GameController from scratch — '
              'the leaked "bell" phase must not survive');
      expect(fresh.me, isNull, reason: 'Game A roster must not leak');
      expect(fresh.opponent, isNull, reason: 'Game A roster must not leak');
      expect(fresh.game, isNull, reason: "Game A's game snapshot must not "
          'leak');
      expect(fresh.result, isNull,
          reason: "Game A's win result must not leak into Game B");
      expect(fresh.bellArmed, isFalse);
      expect(fresh.comebackAnswerLocked, isFalse);
      expect(fresh.answersUnlocked, isFalse);
      expect(fresh.lastEventName, isNull);
    },
  );
}
