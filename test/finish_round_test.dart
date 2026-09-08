import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// FinishRound / end-of-game flow.
//
// RoundFinished / ShowResults -> GamePhase.finishRound (a shared "please
// wait" screen, same for every round). GameOver / GameFinished /
// GameTerminated -> endGame, which sets result + gameOver but deliberately
// leaves phase untouched — whatever was on screen stays there, covered by
// the modal result dialog GameControllerScreen shows.
//
// These pin down the gaps found while auditing that flow:
//   - endGame did not freeze isTimerStarted / answersUnlocked, so a round
//     that ends abruptly (GameOver with no preceding RoundFinished) left
//     RoundScoreColumn's countdown running and answering flagged "open"
//     under the result dialog.
//   - showPhase and _refreshLobby build GameSessionState with a raw
//     constructor, not copyWith. Unlike the neighbouring gameOver field,
//     result was not carried over — any routine event arriving after the
//     game ended (a stray GameUpdated, or a GameRestore) silently reset
//     result back to null.
//   - GameControllerScreen's own direct hub listener (HubEventMixin, a
//     separate pipeline from the reducer stream) kept dispatching round
//     dialogs (ChangeTurn/Penalty/...) with no check that the game had
//     already ended.
/// One hub event listener, named so the map and its iteration share a type.
typedef HubHandler = void Function(List<Object?>?);

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

/// Like [_FakeSignalRService], but actually stores registered listeners so a
/// test can fire them — needed to exercise GameControllerScreen's own direct
/// hub pipeline (HubEventMixin), which none of the existing fakes support.
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

  @override
  void bindAll() {}

  @override
  void bindEvents(Iterable<String> eventNames) {}

  void emit(String name, [Map<String, dynamic>? data]) =>
      _events.add(GameHubEvent(name: name, data: data));

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

/// Silences playback — the round intro plays a sound, then loops music once
/// it closes.
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

const _players = [
  {'id': '47', 'playerName': 'me'},
  {'id': '211403', 'playerName': 'them'},
];

Map<String, dynamic> _gameJson({
  String id = 'g1',
  required int status,
  int type = 1,
  List<Map<String, dynamic>>? players = _players,
}) =>
    {
      'id': id,
      'status': status,
      'type': type,
      'groupId': 'grp',
      if (players != null) 'players': players,
    };

