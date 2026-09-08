import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:play_game/presentation/widgets/rounds/round_player_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ALLOW_ALL is a valid WDYK turn state meaning both players may act. These
// drive the real screen, because the turn value reaches the UI through
// GameSessionState rather than through GameController alone.

const _localId = '47';
const _opponentId = '211403';

class _FakeSignalRService extends SignalRService {
  final invocations = <({String method, List<Object?>? args})>[];

  // Drives invoke()s return the way a real disconnected hub would.
  bool connected = true;

  @override
  Future<bool> invoke(String methodName, {List<Object?>? args}) async {
    if (!connected) {
      return false;
    }
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

Map<String, dynamic> _roundJson({
  required String currentTurn,
  int passes = 0,
  int penalty = 0,
}) =>
    {
      'id': 'g1',
      'status': 3,
      'type': 1,
      'groupId': 'grp',
      'currentTurn': currentTurn,
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

  Future<void> pumpRound(
    WidgetTester tester, {
    required String currentTurn,
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
    container.read(gameControllerProvider.notifier).applySessionEvent(
          PlayGameHubEvents.gameStarted,
          _roundJson(
            currentTurn: currentTurn,
            passes: passes,
            penalty: penalty,
          ),
        );
    await tester.pump();
    // Answering opens only once a countdown is running (shared rule).
    container.read(gameControllerProvider.notifier).applySharedRoundEvent(
          PlayGameHubEvents.timerUpdatedSeconds,
          HubEventPayload.mapFromArgs([30, 'g1']),
        );
    await tester.pump();
  }

  List<bool> avatarTurnFlags(WidgetTester tester) => tester
      .widgetList<RoundPlayerAvatar>(find.byType(RoundPlayerAvatar))
      .map((a) => a.isTurn)
      .toList();

  double passOpacity(WidgetTester tester) => tester
      .widget<Opacity>(
        find
            .ancestor(of: find.text('Pass'), matching: find.byType(Opacity))
            .first,
      )
      .opacity;

  group('ALLOW_ALL', () {
    testWidgets('answer chips are offered to the local player',
        (tester) async {
      await pumpRound(tester, currentTurn: CreatedGame.allowAllTurn);
      expect(find.text('a1'), findsOneWidget);
      expect(find.text('a2'), findsOneWidget);
    });

    testWidgets('an answer can be submitted', (tester) async {
      await pumpRound(tester, currentTurn: CreatedGame.allowAllTurn);
      await tester.tap(find.text('a1'));
      await tester.pump();
      expect(
        signalR.invocations
            .where((i) => i.method == PlayGameHubEvents.submitAnswer),
        hasLength(1),
      );
    });

    testWidgets('both avatars are shown as active', (tester) async {
      await pumpRound(tester, currentTurn: CreatedGame.allowAllTurn);
      expect(avatarTurnFlags(tester), [true, true]);
    });

    testWidgets('pass stays disabled without passes or penalties',
        (tester) async {
      await pumpRound(tester, currentTurn: CreatedGame.allowAllTurn);
      expect(passOpacity(tester), 0.4);
    });

    testWidgets('pass stays disabled with fewer than two penalties',
        (tester) async {
      await pumpRound(
        tester,
        currentTurn: CreatedGame.allowAllTurn,
        passes: 1,
        penalty: 1,
      );
      expect(passOpacity(tester), 0.4);
    });

    testWidgets('pass stays disabled with no remaining passes',
        (tester) async {
      await pumpRound(
        tester,
        currentTurn: CreatedGame.allowAllTurn,
        passes: 0,
        penalty: 2,
      );
      expect(passOpacity(tester), 0.4);
    });

    testWidgets('pass is enabled once passes and penalties allow it',
        (tester) async {
      await pumpRound(
        tester,
        currentTurn: CreatedGame.allowAllTurn,
        passes: 1,
        penalty: 2,
      );
      expect(passOpacity(tester), 1);

      await tester.tap(find.text('Pass'));
      await tester.pump();
      expect(
        signalR.invocations.where((i) => i.method == PlayGameHubEvents.pass),
        hasLength(1),
      );
    });
  });

  group('a named turn is unchanged', () {
    testWidgets('the local player keeps the turn alone', (tester) async {
      await pumpRound(tester, currentTurn: _localId, passes: 1, penalty: 2);
      expect(find.text('a1'), findsOneWidget);
      expect(avatarTurnFlags(tester), [false, true]);
      expect(passOpacity(tester), 1);
    });

    testWidgets('the opponent keeps the turn alone', (tester) async {
      await pumpRound(tester, currentTurn: _opponentId, passes: 1, penalty: 2);
      expect(find.text('a1'), findsNothing);
      expect(avatarTurnFlags(tester), [true, false]);
      expect(passOpacity(tester), 0.4);
    });

    testWidgets('an unknown turn value lets neither player act',
        (tester) async {
      await pumpRound(tester, currentTurn: 'ALLOW_NONE', passes: 1, penalty: 2);
      expect(find.text('a1'), findsNothing);
      expect(avatarTurnFlags(tester), [false, false]);
      expect(passOpacity(tester), 0.4);
    });
  });

  // The server owns the pass budget. The client must not send a second Pass
  // in the window between invoking it and GameUpdated reporting passes: 0.
  group('duplicate pass protection', () {
    List<({String method, List<Object?>? args})> passes() => signalR.invocations
        .where((i) => i.method == PlayGameHubEvents.pass)
        .toList();

    Future<void> refreshRoster(WidgetTester tester, {required int passes}) async {
      container.read(gameControllerProvider.notifier).applySessionEvent(
            PlayGameHubEvents.gameUpdated,
            _roundJson(
              currentTurn: CreatedGame.allowAllTurn,
              passes: passes,
              penalty: 2,
            ),
          );
      await tester.pump();
    }

    testWidgets('the first tap invokes Pass once', (tester) async {
      await pumpRound(
        tester,
        currentTurn: CreatedGame.allowAllTurn,
        passes: 1,
        penalty: 2,
      );
      expect(passOpacity(tester), 1);

      await tester.tap(find.text('Pass'));
      await tester.pump();

      expect(passes(), hasLength(1));
      expect(passes().single.args, ['g1']);
    });

    testWidgets('a second tap before GameUpdated invokes nothing',
        (tester) async {
      await pumpRound(
        tester,
        currentTurn: CreatedGame.allowAllTurn,
        passes: 1,
        penalty: 2,
      );
      await tester.tap(find.text('Pass'));
      await tester.pump();
      await tester.tap(find.text('Pass'), warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.text('Pass'), warnIfMissed: false);
      await tester.pump();

      expect(passes(), hasLength(1));
    });

    testWidgets('the button is disabled while the request is in flight',
        (tester) async {
      await pumpRound(
        tester,
        currentTurn: CreatedGame.allowAllTurn,
        passes: 1,
        penalty: 2,
      );
      await tester.tap(find.text('Pass'));
      await tester.pump();

      expect(passOpacity(tester), 0.4);
    });

    testWidgets('pass stays unavailable once the server confirms passes 0',
        (tester) async {
      await pumpRound(
        tester,
        currentTurn: CreatedGame.allowAllTurn,
        passes: 1,
        penalty: 2,
      );
      await tester.tap(find.text('Pass'));
      await tester.pump();
      await refreshRoster(tester, passes: 0);

      expect(passOpacity(tester), 0.4);
      await tester.tap(find.text('Pass'), warnIfMissed: false);
      await tester.pump();
      expect(passes(), hasLength(1));
    });

    testWidgets('the local passes value is never decremented by the client',
        (tester) async {
      await pumpRound(
        tester,
        currentTurn: CreatedGame.allowAllTurn,
        passes: 1,
        penalty: 2,
      );
      await tester.tap(find.text('Pass'));
      await tester.pump();

      expect(container.read(gameControllerProvider).me?.passes, 1);
    });

    testWidgets('a refreshed budget makes pass available again',
        (tester) async {
      await pumpRound(
        tester,
        currentTurn: CreatedGame.allowAllTurn,
        passes: 1,
        penalty: 2,
      );
      await tester.tap(find.text('Pass'));
      await tester.pump();
      await refreshRoster(tester, passes: 0);
      expect(passOpacity(tester), 0.4);

      await refreshRoster(tester, passes: 1);

      expect(passOpacity(tester), 1);
      await tester.tap(find.text('Pass'));
      await tester.pump();
      expect(passes(), hasLength(2));
    });
  });

  // W-ACTION: a Pass that never dispatched must not leave the button dead.
  group('a failed dispatch releases the pass guard', () {
    Future<void> pumpPassable(WidgetTester tester) => pumpRound(
          tester,
          currentTurn: _localId,
          passes: 1,
          penalty: 2,
        );

    List<({String method, List<Object?>? args})> passes() => signalR.invocations
        .where((i) => i.method == PlayGameHubEvents.pass)
        .toList();

    testWidgets('the button is usable again after a failed pass',
        (tester) async {
      await pumpPassable(tester);
      expect(passOpacity(tester), 1);

      signalR.connected = false;
      await tester.tap(find.text('Pass'));
      await tester.pump();

      expect(passes(), isEmpty, reason: 'nothing dispatched');
      expect(passOpacity(tester), 1, reason: 'guard released, button live');

      signalR.connected = true;
      await tester.tap(find.text('Pass'));
      await tester.pump();

      expect(passes(), hasLength(1), reason: 'the retry went out');
    });

    testWidgets('a failed pass leaves a running timer running', (tester) async {
      await pumpPassable(tester);

      // A real countdown first: TimeStarted arms the timer and
      // TimerUpdatedSeconds is the only thing that sets it running.
      final controller = container.read(gameControllerProvider.notifier);
      controller.applySharedRoundEvent(
        PlayGameHubEvents.timeStarted,
        HubEventPayload.mapFromArgs(['', 'g1']),
      );
      await tester.pump();
      controller.applySharedRoundEvent(
        PlayGameHubEvents.timerUpdatedSeconds,
        HubEventPayload.mapFromArgs([10, 'g1']),
      );
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('00:07'), findsOneWidget, reason: 'the timer is live');

      signalR.connected = false;
      await tester.tap(find.text('Pass'));
      await tester.pump();
      expect(passes(), isEmpty, reason: 'nothing dispatched');

      final game = container.read(gameControllerProvider).game;
      expect(game?.isTimerStarted, isTrue,
          reason: 'a dispatch that never left must not stop the timer');
      expect(game?.currentTimerValue, 10,
          reason: 'and must not rewrite the seconds the server gave');
      expect(find.text('00:07'), findsOneWidget,
          reason: 'no restart — the countdown carries on where it was');

      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('00:03'), findsOneWidget,
          reason: 'the countdown is still advancing');
    });

    testWidgets('a successful pass keeps the guard closed', (tester) async {
      await pumpPassable(tester);

      await tester.tap(find.text('Pass'));
      await tester.pump();
      expect(passOpacity(tester), 0.4, reason: 'guard held after dispatch');

      await tester.tap(find.text('Pass'), warnIfMissed: false);
      await tester.pump();

      expect(passes(), hasLength(1), reason: 'no duplicate dispatch');
    });
  });
}
