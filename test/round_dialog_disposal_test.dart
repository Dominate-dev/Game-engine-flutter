import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// showAppDialog now skips (resolves immediately) when the screen's route
// is no longer on the navigator, checked via ModalRoute.isActive rather
// than `mounted` (stays true through a route's exit transition) or
// isCurrent (also false whenever a legitimate dialog is already stacked on
// top). Without this, a round dialog still queued behind one already
// showing could orphan itself onto whatever screen replaced this one.

const _localId = '47';
const _opponentId = '211403';

/// One hub event listener, named so the map and its iteration share a type.
typedef HubHandler = void Function(List<Object?>?);

class _FiringSignalRService extends SignalRService {
  final _handlers = <String, List<HubHandler>>{};

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

Map<String, dynamic> _comebackGame() => {
      'id': 'g1',
      'status': 3,
      'type': 4, // Comeback
      'groupId': 'grp',
      'currentTurn': '',
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
        {
          'id': _opponentId,
          'playerName': 'them',
          'makeupTryCount': 0,
          'maxMakeupTryCount': 3,
        },
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

void main() {
  Future<
      ({
        ProviderContainer container,
        _FiringSignalRService signalR,
        _FakeHubBindings bindings,
        GlobalKey<NavigatorState> navigatorKey,
      })> setUpComebackRound(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    final signalR = _FiringSignalRService();
    final bindings = _FakeHubBindings(signalR);
    final container = ProviderContainer(
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

    bindings.emit(PlayGameHubEvents.gameStarted, _comebackGame());
    await tester.pump();
    // Let the round-intro dialog build and auto-dismiss (its own 2s Timer),
    // matching the established pattern from cross_game_reset_test.dart —
    // otherwise it stacks with what this test queues next.
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    return (
      container: container,
      signalR: signalR,
      bindings: bindings,
      navigatorKey: navigatorKey,
    );
  }

  testWidgets(
    'disposing the screen while a round dialog is visible AND more are '
    'queued behind it: no orphan dialog, no exception, and nothing '
    'leaks into a freshly-pushed screen afterward',
    (tester) async {
      final s = await setUpComebackRound(tester);

      // Dialog #1 (Start Timer, 2000ms) — let it actually show.
      s.signalR.fire(PlayGameHubEvents.timeStarted);
      await tester.pump();
      await tester.pump();
      expect(find.byType(RoundLottieDialog), findsOneWidget, reason: 'sanity');

      // Dialogs #2 and #3 — queued behind #1, not yet shown.
      s.signalR.fire(
        PlayGameHubEvents.correctAnswer,
        ['text', 'textEn', _opponentId, 'g1'],
      );
      s.signalR.fire(
        PlayGameHubEvents.penalty,
        [
          {'playerId': _localId, 'type': 2},
        ],
      );

      // The whole game screen (and the dialog on top of it) goes away in
      // one shot — the same shape of disposal PlayGame.clearGameData() /
      // a hard return-to-Home navigation produces. popUntil resolves
      // dialog #1's own showDialog Future as part of this same call
      // (forced pop, not its own timer), which synchronously cascades the
      // chain into #2 and #3 as microtasks — so the very next pump is the
      // one that matters: checking only much later (after every dialog's
      // own auto-dismiss timer would also have run its course) would let
      // a real orphan dialog slip through undetected, since it clears
      // itself before the check runs. This is the exact window the bug
      // reproduced in.
      s.navigatorKey.currentState!.popUntil((route) => route.isFirst);
      await tester.pump();

      expect(
        find.byType(RoundLottieDialog),
        findsNothing,
        reason: 'no queued dialog may orphan itself onto Home once the '
            'screen that queued it is gone — checked in the exact window '
            '(right after the forced pop cascades the chain) where the '
            'unfixed code produced a visible "Wrong Answer" orphan',
      );

      // Give the rest of the (doomed) chain every remaining chance to run.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.byType(GameControllerScreen), findsNothing);
      expect(find.byType(RoundLottieDialog), findsNothing);
      expect(find.byType(_HomePlaceholder), findsOneWidget);

      // A brand new game/screen instance must start completely clean —
      // the old queue must not leak into it.
      unawaited(
        s.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const GameControllerScreen()),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byType(GameControllerScreen), findsOneWidget);
      expect(
        find.byType(RoundLottieDialog),
        findsNothing,
        reason: 'the old controller instance\'s queue is gone with it — '
            'autoDispose gives the new screen a fresh GameController',
      );
    },
  );

  testWidgets(
    'disposing the screen while dialogs are only queued — none has shown '
    'yet — is equally clean',
    (tester) async {
      final s = await setUpComebackRound(tester);

      // All three fire back-to-back with no pump in between: none of them
      // has been shown yet when the screen goes away.
      s.signalR.fire(PlayGameHubEvents.timeStarted);
      s.signalR.fire(
        PlayGameHubEvents.correctAnswer,
        ['text', 'textEn', _opponentId, 'g1'],
      );
      s.signalR.fire(
        PlayGameHubEvents.penalty,
        [
          {'playerId': _localId, 'type': 2},
        ],
      );

      s.navigatorKey.currentState!.popUntil((route) => route.isFirst);
      await tester.pump();
      expect(
        find.byType(RoundLottieDialog),
        findsNothing,
        reason: 'checked in the window where an orphan would first appear, '
            'not after it would already have auto-dismissed',
      );

      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.byType(RoundLottieDialog), findsNothing);
      expect(find.byType(GameControllerScreen), findsNothing);
      expect(find.byType(_HomePlaceholder), findsOneWidget);
    },
  );

  testWidgets(
    'the confirmed game-end leave path (result dialog closes, then '
    '_leaveGame()\'s own single pop) still leaves nothing behind once a '
    'round dialog queued earlier in the same round has fully drained',
    (tester) async {
      final s = await setUpComebackRound(tester);

      // A round dialog queues, shows, and closes on its own — same as any
      // ordinary round dialog completing before the round ends — so
      // nothing else is stacked on GameControllerScreen's route by the
      // time the game ends and its single real pop runs.
      s.signalR.fire(PlayGameHubEvents.timeStarted);
      await tester.pump();
      await tester.pump();
      expect(find.byType(RoundLottieDialog), findsOneWidget, reason: 'sanity');
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.byType(RoundLottieDialog), findsNothing, reason: 'sanity');

      s.bindings.emit(PlayGameHubEvents.gameOver, {
        'gameId': 'g1',
        'winnerId': _localId,
        'gameResultPlayers': <dynamic>[],
      });
      await tester.pump();
      await tester.pump();

      final strings = s.container.read(playGameStringsProvider);
      final collectRewards = find.text(strings.collectRewards);
      expect(collectRewards, findsOneWidget, reason: 'sanity');
      await tester.tap(collectRewards);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(
        find.byType(GameControllerScreen),
        findsNothing,
        reason: 'the real leave path completed — exactly one clean pop',
      );
      expect(find.byType(RoundLottieDialog), findsNothing);
    },
  );
}
