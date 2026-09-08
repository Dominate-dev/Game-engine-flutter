import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// GameController routing. Events and payloads are constructed by the test.
// Nothing here asserts what the backend actually sends — only how the
// controller routes a payload it is handed.

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

  void emit(String name, [Map<String, dynamic>? data]) =>
      _events.add(GameHubEvent(name: name, data: data));

  @override
  void dispose() {
    _events.close();
  }
}

Map<String, dynamic> _gameJson({
  String id = 'g1',
  required int status,
  int type = 1,
  List<Map<String, dynamic>>? players,
  String? currentTurn,
}) =>
    {
      'id': id,
      'status': status,
      'type': type,
      'groupId': 'grp',
      if (players != null) 'players': players,
      if (currentTurn != null) 'currentTurn': currentTurn,
    };

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;
  late _FakeHubBindings bindings;

  Future<void> setUpContainer({
    String userId = '47',
    String language = AppLanguage.english,
  }) async {
    // user_id is persisted as a String by SharedPrefsService.
    SharedPreferences.setMockInitialValues({
      'user_id': userId,
      'app_language': language,
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
    // gameControllerProvider is autoDispose; hold a listener so state survives
    // across awaits within a test.
    final sub = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(sub.close);
  }

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);
  GameSessionState current() => container.read(gameControllerProvider);

  setUp(() async => setUpContainer());

  group('initial state', () {
    test('starts in the waiting phase with no result', () {
      expect(current().phase, GamePhase.waiting);
      expect(current().result, isNull);
    });
  });

  group('_routeByStatus — game status selects the phase', () {
    test('status 1 routes to waiting', () {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameJoined,
        _gameJson(status: 1),
      );
      expect(current().phase, GamePhase.waiting);
    });

    test('status 2 routes to the lobby', () {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameJoined,
        _gameJson(status: 2),
      );
      expect(current().phase, GamePhase.lobbyPlay);
    });

    test('status 3 routes to the round named by type', () {
      for (final entry in {
        1: GamePhase.wdyk,
        2: GamePhase.auction,
        3: GamePhase.bell,
        4: GamePhase.comeBack,
        5: GamePhase.breaker,
      }.entries) {
        notifier().applySessionEvent(
          PlayGameHubEvents.gameStarted,
          _gameJson(status: 3, type: entry.key),
        );
        expect(
          current().phase,
          entry.value,
          reason: 'round type ${entry.key}',
        );
      }
    });

    test('status 4 ends the game', () {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameUpdated,
        _gameJson(status: 4),
      );
      expect(current().result, GameResult.ended);
    });
  });

  group('game-over routing', () {
    test('a winning payload for this user yields a win', () {
      notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
        'gameId': 'g1',
        'winnerId': '47',
        'gameResultPlayers': <dynamic>[],
      });
      expect(current().result, GameResult.win);
    });

    // R-13: GameOverResult.isWinner used to compare winnerId with raw `==`
    // instead of playerIdsEqual — a hub-JSON-sourced winnerId with
    // surrounding whitespace or numeric-string drift (e.g. "007" vs "7")
    // would silently fail to match this device's own userId, telling a
    // winning player they lost. Exercised here through the real
    // applySessionEvent path, not just the isolated isWinner unit.
    test(
      'a winnerId with surrounding whitespace still yields a win for this '
      'user',
      () {
        notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
          'gameId': 'g1',
          'winnerId': ' 47 ',
          'gameResultPlayers': <dynamic>[],
        });
        expect(current().result, GameResult.win);
      },
    );

    test('a payload naming another winner yields a loss', () {
      notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
        'gameId': 'g1',
        'winnerId': '211403',
        'gameResultPlayers': <dynamic>[],
      });
      expect(current().result, GameResult.loss);
    });

    // UNRESOLVED — characterization only, NOT an endorsement.
    // _gameOverFromData always returns an object for a game-over event (winnerId
    // E6 regression. When no winner is named the result path must fall through
    // to _resultFromData instead of short-circuiting to a loss.
    test('an explicit isWin flag is honoured when no winner is named', () {
      notifier().applySessionEvent(PlayGameHubEvents.gameFinished, {
        'isWin': true,
      });
      expect(current().result, GameResult.win);
    });

    test('an explicit isWin false yields a loss', () {
      notifier().applySessionEvent(PlayGameHubEvents.gameFinished, {
        'isWin': false,
      });
      expect(current().result, GameResult.loss);
    });

    test('a textual result field is honoured when no winner is named', () {
      notifier().applySessionEvent(PlayGameHubEvents.gameFinished, {
        'result': 'won',
      });
      expect(current().result, GameResult.win);
    });

    // E1 regression. A payload that determines nothing must not be reported as
    // a defeat — the neutral end-of-game result is the only safe default.
    test(
      'an indeterminate game-over yields a neutral ended result, not a loss',
      () {
        notifier().applySessionEvent(PlayGameHubEvents.gameTerminated, {
          'gameId': 'g1',
        });
        expect(current().result, GameResult.ended);
      },
    );

    test('a named winner still takes precedence over payload result fields',
        () {
      notifier().applySessionEvent(PlayGameHubEvents.gameOver, {
        'gameId': 'g1',
        'winnerId': '47',
        'isWin': false,
        'gameResultPlayers': <dynamic>[],
      });
      expect(
        current().result,
        GameResult.win,
        reason: 'winnerId is authoritative when present',
      );
    });
  });

  group('_onHubEvent phase filtering', () {
    test('waiting-screen events are not routed while in the waiting phase',
        () async {
      expect(current().phase, GamePhase.waiting);
      bindings.emit(PlayGameHubEvents.gameUpdated, _gameJson(status: 3));
      await Future<void>.delayed(Duration.zero);
      expect(
        current().phase,
        GamePhase.waiting,
        reason: 'the waiting screen owns this event in this phase',
      );
    });

    test('lobby-screen events are not routed while in the lobby phase',
        () async {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameJoined,
        _gameJson(status: 2),
      );
      expect(current().phase, GamePhase.lobbyPlay);
      bindings.emit(PlayGameHubEvents.playerReady, {'playerId': '48'});
      await Future<void>.delayed(Duration.zero);
      expect(current().phase, GamePhase.lobbyPlay);
    });

    test('session events are routed when the phase does not own them',
        () async {
      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _gameJson(status: 3, type: 1),
      );
      expect(current().phase, GamePhase.wdyk);
      bindings.emit(
        PlayGameHubEvents.gameUpdated,
        _gameJson(status: 3, type: 3),
      );
      await Future<void>.delayed(Duration.zero);
      expect(current().phase, GamePhase.bell);
    });
  });

  group('onRecovered', () {
    test('asks the hub to re-check the player game', () async {
      await notifier().onRecovered();
      expect(
        signalR.invocations.map((i) => i.method),
        contains(PlayGameHubEvents.checkPlayerGame),
      );
    });
  });

  // W-2: GameControllerScreen's switch also called applySharedRoundEvent /
  // applySessionEvent for nextQuestion, gameOver and gameFinished, while
  // GameController._onHubEvent handled the same three from the bindings
  // stream. Each arrival mutated state twice and endGame ran twice.
  //
  // GameSessionState has no value equality, so a second application produces
  // a second notification even when the content is identical — the counts
  // below would be 2, not 1, if either path were restored.
  group('single delivery of state-only events', () {
    Future<void> startRound() async {
      bindings.emit(
        PlayGameHubEvents.gameStarted,
        _gameJson(
          status: 3,
          type: 1,
          players: [
            {'id': '47', 'playerName': 'me'},
            {'id': '211403', 'playerName': 'them'},
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    // The bindings stream delivers asynchronously, so the listener has to
    // stay open across the microtask that carries the event.
    Future<int> countNotifications(void Function() body) async {
      var count = 0;
      final sub = container.listen(gameControllerProvider, (_, __) => count++);
      body();
      await Future<void>.delayed(Duration.zero);
      sub.close();
      return count;
    }

    test('the host screen no longer claims the state-only events', () {
      for (final name in [
        PlayGameHubEvents.nextQuestion,
        PlayGameHubEvents.gameOver,
        PlayGameHubEvents.gameFinished,
      ]) {
        expect(
          PlayGameHubEvents.hostScreenEvents,
          isNot(contains(name)),
          reason: '$name is state-only and is applied by GameController',
        );
      }
    });

    test('the host screen still claims its dialog and navigation events', () {
      for (final name in [
        PlayGameHubEvents.playerEmoted,
        PlayGameHubEvents.playerLeft,
        PlayGameHubEvents.changeTurn,
        PlayGameHubEvents.penalty,
        PlayGameHubEvents.timeStarted,
        PlayGameHubEvents.playerPassed,
        PlayGameHubEvents.playerAnswered,
        PlayGameHubEvents.correctAnswer,
      ]) {
        expect(PlayGameHubEvents.hostScreenEvents, contains(name));
      }
    });

    test('the state-only events still reach the controller path', () {
      for (final name in [
        PlayGameHubEvents.nextQuestion,
        PlayGameHubEvents.gameOver,
        PlayGameHubEvents.gameFinished,
        PlayGameHubEvents.gameRestore,
      ]) {
        expect(
          PlayGameHubEvents.lifetimeEvents,
          contains(name),
          reason: 'PlayGameHubBindings.bindAll must still subscribe $name',
        );
      }
      expect(
        PlayGameHubEvents.sharedRoundEvents,
        contains(PlayGameHubEvents.nextQuestion),
      );
      expect(
        PlayGameHubEvents.sessionEvents,
        containsAll([
          PlayGameHubEvents.gameOver,
          PlayGameHubEvents.gameFinished,
          PlayGameHubEvents.gameRestore,
        ]),
      );
    });

    test('nextQuestion is applied exactly once', () async {
      await startRound();
      final notifications = await countNotifications(() {
        bindings.emit(PlayGameHubEvents.nextQuestion, {
          'id': 7,
          'text': 'س',
          'textEn': 'q',
          'questionNumber': 2,
          'roundTotalQuestionsCount': 5,
          'answers': [
            {'id': 1, 'text': 'أ', 'textEn': 'a'},
            {'id': 2, 'text': 'ب', 'textEn': 'b'},
          ],
        });
      });

      expect(current().game?.currentQuestion?.id, 7);
      expect(current().game?.currentQuestion?.answers.length, 2);
      expect(current().game?.isTimerStarted, isFalse);
      expect(notifications, 1);
    });

    test('gameOver produces exactly one terminal transition', () async {
      await startRound();
      expect(current().result, isNull);
      final notifications = await countNotifications(() {
        bindings.emit(PlayGameHubEvents.gameOver, {
          'winnerId': '47',
          'players': [
            {'id': '47', 'playerName': 'me'},
            {'id': '211403', 'playerName': 'them'},
          ],
        });
      });

      expect(current().result, GameResult.win);
      expect(notifications, 1);
    });

    test('gameFinished is handled exactly once', () async {
      await startRound();
      final notifications = await countNotifications(() {
        bindings.emit(PlayGameHubEvents.gameFinished, {'winnerId': '211403'});
      });

      expect(current().result, GameResult.loss);
      expect(notifications, 1);
    });
  });

  // GameRestore is the reconnect path: onRecovered invokes CheckPlayerGame and
  // the server answers with the full snapshot. It was never on the host
  // screen, and this change must leave it alone.
  group('GameRestore recovery', () {
    test('restores the full snapshot into state', () async {
      bindings.emit(
        PlayGameHubEvents.gameStarted,
        _gameJson(
          status: 3,
          type: 1,
          players: [
            {'id': '47', 'playerName': 'me'},
            {'id': '211403', 'playerName': 'them'},
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(current().phase, GamePhase.wdyk);

      bindings.emit(PlayGameHubEvents.gameRestore, {
        'id': 'g1',
        'status': 3,
        'type': 1,
        'groupId': 'grp',
        'currentTurn': '211403',
        'currentTimerValue': 18,
        'players': [
          {'id': '47', 'playerName': 'me', 'penalty': 2, 'points': 30},
          {'id': '211403', 'playerName': 'them', 'penalty': 1, 'points': 10},
        ],
        'currentQuestion': {
          'id': 9,
          'text': 'س',
          'questionNumber': 3,
          'roundTotalQuestionsCount': 5,
          'answers': [
            {'id': 4, 'text': 'أ'},
          ],
        },
      });
      await Future<void>.delayed(Duration.zero);

      expect(current().phase, GamePhase.wdyk);
      expect(current().game?.currentTurn, '211403');
      expect(current().game?.currentTimerValue, 18);
      expect(current().game?.currentQuestion?.id, 9);
      expect(current().me?.points, 30);
      expect(current().me?.penalty, 2);
      expect(current().opponent?.points, 10);
      expect(current().lastEventName, PlayGameHubEvents.gameRestore);
      expect(current().data?['currentTurn'], '211403');
    });

    test('onRecovered still asks the server for the snapshot', () async {
      await notifier().onRecovered();
      expect(
        signalR.invocations.map((i) => i.method),
        contains(PlayGameHubEvents.checkPlayerGame),
      );
    });
  });

  // The six round events the screen kept are a deliberate split: the screen
  // shows the dialog, GameController applies the state. Removing the three
  // state-only cases must not disturb that.
  group('screen-only dialog handlers', () {
    Future<void> startRound() async {
      bindings.emit(
        PlayGameHubEvents.gameStarted,
        _gameJson(
          status: 3,
          type: 1,
          players: [
            {'id': '47', 'playerName': 'me'},
            {'id': '211403', 'playerName': 'them'},
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    test('the round dialogs still fire', () async {
      await startRound();
      expect(current().phase, GamePhase.wdyk);

      final shown = <Widget>[];
      Future<void> record({
        required Widget child,
        bool barrierDismissible = true,
      }) async {
        shown.add(child);
      }

      // CorrectAnswer and PlayerPassed belong to one player now, so they carry
      // the local id — a payload naming nobody deliberately shows nothing.
      notifier().onCorrectAnswer(
        {'arg0': 'a', 'arg1': 'a', 'arg2': '47'},
        record,
      );
      notifier().onTimeStarted(null, record);
      notifier().onPlayerPassed({'arg0': '47', 'arg1': 'g1'}, record);
      notifier().onPlayerAnswered(
        {'answerText': 'أ', 'answerTextEn': 'a'},
        record,
      );
      notifier().onPenalty({'playerId': '47', 'type': 1}, record);
      // Last, so its own post-close grace period has nothing left to matter to.
      notifier().onChangeTurn({'playerId': '47'}, record);

      // WDYK overlays are sequenced rather than stacked, so let them drain.
      for (var i = 0; i < 20 && shown.length < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(shown.length, 6);
    });

    test('the controller hub path applies state without a dialog surface',
        () async {
      await startRound();
      bindings.emit(PlayGameHubEvents.timeStarted, {'arg0': '', 'arg1': 'g1'});
      await Future<void>.delayed(Duration.zero);

      expect(current().phase, GamePhase.wdyk);
      expect(current().game?.isTimerStarted, isTrue);
      expect(current().lastEventName, PlayGameHubEvents.timeStarted);
    });
  });

  // W-5 / W-6: payload hardening for the two round dialogs.
  //
  // Verified runtime shapes:
  //   Penalty        [{playerId: 47, type: 1}, gameId]
  //   PlayerAnswered [{playerId: 10002, ...}, gameId]
  //   CorrectAnswer  [answerText, answerTextEn, playerId, gameId]
  //
  // mapFromArgs returns args.first when it is a map, so Penalty and
  // PlayerAnswered are named; only CorrectAnswer produces arg0/arg1.
  group('round dialog payload parsing', () {
    late List<Widget> shown;

    Future<void> record({
      required Widget child,
      bool barrierDismissible = true,
    }) async {
      shown.add(child);
    }

    Future<void> enterRound({String language = AppLanguage.english}) async {
      await setUpContainer(language: language);
      shown = [];
      bindings.emit(
        PlayGameHubEvents.gameStarted,
        _gameJson(
          status: 3,
          type: 1,
          players: [
            {'id': '47', 'playerName': 'me'},
            {'id': '211403', 'playerName': 'them'},
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    String? lottieText() => (shown.single as RoundLottieDialog).text;
    String answeredText() => (shown.single as PlayerAnsweredDialog).answer;

    group('W-5 — penalty type', () {
      test('the verified named payload resolves the type', () async {
        await enterRound();
        notifier().onPenalty({'playerId': 47, 'type': 1}, record);
        expect(shown, hasLength(1));
        expect(lottieText(), isNotEmpty);
      });

      test('a numeric string type resolves', () async {
        await enterRound();
        notifier().onPenalty({'playerId': 47, 'type': '1'}, record);
        expect(shown, hasLength(1));
      });

      // Only the type read is hardened here. The playerId read is still
      // raw map access and is left to W-7.
      test('a PascalCase type key resolves', () async {
        await enterRound();
        notifier().onPenalty({'playerId': 47, 'Type': 2}, record);
        expect(shown, hasLength(1));
      });

      test('a double type resolves', () async {
        await enterRound();
        notifier().onPenalty({'playerId': 47, 'type': 2.0}, record);
        expect(shown, hasLength(1));
      });

      // TypePenalty semantics are unchanged: only 1 and 2 are known, and an
      // unknown id still shows nothing rather than guessing.
      test('an unknown type id shows no dialog', () async {
        await enterRound();
        notifier().onPenalty({'playerId': 47, 'type': 9}, record);
        expect(shown, isEmpty);
      });

      test('a missing type shows no dialog', () async {
        await enterRound();
        notifier().onPenalty({'playerId': 47}, record);
        expect(shown, isEmpty);
      });

      test('a non-numeric type shows no dialog instead of throwing', () async {
        await enterRound();
        notifier().onPenalty({'playerId': 47, 'type': 'timeout'}, record);
        expect(shown, isEmpty);
      });

      test('null and empty payloads show no dialog', () async {
        await enterRound();
        notifier().onPenalty(null, record);
        notifier().onPenalty(const {}, record);
        expect(shown, isEmpty);
      });

      // wrongAnswer is shown to the penalised player only — unchanged.
      test('a wrongAnswer penalty for the opponent shows no dialog', () async {
        await enterRound();
        notifier().onPenalty({'playerId': 211403, 'type': 2}, record);
        expect(shown, isEmpty);
      });
    });

    group('W-6 — answered text', () {
      test('the verified named payload resolves the text', () async {
        await enterRound();
        notifier().onPlayerAnswered(
          {'playerId': 10002, 'answerText': 'أ', 'answerTextEn': 'a'},
          record,
        );
        expect(answeredText(), 'a');
      });

      test('a positional payload resolves the text', () async {
        await enterRound();
        notifier().onPlayerAnswered(
          HubEventPayload.mapFromArgs(['أ', 'a', '47', 'g1']),
          record,
        );
        expect(answeredText(), 'a');
      });

      test('Arabic is preferred when the app language is Arabic', () async {
        await enterRound(language: AppLanguage.arabic);
        notifier().onPlayerAnswered(
          {'answerText': 'أ', 'answerTextEn': 'a'},
          record,
        );
        expect(answeredText(), 'أ');
      });

      test('Arabic falls back to English when Arabic is absent', () async {
        await enterRound(language: AppLanguage.arabic);
        notifier().onPlayerAnswered({'answerTextEn': 'a'}, record);
        expect(answeredText(), 'a');
      });

      test('English falls back to Arabic when English is absent', () async {
        await enterRound();
        notifier().onPlayerAnswered({'answerText': 'أ'}, record);
        expect(answeredText(), 'أ');
      });

      test('a PascalCase key resolves', () async {
        await enterRound();
        notifier().onPlayerAnswered(
          {'AnswerText': 'أ', 'AnswerTextEn': 'a'},
          record,
        );
        expect(answeredText(), 'a');
      });

      test('surrounding whitespace is trimmed', () async {
        await enterRound();
        notifier().onPlayerAnswered({'answerTextEn': '  a  '}, record);
        expect(answeredText(), 'a');
      });

      test('blank, empty and null payloads show no dialog', () async {
        await enterRound();
        notifier().onPlayerAnswered(null, record);
        notifier().onPlayerAnswered(const {}, record);
        notifier().onPlayerAnswered({'answerText': '   '}, record);
        expect(shown, isEmpty);
      });
    });
  });

  // W-7: both round dialog handlers resolved the name with
  // `isMe ? me : opponent`, so an empty, unmatched or malformed id was
  // reported as the opponent. Resolution is now positive on both sides.
  group('round dialog player-name resolution', () {
    late List<Widget> shown;

    Future<void> record({
      required Widget child,
      bool barrierDismissible = true,
    }) async {
      shown.add(child);
    }

    Future<void> enterRound() async {
      await setUpContainer();
      shown = [];
      bindings.emit(
        PlayGameHubEvents.gameStarted,
        _gameJson(
          status: 3,
          type: 1,
          players: [
            {'id': '47', 'playerName': 'me'},
            {'id': '211403', 'playerName': 'them'},
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    String? lottieText() => (shown.single as RoundLottieDialog).text;

    group('ChangeTurn', () {
      test('the local id resolves the local name', () async {
        await enterRound();
        notifier().onChangeTurn({'playerId': '47'}, record);
        expect(
          lottieText(),
          PlayGameStrings.forLanguage(AppLanguage.english)
              .turnOverlayText(isMine: true, playerName: 'me'),
          reason: 'resolved as my own turn — the name is what resolved it',
        );
      });

      test('the opponent id resolves the opponent name', () async {
        await enterRound();
        notifier().onChangeTurn({'playerId': '211403'}, record);
        expect(
          lottieText(),
          PlayGameStrings.forLanguage(AppLanguage.english)
              .turnOverlayText(isMine: false, playerName: 'them'),
        );
      });

      test('a positional payload resolves the same way', () async {
        await enterRound();
        notifier().onChangeTurn(
          HubEventPayload.mapFromArgs(['211403', 'g1']),
          record,
        );
        expect(
          lottieText(),
          PlayGameStrings.forLanguage(AppLanguage.english)
              .turnOverlayText(isMine: false, playerName: 'them'),
        );
      });

      test('an id matching neither player shows no dialog', () async {
        await enterRound();
        notifier().onChangeTurn({'playerId': '900'}, record);
        expect(shown, isEmpty);
      });

      test('an empty, missing or null id shows no dialog', () async {
        await enterRound();
        notifier().onChangeTurn({'playerId': ''}, record);
        notifier().onChangeTurn(const {}, record);
        notifier().onChangeTurn(null, record);
        expect(shown, isEmpty);
      });
    });

    group('Penalty', () {
      test('a local timeout keeps the strike wording', () async {
        await enterRound();
        notifier().onPenalty({'playerId': 47, 'type': 1}, record);
        expect(
          lottieText(),
          PlayGameStrings.forLanguage(AppLanguage.english).strike,
        );
      });

      test('an opponent timeout keeps the timeout wording', () async {
        await enterRound();
        notifier().onPenalty({'playerId': 211403, 'type': 1}, record);
        expect(
          lottieText(),
          PlayGameStrings.forLanguage(AppLanguage.english).timeout,
        );
      });

      test('an id matching neither player shows no dialog', () async {
        await enterRound();
        notifier().onPenalty({'playerId': 900, 'type': 1}, record);
        expect(shown, isEmpty);
      });

      test('an empty, missing or null id shows no dialog', () async {
        await enterRound();
        notifier().onPenalty({'playerId': '', 'type': 1}, record);
        notifier().onPenalty({'type': 1}, record);
        notifier().onPenalty(null, record);
        expect(shown, isEmpty);
      });

      // The unmatched id used to resolve to the opponent, which showed the
      // opponent's timeout dialog for an event about nobody.
      test('an unmatched id no longer produces an opponent dialog', () async {
        await enterRound();
        notifier().onPenalty({'playerId': 'not-a-player', 'type': 1}, record);
        expect(shown, isEmpty);
      });
    });
  });

  // ChangeTurn arrives positionally as [playerId, gameId]. An explicitly
  // empty playerId clears the turn; leaving the previous value in place made
  // the last named player look available indefinitely.
  group('ChangeTurn turn clearing', () {
    Future<void> startRound() async {
      bindings.emit(
        PlayGameHubEvents.gameStarted,
        _gameJson(
          status: 3,
          type: 1,
          currentTurn: '47',
          players: [
            {'id': '47', 'playerName': 'me'},
            {'id': '211403', 'playerName': 'them'},
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> changeTurn(List<Object?> args) async {
      bindings.emit(
        PlayGameHubEvents.changeTurn,
        HubEventPayload.mapFromArgs(args),
      );
      await Future<void>.delayed(Duration.zero);
    }

    test('an explicitly empty playerId clears the turn', () async {
      await startRound();
      expect(current().isMyTurn, isTrue);
      expect(current().isOpponentTurn, isFalse);

      await changeTurn(['', 'g1']);

      expect(current().isMyTurn, isFalse);
      expect(current().isOpponentTurn, isFalse);
      expect(current().game?.currentTurn, isNot('47'));
    });

    test('an empty playerId is not treated as ALLOW_ALL', () async {
      await startRound();
      await changeTurn(['', 'g1']);

      expect(current().game?.currentTurn, isNot(CreatedGame.allowAllTurn));
      expect(current().isMyTurn, isFalse);
      expect(current().isOpponentTurn, isFalse);
    });

    test('a named player id still grants only that player', () async {
      await startRound();
      await changeTurn(['211403', 'g1']);

      expect(current().isMyTurn, isFalse);
      expect(current().isOpponentTurn, isTrue);

      await changeTurn(['47', 'g1']);

      expect(current().isMyTurn, isTrue);
      expect(current().isOpponentTurn, isFalse);
    });

    test('ALLOW_ALL still grants both players', () async {
      await startRound();
      await changeTurn([CreatedGame.allowAllTurn, 'g1']);

      expect(current().isMyTurn, isTrue);
      expect(current().isOpponentTurn, isTrue);
    });

    test('a clear can be followed by a new named turn', () async {
      await startRound();
      await changeTurn(['', 'g1']);
      expect(current().isMyTurn, isFalse);

      await changeTurn(['47', 'g1']);

      expect(current().isMyTurn, isTrue);
      expect(current().game?.currentTurn, '47');
    });

    test('a named empty playerId also clears the turn', () async {
      await startRound();
      bindings.emit(PlayGameHubEvents.changeTurn, {'playerId': ''});
      await Future<void>.delayed(Duration.zero);

      expect(current().isMyTurn, isFalse);
      expect(current().isOpponentTurn, isFalse);
    });

    // A payload with no turn field is not a clear.
    test('a payload carrying no turn field leaves the turn alone', () async {
      await startRound();
      bindings.emit(PlayGameHubEvents.changeTurn, const {});
      await Future<void>.delayed(Duration.zero);

      expect(current().game?.currentTurn, '47');
      expect(current().isMyTurn, isTrue);
    });
  });
}
