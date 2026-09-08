import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// BUG-01 + BUG-02 (final audit) regression tests.
//
// BUG-01: once GameOver/GameFinished/GameTerminated has set
// GameSessionState.result, the reducer's own hub-event entry point
// (GameController._onHubEvent) had no guard — a late TimeStarted,
// TimerUpdatedSeconds, ChangeTurn, or stale GameUpdated arriving afterward
// on the bindings stream would still be applied, silently re-enabling
// isTimerStarted/answersUnlocked (or moving currentTurn/phase) behind the
// already-showing result dialog, since endGame deliberately leaves `phase`
// untouched so the round stays "on screen" underneath it.
//
// BUG-02: the round-intro scheduling path (GameControllerScreen's
// ref.listen -> RoundScreenHandler.showRoundIntro) only checked
// `_isRoundPhase`, which is still true after endGame — so a GameOver
// landing within the same frame as entering a round could let the intro
// dialog show over/behind the result dialog.
//
// Both are fixed with a single, narrow `result != null` guard each: one in
// GameController._onHubEvent (exempting the terminal events themselves and
// GameRestore, the authoritative resync mechanism), one in showRoundIntro.

const _localId = '47';
const _opponentId = '211403';

const _players = [
  {'id': _localId, 'playerName': 'me'},
  {'id': _opponentId, 'playerName': 'them'},
];

Map<String, dynamic> _gameJson({
  String id = 'g1',
  required int status,
  int type = 1,
  List<Map<String, dynamic>>? players = _players,
  String? currentTurn,
  bool? isTimerStarted,
}) =>
    {
      'id': id,
      'status': status,
      'type': type,
      'groupId': 'grp',
      if (players != null) 'players': players,
      if (currentTurn != null) 'currentTurn': currentTurn,
      if (isTimerStarted != null) 'isTimerStarted': isTimerStarted,
    };

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

  void emit(String name, [Map<String, dynamic>? data]) =>
      _events.add(GameHubEvent(name: name, data: data));

  @override
  void dispose() {
    _events.close();
  }
}

