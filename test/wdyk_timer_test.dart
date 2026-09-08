import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// WDYK round timer, normal player-id turn. The server owns the value;
// TimerUpdatedSeconds is the only start signal and a stop freezes the
// display where it stands.

const _localId = '47';
const _opponentId = '211403';

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

Map<String, dynamic> _roundJson({int passes = 0, int penalty = 0}) => {
      'id': 'g1',
      'status': 3,
      'type': 1,
      'groupId': 'grp',
      'currentTurn': _localId,
      'players': [
        {
          'id': _localId,
          'playerName': 'me',
          'passes': passes,
          'penalty': penalty,
        },
        {'id': _opponentId, 'playerName': 'them'},
      ],
      'currentQuestion': {
        'id': 1682,
        'text': 'q',
        'textEn': 'q',
        'questionNumber': 1,
        'roundTotalQuestionsCount': 5,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
          {'id': 11, 'text': 'a2', 'textEn': 'a2'},
        ],
      },
    };

void main() {
  late ProviderContainer container;
  late _FakeSignalRService signalR;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  Future<void> pumpRound(
    WidgetTester tester, {
    int passes = 0,
    int penalty = 0,
  }) async {
    SharedPreferences.setMockInitialValues({
      'user_id': _localId,
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    signalR = _FakeSignalRService();
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        signalRServiceProvider.overrideWithValue(signalR),
        playGameHubBindingsProvider
            .overrideWithValue(_FakeHubBindings(signalR)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WdykRoundScreen()),
      ),
    );
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _roundJson(passes: passes, penalty: penalty),
    );
    await tester.pump();
  }

  Future<void> timeStarted(WidgetTester tester) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.timeStarted,
      HubEventPayload.mapFromArgs(['', 'g1']),
    );
    await tester.pump();
  }

  Future<void> timerSeconds(WidgetTester tester, num value) async {
    notifier().applySharedRoundEvent(
      PlayGameHubEvents.timerUpdatedSeconds,
      HubEventPayload.mapFromArgs([value, 'g1']),
    );
    await tester.pump();
  }

  Future<void> tick(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> roundEvent(
    WidgetTester tester,
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    notifier().applySharedRoundEvent(
      name,
      data ?? HubEventPayload.mapFromArgs([_localId, 'g1']),
    );
    await tester.pump();
  }

  group('TimerUpdatedSeconds truncates', () {
    const cases = <({num value, String label})>[
      (value: 10.999, label: '00:10'),
      (value: 10.5, label: '00:10'),
      (value: 10.1, label: '00:10'),
      (value: 10.0, label: '00:10'),
      (value: 3.99, label: '00:03'),
    ];

    for (final entry in cases) {
      testWidgets('${entry.value} displays ${entry.label}', (tester) async {
        await pumpRound(tester);
        await timeStarted(tester);
        await timerSeconds(tester, entry.value);
        expect(find.text(entry.label), findsOneWidget);
      });
    }
  });

  group('start signal', () {
    testWidgets('nothing runs before TimerUpdatedSeconds', (tester) async {
      await pumpRound(tester);
      expect(find.text('00:00'), findsOneWidget);

      await timeStarted(tester);
      expect(find.text('00:00'), findsOneWidget);

      await tick(tester, 3);
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('a GameUpdated snapshot alone does not start the countdown',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      notifier().applySessionEvent(PlayGameHubEvents.gameUpdated, {
        ..._roundJson(),
        'currentTimerValue': 25,
      });
      await tester.pump();

      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('TimerUpdatedSeconds starts it ticking', (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      expect(find.text('00:10'), findsOneWidget);

      await tick(tester, 1);
      expect(find.text('00:09'), findsOneWidget);

      await tick(tester, 2);
      expect(find.text('00:07'), findsOneWidget);
    });
  });

  // W-ACTION: the tap dispatches; only CorrectAnswer or Penalty resolves it.
  group('Answer is resolved by the server, not the tap', () {
    testWidgets('tapping an answer alone does not stop the countdown',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);
      expect(find.text('00:07'), findsOneWidget);

      await tester.tap(find.text('a1'));
      await tester.pump();

      await tick(tester, 4);
      expect(find.text('00:03'), findsOneWidget,
          reason: 'still counting until the server resolves the answer');
    });

    testWidgets('CorrectAnswer freezes at the current value', (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);
      await tester.tap(find.text('a1'));
      await tester.pump();

      await roundEvent(tester, PlayGameHubEvents.correctAnswer);

      // Frozen immediately, and still frozen inside the reset window.
      expect(find.text('00:07'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
      // UPDATED: past CountdownTimerText.freezeResetDelay the countdown is
      // disposed and the display clears — the behaviour this task adds.
      await tick(tester, 4);
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('Penalty freezes at the current value', (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);
      await tester.tap(find.text('a1'));
      await tester.pump();

      await roundEvent(tester, PlayGameHubEvents.penalty,
          {'playerId': _localId, 'type': 2});

      expect(find.text('00:07'), findsOneWidget);
      // UPDATED: cleared after the 500ms post-freeze reset.
      await tick(tester, 4);
      expect(find.text('00:00'), findsOneWidget);
    });
  });
  // W-ACTION: the tap dispatches; only PlayerPassed resolves it.
  group('Pass is resolved by the server, not the tap', () {
    testWidgets('tapping Pass alone does not stop the countdown',
        (tester) async {
      await pumpRound(tester, passes: 1, penalty: 2);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 6);
      expect(find.text('00:04'), findsOneWidget);

      await tester.tap(find.text('Pass'));
      await tester.pump();

      expect(
        signalR.invocations.where((i) => i.method == PlayGameHubEvents.pass),
        hasLength(1),
      );
      await tick(tester, 3);
      expect(find.text('00:01'), findsOneWidget,
          reason: 'still counting until PlayerPassed arrives');
    });

    testWidgets('PlayerPassed freezes at the current value', (tester) async {
      await pumpRound(tester, passes: 1, penalty: 2);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 6);
      await tester.tap(find.text('Pass'));
      await tester.pump();

      await roundEvent(tester, PlayGameHubEvents.playerPassed);

      expect(find.text('00:04'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
      // UPDATED: cleared after the 500ms post-freeze reset.
      await tick(tester, 3);
      expect(find.text('00:00'), findsOneWidget);
    });
  });

  group('timeout', () {
    testWidgets('the countdown reaches and stays at 00:00', (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 3);
      expect(find.text('00:03'), findsOneWidget);

      await tick(tester, 3);
      expect(find.text('00:00'), findsOneWidget);

      await tick(tester, 3);
      expect(find.text('00:00'), findsOneWidget);
    });
  });

  group('server authority is preserved', () {
    // TimerUpdatedSeconds is applied immediately and never schedules the
    // 500ms clear that a terminal freeze does.
    testWidgets('a value of 3 mid-countdown takes effect at once and '
        'continues', (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 2);
      expect(find.text('00:08'), findsOneWidget);

      await timerSeconds(tester, 3);
      expect(find.text('00:03'), findsOneWidget);

      await tick(tester, 1);
      expect(find.text('00:02'), findsOneWidget);
    });

    testWidgets('a value of zero shows 00:00 immediately, not after 500ms',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);
      expect(find.text('00:07'), findsOneWidget);

      await timerSeconds(tester, 0);

      expect(find.text('00:00'), findsOneWidget,
          reason: 'zeroed on arrival — the delayed clear is terminal-only');
    });

    testWidgets('a TimerUpdatedSeconds inside the terminal window supersedes '
        'the pending clear', (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);

      await roundEvent(tester, PlayGameHubEvents.correctAnswer);
      expect(find.text('00:07'), findsOneWidget, reason: 'frozen');

      await timerSeconds(tester, 9);
      expect(find.text('00:09'), findsOneWidget);

      // Past the moment the cancelled clear would have fired.
      await tick(tester, 1);
      expect(find.text('00:08'), findsOneWidget,
          reason: 'a stale clear must not zero the new server countdown');
    });

    testWidgets('a later TimerUpdatedSeconds restarts from the new value',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 4);
      expect(find.text('00:06'), findsOneWidget);

      await timerSeconds(tester, 30);
      expect(find.text('00:30'), findsOneWidget);

      await tick(tester, 1);
      expect(find.text('00:29'), findsOneWidget);
    });
  });

  // W-ACTION: PlayerAnswered announces an answer; it no longer resolves one,
  // so it must not touch the timer. CorrectAnswer / Penalty do that.
  group('the opponent answering freezes this client', () {
    Future<void> playerAnswered(WidgetTester tester) => roundEvent(
          tester,
          PlayGameHubEvents.playerAnswered,
          {'playerId': _opponentId, 'answerText': 'x', 'answerTextEn': 'x'},
        );

    testWidgets('PlayerAnswered alone no longer stops the countdown',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 2);
      expect(find.text('00:08'), findsOneWidget);

      await playerAnswered(tester);

      await tick(tester, 5);
      expect(find.text('00:03'), findsOneWidget,
          reason: 'PlayerAnswered is not an authoritative resolution');
    });

    testWidgets('the opponent CorrectAnswer freezes this client',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 2);
      await playerAnswered(tester);

      await roundEvent(tester, PlayGameHubEvents.correctAnswer);

      expect(find.text('00:08'), findsOneWidget);
      // UPDATED: it does not continue — and past the 500ms post-freeze reset
      // the display is cleared rather than left frozen at 00:08.
      await tick(tester, 5);
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('the opponent Penalty freezes this client', (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 2);

      await roundEvent(tester, PlayGameHubEvents.penalty,
          {'playerId': _opponentId, 'type': 2});

      expect(find.text('00:08'), findsOneWidget);
      await tick(tester, 5);
      // UPDATED: past the 500ms post-freeze reset the display is cleared.
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('a later TimerUpdatedSeconds still restarts it',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 2);
      await roundEvent(tester, PlayGameHubEvents.correctAnswer);

      await timerSeconds(tester, 20);
      expect(find.text('00:20'), findsOneWidget);
      await tick(tester, 1);
      expect(find.text('00:19'), findsOneWidget);
    });
  });

  group('stopping never zeroes the server value', () {
    Future<void> expectFrozenAtTen(WidgetTester tester) async {
      final game = container.read(gameControllerProvider).game;
      expect(game?.currentTimerValue, 10);
      expect(game?.isTimerStarted, isFalse);
    }

    testWidgets('CorrectAnswer leaves currentTimerValue untouched',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);

      await roundEvent(tester, PlayGameHubEvents.correctAnswer);

      await expectFrozenAtTen(tester);
    });

    testWidgets('Penalty leaves currentTimerValue untouched', (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);

      await roundEvent(tester, PlayGameHubEvents.penalty,
          {'playerId': _localId, 'type': 2});

      await expectFrozenAtTen(tester);
    });

    testWidgets('PlayerPassed leaves currentTimerValue untouched',
        (tester) async {
      await pumpRound(tester, passes: 1, penalty: 2);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 6);

      await roundEvent(tester, PlayGameHubEvents.playerPassed);

      await expectFrozenAtTen(tester);
    });

    testWidgets('PlayerAnswered leaves the timer running', (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 2);

      await roundEvent(tester, PlayGameHubEvents.playerAnswered,
          {'playerId': _opponentId, 'answerText': 'x', 'answerTextEn': 'x'});

      final game = container.read(gameControllerProvider).game;
      expect(game?.currentTimerValue, 10);
      expect(game?.isTimerStarted, isTrue);
    });
  });

  group('the next turn starts from the server value', () {
    testWidgets('a fresh TimerUpdatedSeconds after a freeze restarts it',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);
      await tester.tap(find.text('a1'));
      await tester.pump();
      await roundEvent(tester, PlayGameHubEvents.correctAnswer);
      expect(find.text('00:07'), findsOneWidget);

      notifier().applySharedRoundEvent(
        PlayGameHubEvents.changeTurn,
        {'playerId': _localId},
      );
      await tester.pump();
      await timeStarted(tester);
      await timerSeconds(tester, 30);

      expect(find.text('00:30'), findsOneWidget);
      await tick(tester, 1);
      expect(find.text('00:29'), findsOneWidget);
    });
  });

  // PlayerPassed arrives positionally as [playerId, gameId]. The passing
  // device already froze in pass(); this covers the receiving one.
  group('the opponent passing freezes this client', () {
    Future<void> playerPassed(WidgetTester tester) async {
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.playerPassed,
        HubEventPayload.mapFromArgs([_opponentId, 'g1']),
      );
      await tester.pump();
    }

    testWidgets('PlayerPassed stops and freezes the countdown',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 2);
      expect(find.text('00:08'), findsOneWidget);

      await playerPassed(tester);

      expect(find.text('00:08'), findsOneWidget);
      expect(find.text('00:00'), findsNothing);
    });

    testWidgets('the countdown does not continue after PlayerPassed',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 2);
      await playerPassed(tester);

      await tick(tester, 5);
      // UPDATED: past the 500ms post-freeze reset the display is cleared.
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('PlayerPassed leaves currentTimerValue untouched',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 2);
      await playerPassed(tester);

      final game = container.read(gameControllerProvider).game;
      expect(game?.currentTimerValue, 10);
      expect(game?.isTimerStarted, isFalse);
    });

    testWidgets('a later TimerUpdatedSeconds still restarts it',
        (tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 2);
      await playerPassed(tester);

      await timerSeconds(tester, 20);
      expect(find.text('00:20'), findsOneWidget);
      await tick(tester, 1);
      expect(find.text('00:19'), findsOneWidget);
    });
  });

  // A resolution that also carries a game-shaped payload.
  //
  // `looksLikeCreatedGame` is satisfied by any one of id / players /
  // currentQuestion / currentTimerValue / currentTurn / status / answers, and
  // `_gameFromData` merges onto the current game — which inherits `status`
  // when the payload omits it. So a CorrectAnswer carrying only a roster
  // update used to route as "still in progress", take applySharedRoundEvent's
  // early return, and never reach _eventStopsTimer. The routed snapshot then
  // inherited isTimerStarted: true and the countdown ran on to 00:00 with the
  // question already resolved.
  group('a resolution carrying a game snapshot still freezes', () {
    GameSessionState current() => container.read(gameControllerProvider);

    /// The shape the server sends when it syncs scores alongside the
    /// resolution: game-shaped, no explicit status, no isTimerStarted.
    Map<String, dynamic> gameShaped(String playerId) => {
          'id': 'g1',
          'players': [
            {'id': _localId, 'playerName': 'me', 'score': 1},
            {'id': _opponentId, 'playerName': 'them', 'score': 2},
          ],
          'playerId': playerId,
        };

    Future<void> runningTimer(WidgetTester tester) async {
      await pumpRound(tester);
      await timeStarted(tester);
      await timerSeconds(tester, 10);
      await tick(tester, 3);
      expect(find.text('00:07'), findsOneWidget, reason: 'sanity');
      expect(current().game?.isTimerStarted, isTrue, reason: 'sanity');
    }

    testWidgets('CorrectAnswer with a game-shaped payload freezes the timer',
        (tester) async {
      await runningTimer(tester);

      await roundEvent(
        tester,
        PlayGameHubEvents.correctAnswer,
        gameShaped(_opponentId),
      );

      expect(current().game?.isTimerStarted, isFalse,
          reason: 'the resolution must reach the timer even when its payload '
              'also routes');
      expect(find.text('00:07'), findsOneWidget, reason: 'frozen in place');
      await tick(tester, 3);
      expect(find.text('00:00'), findsOneWidget,
          reason: 'then cleared by the existing 500ms reset');
    });

    testWidgets('Penalty(type 1) with a game-shaped payload freezes the timer',
        (tester) async {
      await runningTimer(tester);

      await roundEvent(tester, PlayGameHubEvents.penalty, {
        ...gameShaped(_opponentId),
        'type': 1,
      });

      expect(current().game?.isTimerStarted, isFalse);
      expect(find.text('00:07'), findsOneWidget);
      await tick(tester, 3);
      expect(find.text('00:00'), findsOneWidget);
    });

    testWidgets('a lean CorrectAnswer payload still freezes, as before',
        (tester) async {
      await runningTimer(tester);

      await roundEvent(tester, PlayGameHubEvents.correctAnswer);

      expect(current().game?.isTimerStarted, isFalse);
      expect(find.text('00:07'), findsOneWidget);
    });

    // Split into two tests rather than compared inside one: two pumpRound
    // calls in a single test leave the first tree's timers pending. Each
    // side is asserted against the same constant, which proves the same
    // thing — the freeze does not depend on who resolved.
    for (final entry in {'opponent': _opponentId, 'self': _localId}.entries) {
      testWidgets('a ${entry.key} resolution freezes the timer the same way',
          (tester) async {
        await runningTimer(tester);

        await roundEvent(
          tester,
          PlayGameHubEvents.correctAnswer,
          gameShaped(entry.value),
        );

        expect(current().game?.isTimerStarted, isFalse,
            reason: 'the freeze is not identity-dependent — '
                '_eventStopsTimer never inspects playerId');
        expect(find.text('00:07'), findsOneWidget);
        await tick(tester, 3);
        expect(find.text('00:00'), findsOneWidget);
      });
    }

    testWidgets('the routed payload is still applied — routing is unchanged',
        (tester) async {
      await runningTimer(tester);

      await roundEvent(
        tester,
        PlayGameHubEvents.correctAnswer,
        gameShaped(_opponentId),
      );

      expect(current().game?.id, 'g1');
      expect(current().opponent?.id, _opponentId,
          reason: 'the roster the payload carried was still merged');
      expect(current().phase, GamePhase.wdyk,
          reason: 'an in-progress status still routes to its round');
    });

    testWidgets('a genuinely routable status change still routes as before',
        (tester) async {
      await runningTimer(tester);

      // status 4 = ended: this must still route to the end-of-game path
      // rather than being swallowed by the freeze.
      await roundEvent(tester, PlayGameHubEvents.correctAnswer, {
        ...gameShaped(_opponentId),
        'status': 4,
      });

      expect(current().result, isNotNull,
          reason: 'routing by status is untouched by this fix');
    });

    testWidgets('a later TimerUpdatedSeconds still restarts immediately',
        (tester) async {
      await runningTimer(tester);
      await roundEvent(
        tester,
        PlayGameHubEvents.correctAnswer,
        gameShaped(_opponentId),
      );
      expect(find.text('00:07'), findsOneWidget);

      await timerSeconds(tester, 9);

      expect(find.text('00:09'), findsOneWidget,
          reason: 'server-authoritative restart, unchanged');
      await tick(tester, 1);
      expect(find.text('00:08'), findsOneWidget,
          reason: 'and the pending 500ms clear did not zero it');
    });

    testWidgets('TimerUpdatedSeconds(0) after a resolution shows 00:00 at once',
        (tester) async {
      await runningTimer(tester);
      await roundEvent(
        tester,
        PlayGameHubEvents.correctAnswer,
        gameShaped(_opponentId),
      );

      await timerSeconds(tester, 0);

      expect(find.text('00:00'), findsOneWidget);
    });
  });

  // The real per-question cycle, reproduced from a device log.
  //
  // The server sends NextQuestion -> ChangeTurn -> TimerUpdatedSeconds for
  // every question after the first. There is no TimeStarted in it — that
  // event belongs to the round's opening Start Timer dialog — so the flag
  // TimeStarted used to be the only writer of was never raised, while
  // TimerUpdatedSeconds started the display anyway. _applyNextQuestion had
  // just written the flag false, so the resolution's own false landed on a
  // false, RoundScoreColumn saw no true->false edge, and the countdown ran
  // on to 00:00 under a question the server had already resolved.
  //
  // Every test here therefore omits `timeStarted` deliberately. The groups
  // above keep it, so both entries into a countdown stay covered.
  group('the countdown freezes with no TimeStarted in the cycle', () {
    GameSessionState current() => container.read(gameControllerProvider);

    Future<void> nextQuestion(WidgetTester tester, int id) async {
      notifier().applySharedRoundEvent(PlayGameHubEvents.nextQuestion, {
        'id': id,
        'text': 'q$id',
        'textEn': 'q$id',
        'questionNumber': id,
        'roundTotalQuestionsCount': 5,
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
          {'id': 11, 'text': 'a2', 'textEn': 'a2'},
        ],
      });
      await tester.pump();
    }

    Future<void> changeTurn(WidgetTester tester, String playerId) async {
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.changeTurn,
        HubEventPayload.mapFromArgs([playerId, 'g1']),
      );
      await tester.pump();
    }

    /// The cycle exactly as logged, up to the point a resolution arrives:
    /// question, turn, countdown — and nothing else.
    Future<void> serverCycle(WidgetTester tester, {int seconds = 10}) async {
      await pumpRound(tester);
      await nextQuestion(tester, 2);
      await changeTurn(tester, _localId);
      await timerSeconds(tester, seconds);
    }

    /// CorrectAnswer as the hub actually delivers it: three positional args,
    /// `[answerText, answerTextEn, playerId]`, mapped to arg0/arg1/arg2.
    /// This shape does not satisfy `looksLikeCreatedGame`, which is why the
    /// earlier routing fix never ran on it.
    Map<String, dynamic>? correctAnswerArgs(String playerId) =>
        HubEventPayload.mapFromArgs(['a1', 'a1', playerId]);

    testWidgets('TimerUpdatedSeconds reports the countdown as started',
        (tester) async {
      await serverCycle(tester);

      expect(current().game?.currentTimerValue, 10);
      expect(current().game?.isTimerStarted, isTrue,
          reason: 'a countdown with time on it is the timer running — this '
              'event now reports the flag as well as the value');
      expect(find.text('00:10'), findsOneWidget);
    });

    testWidgets('CorrectAnswer freezes it and then clears it', (tester) async {
      await serverCycle(tester);
      await tick(tester, 3);
      expect(find.text('00:07'), findsOneWidget, reason: 'sanity: running');

      await roundEvent(
        tester,
        PlayGameHubEvents.correctAnswer,
        correctAnswerArgs(_opponentId),
      );

      expect(current().game?.isTimerStarted, isFalse);
      expect(find.text('00:07'), findsOneWidget, reason: 'frozen in place');

      await tick(tester, 1);
      expect(find.text('00:00'), findsOneWidget,
          reason: 'cleared by the existing 500ms reset');
      expect(find.text('00:06'), findsNothing,
          reason: 'the bug: it kept ticking down instead of freezing');
    });

    testWidgets('Penalty(type 2) freezes it the same way', (tester) async {
      await serverCycle(tester);
      await tick(tester, 3);

      await roundEvent(tester, PlayGameHubEvents.penalty, {
        ...?HubEventPayload.mapFromArgs([_opponentId, 'g1']),
        'type': 2,
      });

      expect(current().game?.isTimerStarted, isFalse);
      await tick(tester, 1);
      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('00:06'), findsNothing);
    });

    testWidgets('PlayerPassed freezes it the same way', (tester) async {
      await serverCycle(tester);
      await tick(tester, 3);

      await roundEvent(
        tester,
        PlayGameHubEvents.playerPassed,
        HubEventPayload.mapFromArgs([_opponentId, 'g1']),
      );

      expect(current().game?.isTimerStarted, isFalse);
      await tick(tester, 1);
      expect(find.text('00:00'), findsOneWidget);
    });

    // Split rather than compared inside one test: two pumpRound calls in a
    // single test leave the first tree's timers pending. Both sides assert
    // against the same constants, which is the same proof.
    for (final entry in {'opponent': _opponentId, 'self': _localId}.entries) {
      testWidgets('a ${entry.key} CorrectAnswer freezes it identically',
          (tester) async {
        await serverCycle(tester);
        await tick(tester, 3);

        await roundEvent(
          tester,
          PlayGameHubEvents.correctAnswer,
          correctAnswerArgs(entry.value),
        );

        expect(current().game?.isTimerStarted, isFalse,
            reason: 'no identity-specific behaviour — _eventStopsTimer never '
                'inspects playerId');
        await tick(tester, 1);
        expect(find.text('00:00'), findsOneWidget);
        expect(find.text('00:06'), findsNothing);
      });
    }

    testWidgets('PlayerAnswered still resolves nothing', (tester) async {
      await serverCycle(tester);
      await tick(tester, 3);

      await roundEvent(
        tester,
        PlayGameHubEvents.playerAnswered,
        HubEventPayload.mapFromArgs(['a1', 'a1', _opponentId]),
      );

      expect(current().game?.isTimerStarted, isTrue,
          reason: 'it announces an answer, it does not resolve one — '
              'unchanged');
      await tick(tester, 1);
      expect(find.text('00:06'), findsOneWidget, reason: 'still counting');
    });

    testWidgets('TimerUpdatedSeconds(0) zeroes it without raising the flag',
        (tester) async {
      await pumpRound(tester);
      await nextQuestion(tester, 2);
      await changeTurn(tester, _localId);

      await timerSeconds(tester, 0);

      expect(current().game?.isTimerStarted, isFalse,
          reason: 'NextQuestion wrote false and a non-positive value leaves '
              'it alone — nothing here forces it true');
      expect(find.text('00:00'), findsOneWidget);
      await tick(tester, 1);
      expect(find.text('00:00'), findsOneWidget,
          reason: 'immediate, with no delayed reset behind it');
    });

    testWidgets('a later TimerUpdatedSeconds restarts and cancels the clear',
        (tester) async {
      await serverCycle(tester);
      await tick(tester, 3);
      await roundEvent(
        tester,
        PlayGameHubEvents.correctAnswer,
        correctAnswerArgs(_opponentId),
      );
      expect(find.text('00:07'), findsOneWidget);

      await timerSeconds(tester, 9);

      expect(current().game?.isTimerStarted, isTrue);
      expect(find.text('00:09'), findsOneWidget);
      await tick(tester, 1);
      expect(find.text('00:08'), findsOneWidget,
          reason: 'the pending 500ms clear was superseded, not applied');
    });

    testWidgets('the next question can freeze all over again', (tester) async {
      await serverCycle(tester);
      await tick(tester, 3);
      await roundEvent(
        tester,
        PlayGameHubEvents.correctAnswer,
        correctAnswerArgs(_opponentId),
      );
      await tick(tester, 1);

      await nextQuestion(tester, 3);
      await changeTurn(tester, _opponentId);
      await timerSeconds(tester, 10);
      expect(find.text('00:10'), findsOneWidget);
      await tick(tester, 4);
      expect(find.text('00:06'), findsOneWidget);

      await roundEvent(
        tester,
        PlayGameHubEvents.correctAnswer,
        correctAnswerArgs(_localId),
      );
      await tick(tester, 1);
      expect(find.text('00:00'), findsOneWidget,
          reason: 'the cycle repeats cleanly — no latched flag');
    });

    testWidgets('GameUpdated is still not a start signal', (tester) async {
      await pumpRound(tester);
      await nextQuestion(tester, 2);

      notifier().applySessionEvent(PlayGameHubEvents.gameUpdated, {
        ..._roundJson(),
        'currentTimerValue': 25,
        'isTimerStarted': true,
      });
      await tester.pump();

      expect(find.text('00:00'), findsOneWidget,
          reason: 'the lastEventName gate is untouched: only '
              'TimerUpdatedSeconds starts the display');
      await tick(tester, 2);
      expect(find.text('00:00'), findsOneWidget);

      await timerSeconds(tester, 10);
      expect(find.text('00:10'), findsOneWidget);
    });
  });
}