void main() {
  group('reducer — GameController state', () {
    late ProviderContainer container;
    late _FakeSignalRService signalR;
    late _FakeHubBindings bindings;

    Future<void> setUpContainer() async {
      SharedPreferences.setMockInitialValues({
        'user_id': '47',
        'app_language': AppLanguage.english,
      });
      final prefs = await SharedPrefsService.init();
      signalR = _FakeSignalRService();
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

    void startRound(int type) {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _gameJson(status: 3, type: type),
      );
    }

    group('RoundFinished / ShowResults leave every round the same way', () {
      for (final entry in {
        1: GamePhase.wdyk,
        2: GamePhase.auction,
        3: GamePhase.bell,
        4: GamePhase.comeBack,
        5: GamePhase.breaker,
      }.entries) {
        test('round type ${entry.key} reaches GamePhase.finishRound', () {
          startRound(entry.key);
          expect(current().phase, entry.value, reason: 'sanity');
          notifier()
              .applySharedRoundEvent(PlayGameHubEvents.roundFinished, null);
          expect(current().phase, GamePhase.finishRound);
        });
      }

      test('ShowResults reaches GamePhase.finishRound too', () {
        startRound(1);
        notifier().applySharedRoundEvent(PlayGameHubEvents.showResults, null);
        expect(current().phase, GamePhase.finishRound);
      });

      test('a GameOver that follows RoundFinished resolves normally', () {
        startRound(5);
        notifier()
            .applySharedRoundEvent(PlayGameHubEvents.roundFinished, null);
        expect(current().phase, GamePhase.finishRound);

        notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
          'gameId': 'g1',
          'winnerId': '47',
          'gameResultPlayers': <dynamic>[],
        });
        expect(current().result, GameResult.win);
        expect(
          current().phase,
          GamePhase.finishRound,
          reason: 'endGame leaves phase alone — the result dialog covers it',
        );
      });
    });

    group('endGame freezes the shared live-round signals', () {
      void armTimer(int type) {
        startRound(type);
        notifier().applySharedRoundEvent(
          PlayGameHubEvents.timeStarted,
          {'arg0': '', 'arg1': 'g1'},
        );
        notifier().applySharedRoundEvent(
          PlayGameHubEvents.timerUpdatedSeconds,
          {'arg0': 12.0, 'arg1': 'g1'},
        );
        expect(current().game?.isTimerStarted, isTrue, reason: 'sanity');
        expect(current().answersUnlocked, isTrue, reason: 'sanity');
      }

      test(
        'GameOver arriving mid-round, with no RoundFinished first, stops '
        'the countdown and closes answering',
        () {
          armTimer(3); // Bell — nothing has left the round yet.
          notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
            'gameId': 'g1',
            'winnerId': '211403',
            'gameResultPlayers': <dynamic>[],
          });
          expect(current().result, GameResult.loss);
          expect(
            current().game?.isTimerStarted,
            isFalse,
            reason: 'RoundScoreColumn only stops on a true -> false edge',
          );
          expect(current().answersUnlocked, isFalse);
        },
      );

      test('GameTerminated freezes the timer the same way', () {
        armTimer(4); // Comeback.
        notifier().applySessionEvent(
          PlayGameHubEvents.gameTerminated,
          {'gameId': 'g1'},
        );
        expect(current().result, GameResult.ended);
        expect(current().game?.isTimerStarted, isFalse);
        expect(current().answersUnlocked, isFalse);
      });

      test('GameFinished freezes the timer for Breaker too', () {
        armTimer(5);
        notifier().applySessionEvent(
          PlayGameHubEvents.gameFinished,
          {'winnerId': '47'},
        );
        expect(current().result, GameResult.win);
        expect(current().game?.isTimerStarted, isFalse);
        expect(current().answersUnlocked, isFalse);
      });
    });

    group('result survives events that arrive after the game already ended',
        () {
      test('a routine in-progress GameUpdated does not un-end the game', () {
        startRound(1);
        notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
          'gameId': 'g1',
          'winnerId': '47',
          'gameResultPlayers': <dynamic>[],
        });
        expect(current().result, GameResult.win);

        notifier().applySessionEvent(
          PlayGameHubEvents.gameUpdated,
          _gameJson(status: 3, type: 1),
        );
        expect(
          current().result,
          GameResult.win,
          reason: 'showPhase must carry result forward, same as it already '
              'does gameOver',
        );
      });

      test('a lobby-status GameUpdated (_refreshLobby) does not un-end it',
          () {
        startRound(1);
        notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
          'gameId': 'g1',
          'winnerId': '211403',
          'gameResultPlayers': <dynamic>[],
        });
        expect(current().result, GameResult.loss);

        notifier().applySessionEvent(
          PlayGameHubEvents.gameUpdated,
          _gameJson(status: 2, type: 1),
        );
        expect(current().result, GameResult.loss);
      });

      // Requirement: "Restore does not incorrectly revive an
      // already-finished game."
      test('a stray GameRestore does not revive an already-finished game',
          () {
        startRound(2);
        notifier().applySessionEvent(PlayGameHubEvents.gameFinished, {
          'winnerId': '47',
        });
        expect(current().result, GameResult.win);

        notifier().applySessionEvent(
          PlayGameHubEvents.gameRestore,
          _gameJson(status: 3, type: 2),
        );
        expect(
          current().result,
          GameResult.win,
          reason: 'a restore snapshot for the old round must not resurrect '
              'it',
        );
      });
    });

    // W-2-style regression, extended to the finish-round path: the hub
    // bindings stream must still apply exactly once.
    test('RoundFinished delivered on the bindings stream applies once',
        () async {
      startRound(1);
      var notifications = 0;
      final sub = container.listen(
        gameControllerProvider,
        (_, __) => notifications++,
      );
      bindings.emit(PlayGameHubEvents.roundFinished, null);
      // The bindings stream delivers asynchronously — the listener has to
      // stay open across the microtask that carries the event.
      await Future<void>.delayed(Duration.zero);
      sub.close();
      expect(current().phase, GamePhase.finishRound);
      expect(notifications, 1);
    });
  });

  group('widget — GameControllerScreen', () {
    late ProviderContainer container;
    late _FiringSignalRService firingSignalR;

    GameController notifier() =>
        container.read(gameControllerProvider.notifier);
    GameSessionState session() => container.read(gameControllerProvider);

    Future<void> pumpHost(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'user_id': '47',
        'app_language': AppLanguage.english,
      });
      final prefs = await SharedPrefsService.init();
      firingSignalR = _FiringSignalRService();
      container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          signalRServiceProvider.overrideWithValue(firingSignalR),
          playGameHubBindingsProvider
              .overrideWithValue(_FakeHubBindings(firingSignalR)),
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
      'a round dialog from the direct hub listener is no longer shown once '
      'the game has ended',
      (tester) async {
        await pumpHost(tester);
        notifier().applySessionEvent(
          PlayGameHubEvents.gameStarted,
          _gameJson(status: 3, type: 1),
        );
        await tester.pump();
        await tester.pump();
        expect(session().phase, GamePhase.wdyk);

        // Entering the round queues its own 2000ms intro overlay first — let
        // that clear before firing anything else, so every dialog check below
        // is unambiguous.
        await tester.pump(const Duration(milliseconds: 2000));
        await tester.pump();
        expect(find.byType(RoundLottieDialog), findsNothing);

        // Sanity check first: the direct hub pipeline really does reach
        // onEventReceived and shows a round dialog while the game is live.
        firingSignalR.fire(
          PlayGameHubEvents.changeTurn,
          [
            {'playerId': '211403'},
          ],
        );
        await tester.pump();
        expect(find.byType(RoundLottieDialog), findsOneWidget);

        // Let it retire before ending the game, so what follows is
        // unambiguous.
        await tester.pump(const Duration(milliseconds: 1500));
        await tester.pump();
        expect(find.byType(RoundLottieDialog), findsNothing);

        notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
          'gameId': 'g1',
          'winnerId': '47',
          'gameResultPlayers': <dynamic>[],
        });
        expect(session().result, GameResult.win);
        await tester.pump();

        firingSignalR.fire(
          PlayGameHubEvents.changeTurn,
          [
            {'playerId': '211403'},
          ],
        );
        await tester.pump();
        expect(
          find.byType(RoundLottieDialog),
          findsNothing,
          reason: 'no round dialog may show once the game has ended',
        );
      },
    );
  });
}