void main() {
  group('reducer — post-GameOver event guard (BUG-01)', () {
    late ProviderContainer container;
    late _FakeSignalRService signalR;
    late _FakeHubBindings bindings;

    Future<void> setUpContainer() async {
      SharedPreferences.setMockInitialValues({
        'user_id': _localId,
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

    GameSessionState current() => container.read(gameControllerProvider);

    setUp(() async => setUpContainer());

    // Delivers everything through the real GameController._onHubEvent
    // pipeline (not direct method calls), since that is exactly where the
    // new guard lives.
    Future<void> emit(String name, [Map<String, dynamic>? data]) async {
      bindings.emit(name, data);
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> startRoundAndArmTimer(int type) async {
      await emit(PlayGameHubEvents.gameStarted, _gameJson(status: 3, type: type));
      await emit(PlayGameHubEvents.timeStarted, {'arg0': '', 'arg1': 'g1'});
      await emit(PlayGameHubEvents.timerUpdatedSeconds, {'arg0': 12.0, 'arg1': 'g1'});
      expect(current().game?.isTimerStarted, isTrue, reason: 'sanity');
      expect(current().answersUnlocked, isTrue, reason: 'sanity');
    }

    Future<void> endGameAbruptly({String winnerId = _opponentId}) async {
      await emit(PlayGameHubEvents.gameOver, {
        'gameId': 'g1',
        'winnerId': winnerId,
        'gameResultPlayers': <dynamic>[],
      });
      expect(current().result, isNotNull, reason: 'sanity');
      expect(current().game?.isTimerStarted, isFalse,
          reason: 'sanity — endGame already freezes this');
      expect(current().answersUnlocked, isFalse,
          reason: 'sanity — endGame already freezes this');
    }

    test('a late TimeStarted cannot restart the timer', () async {
      await startRoundAndArmTimer(3); // Bell
      await endGameAbruptly();
      final frozenLastEvent = current().lastEventName;

      await emit(PlayGameHubEvents.timeStarted, {'arg0': '', 'arg1': 'g1'});

      expect(current().game?.isTimerStarted, isFalse);
      expect(
        current().lastEventName,
        frozenLastEvent,
        reason: 'the event must be fully ignored, not just its timer effect',
      );
    });

    test(
      'a late TimerUpdatedSeconds cannot unlock answers or restart the '
      'timer',
      () async {
        await startRoundAndArmTimer(1); // WDYK
        await endGameAbruptly();
        final frozenLastEvent = current().lastEventName;

        await emit(
          PlayGameHubEvents.timerUpdatedSeconds,
          {'arg0': 9.0, 'arg1': 'g1'},
        );

        expect(current().answersUnlocked, isFalse);
        expect(current().game?.isTimerStarted, isFalse);
        expect(current().lastEventName, frozenLastEvent);
      },
    );

    test('a late GameUpdated cannot resurrect timer/answer state', () async {
      await startRoundAndArmTimer(4); // Comeback
      await endGameAbruptly();
      final frozenLastEvent = current().lastEventName;

      await emit(
        PlayGameHubEvents.gameUpdated,
        _gameJson(status: 3, type: 4, isTimerStarted: true),
      );

      expect(current().game?.isTimerStarted, isFalse);
      expect(current().answersUnlocked, isFalse);
      expect(
        current().phase,
        GamePhase.comeBack,
        reason: 'a stale GameUpdated must not re-route phase either',
      );
      expect(current().lastEventName, frozenLastEvent);
    });

    test(
      'a late ChangeTurn cannot mutate active round state behind the '
      'result dialog',
      () async {
        await startRoundAndArmTimer(1); // WDYK
        final turnBeforeEnd = current().game?.currentTurn;
        await endGameAbruptly();
        final frozenLastEvent = current().lastEventName;

        await emit(PlayGameHubEvents.changeTurn, {'playerId': _opponentId});

        expect(current().game?.currentTurn, turnBeforeEnd);
        expect(current().lastEventName, frozenLastEvent);
      },
    );

    test('a late RoundFinished/NextRoundStarted cannot resurrect the round',
        () async {
      await startRoundAndArmTimer(5); // Breaker
      await endGameAbruptly();
      final frozenPhase = current().phase;

      await emit(PlayGameHubEvents.roundFinished, null);
      expect(current().phase, frozenPhase);

      await emit(PlayGameHubEvents.nextRoundStarted, {'arg0': 1, 'arg1': 'g1'});
      expect(current().phase, frozenPhase);
      expect(current().result, isNotNull);
    });

    test('existing GameOver/result behavior still works normally', () async {
      await startRoundAndArmTimer(5); // Breaker
      await emit(PlayGameHubEvents.gameOver, {
        'gameId': 'g1',
        'winnerId': _localId,
        'gameResultPlayers': [
          {'playerId': _localId, 'points': 4, 'winningCoins': 8, 'winningXP': 16},
          {'playerId': _opponentId, 'points': 1, 'winningCoins': 4, 'winningXP': 8},
        ],
      });

      expect(current().result, GameResult.win);
      expect(current().myResult?.points, 4);
      expect(current().opponentResult?.points, 1);
      expect(current().winnerPlayer?.id, _localId);
    });

    test(
      'a repeated GameOver/GameFinished/GameTerminated still resolves '
      '(terminal events remain exempt from the guard)',
      () async {
        await startRoundAndArmTimer(2); // Auction
        await endGameAbruptly(winnerId: _opponentId);
        expect(current().result, GameResult.loss);

        await emit(PlayGameHubEvents.gameFinished, {'winnerId': _opponentId});
        expect(current().result, GameResult.loss);
      },
    );

    test('existing GameRestore behavior remains intact before the game ends',
        () async {
      await startRoundAndArmTimer(2); // Auction
      await emit(
        PlayGameHubEvents.gameRestore,
        _gameJson(status: 3, type: 2, currentTurn: _opponentId),
      );
      expect(current().game?.currentTurn, _opponentId);
    });

    test(
      'GameRestore is exempt from the post-GameOver guard and still '
      'resyncs the roster, while result is preserved',
      () async {
        await startRoundAndArmTimer(3); // Bell
        await endGameAbruptly();

        await emit(
          PlayGameHubEvents.gameRestore,
          _gameJson(
            status: 3,
            type: 3,
            players: const [
              {'id': _localId, 'playerName': 'me', 'points': 99},
              {'id': _opponentId, 'playerName': 'them', 'points': 1},
            ],
          ),
        );

        expect(
          current().me?.points,
          99,
          reason: 'GameRestore must still resync the roster after result is '
              'set — it is the authoritative resync mechanism, not a stale '
              'event',
        );
        expect(
          current().result,
          isNotNull,
          reason: 'result must survive the restore (existing FinishRound '
              'fix)',
        );
      },
    );
  });

  group('widget — round intro suppressed once result is set (BUG-02)', () {
    late ProviderContainer container;

    GameController notifier() =>
        container.read(gameControllerProvider.notifier);
    GameSessionState session() => container.read(gameControllerProvider);

    Future<void> pumpHost(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'user_id': _localId,
        'app_language': AppLanguage.english,
      });
      final prefs = await SharedPrefsService.init();
      final signalR = _FakeSignalRService();
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
      'a scheduled round intro is not shown when result != null',
      (tester) async {
        await pumpHost(tester);

        // Enters a round-intro phase (schedules the intro's postFrameCallback)
        // then, before any frame runs it, the game ends — endGame leaves
        // phase alone, so _isRoundPhase would still be true when the
        // callback eventually fires.
        notifier().applySessionEvent(
          PlayGameHubEvents.gameStarted,
          _gameJson(status: 3, type: 1),
        );
        notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
          'gameId': 'g1',
          'winnerId': _localId,
          'gameResultPlayers': <dynamic>[],
        });
        expect(session().phase, GamePhase.wdyk, reason: 'sanity');
        expect(session().result, GameResult.win, reason: 'sanity');

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 2000));
        await tester.pump();

        expect(find.byType(RoundLottieDialog), findsNothing);
      },
    );

    testWidgets(
      'sanity: the round intro still shows normally when the game has not '
      'ended',
      (tester) async {
        await pumpHost(tester);

        notifier().applySessionEvent(
          PlayGameHubEvents.gameStarted,
          _gameJson(status: 3, type: 1),
        );
        expect(session().result, isNull, reason: 'sanity');

        await tester.pump();
        await tester.pump();

        expect(find.byType(RoundLottieDialog), findsOneWidget);
      },
    );
  });
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
