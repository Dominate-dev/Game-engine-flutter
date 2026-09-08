import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// WDYK overlays — ownership, T30 durations, sequencing and app-background
// behaviour. The reference is docs/tasks/what-do-you-know-round-workflow.md.
//
// The handlers take the show-dialog callback as a parameter, so these drive
// them directly through a recorder that keeps each dialog "open" until the
// test dismisses it — which is what makes stacking observable.

const _localId = '47';
const _opponentId = '211403';

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

/// Stands in for [BaseState.showAppDialog]: a dialog stays open until the test
/// completes it, so two overlays open at once would be visible here.
class _DialogRecorder {
  final shown = <Widget>[];
  final _open = <Completer<void>>[];

  Future<void> show({required Widget child, bool barrierDismissible = true}) {
    shown.add(child);
    final completer = Completer<void>();
    _open.add(completer);
    return completer.future;
  }

  int get openCount => _open.where((c) => !c.isCompleted).length;

  T last<T>() => shown.last as T;

  void dismissAll() {
    for (final completer in _open) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }
}

Map<String, dynamic> _gameJson({required int type}) => {
      'id': 'g1',
      'status': 3,
      'type': type,
      'groupId': 'grp',
      'currentTurn': _localId,
      'players': [
        {'id': _localId, 'playerName': 'me', 'passes': 1, 'penalty': 2},
        {'id': _opponentId, 'playerName': 'them', 'passes': 1, 'penalty': 0},
      ],
    };

void main() {
  late ProviderContainer container;
  late _DialogRecorder recorder;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  final strings = PlayGameStrings.forLanguage(AppLanguage.english);

  Future<void> enterRound(WidgetTester tester, {int type = 1}) async {
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
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(gameControllerProvider, (_, __) {});
    addTearDown(sub.close);
    recorder = _DialogRecorder();

    // A bare tree: the handlers are driven directly, but a pumped widget gives
    // the test a binding and a clock.
    await tester.pumpWidget(const SizedBox());
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _gameJson(type: type),
    );
    await tester.pump();
  }

  Future<void> setLifecycle(
    WidgetTester tester,
    AppLifecycleState state,
  ) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/lifecycle',
      const StringCodec().encodeMessage(state.toString()),
      (_) {},
    );
    await tester.pump();
  }

  // CorrectAnswer is (text, textEn, playerId, gameId) per W-CONTRACT, and
  // HubEventPayload.mapFromArgs keeps arg0..arg2.
  Map<String, dynamic> correctAnswerArgs(String playerId) => {
        'arg0': 'answer',
        'arg1': 'answer en',
        'arg2': playerId,
      };

  // PlayerPassed is [playerId, gameId] — observed at runtime.
  Map<String, dynamic> passedArgs(String playerId) => {
        'arg0': playerId,
        'arg1': 'g1',
      };

  group('CorrectAnswer belongs to the player who answered', () {
    testWidgets('my correct answer shows the overlay on my device',
        (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<Widget>(), isA<RoundLottieDialog>());
      expect(
        (recorder.last<RoundLottieDialog>()).text,
        strings.correctAnswer,
      );
    });

    testWidgets('the opponent answering correctly shows me nothing',
        (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs(_opponentId), recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty,
          reason: 'the celebration belongs to the other device');
    });

    testWidgets('a named playerId field is honoured too', (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(
        {'arg0': 'answer', 'playerId': _localId},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.shown, hasLength(1));
    });

    testWidgets('an id naming neither player shows nothing', (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs('999'), recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty, reason: 'no side may be guessed');
    });

    testWidgets('a null payload shows nothing', (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(null, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('a payload carrying no player at all shows nothing',
        (tester) async {
      await enterRound(tester);

      // Only the answer texts — the position the player would occupy is absent.
      notifier().onCorrectAnswer(
        {'arg0': 'answer', 'arg1': 'answer en'},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('an empty or whitespace-only playerId shows nothing',
        (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs(''), recorder.show);
      notifier().onCorrectAnswer(correctAnswerArgs('   '), recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('ownership is decided by identity, never by position',
        (tester) async {
      await enterRound(tester);

      // The opponent's id sitting in the payload does not become mine just
      // because no other player is named.
      notifier().onCorrectAnswer(
        {'arg0': 'answer', 'playerId': _opponentId},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('other round types keep their own overlay and timing',
        (tester) async {
      // Every round now routes CorrectAnswer to its own handler — Auction
      // (A-4), Bell (B-3), Comeback/Breaker (C-4) — so this checks that
      // WDYK's ownership rule does not reach them. Breaker shows the answer
      // bar with the answerer's name; the 2000ms opponent timing is
      // unchanged.
      await enterRound(tester, type: 5); // breaker

      notifier().onCorrectAnswer(correctAnswerArgs(_opponentId), recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<PlayerAnsweredDialog>().timer, 2000);
      expect(recorder.last<PlayerAnsweredDialog>().playerName, isNotEmpty);
    });
  });

  group('PlayerPassed belongs to the player who passed', () {
    testWidgets('the passer sees the skip overlay', (tester) async {
      await enterRound(tester);

      notifier().onPlayerPassed(passedArgs(_localId), recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<Widget>(), isA<RoundLottieDialog>());
      expect(recorder.last<RoundLottieDialog>().text, strings.skip);
    });

    testWidgets('the watcher sees the answer reveal reading Skip',
        (tester) async {
      await enterRound(tester);

      notifier().onPlayerPassed(passedArgs(_opponentId), recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<Widget>(), isA<PlayerAnsweredDialog>());
      expect(recorder.last<PlayerAnsweredDialog>().answer, strings.skip);
    });

    testWidgets('the two devices do not show the same overlay',
        (tester) async {
      await enterRound(tester);

      notifier().onPlayerPassed(passedArgs(_localId), recorder.show);
      await tester.pump();
      final mine = recorder.shown.single.runtimeType;

      recorder.dismissAll();
      await tester.pump();
      notifier().onPlayerPassed(passedArgs(_opponentId), recorder.show);
      await tester.pump();

      expect(recorder.shown.last.runtimeType, isNot(mine));
    });

    testWidgets('an id naming neither player shows nothing', (tester) async {
      await enterRound(tester);

      notifier().onPlayerPassed(passedArgs('999'), recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });
  });

  group('T30 overlay durations', () {
    testWidgets('turn overlay is 1500ms', (tester) async {
      await enterRound(tester);

      notifier().onChangeTurn({'arg0': _localId}, recorder.show);
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });

    testWidgets('correct overlay is 1500ms', (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });

    testWidgets('the opponent timeout overlay is 1500ms', (tester) async {
      await enterRound(tester);

      notifier().onPenalty(
        {'playerId': _opponentId, 'type': 1},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().timer, 1500);
      expect(recorder.last<RoundLottieDialog>().text, strings.timeout);
    });

    testWidgets('answer reveal is 1500ms', (tester) async {
      await enterRound(tester);

      notifier().onPlayerAnswered(
        {'answerText': 'blue', 'answerTextEn': 'blue'},
        recorder.show,
      );
      await tester.pump();

      expect(recorder.last<PlayerAnsweredDialog>().timer, 1500);
    });

    testWidgets('skip overlay is 1500ms', (tester) async {
      await enterRound(tester);

      notifier().onPlayerPassed(passedArgs(_localId), recorder.show);
      await tester.pump();

      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });

    testWidgets('my strike stays at 2000ms — timeout and wrong answer alike',
        (tester) async {
      await enterRound(tester);

      notifier().onPenalty({'playerId': _localId, 'type': 1}, recorder.show);
      await tester.pump();
      expect(recorder.last<RoundLottieDialog>().timer, 2000);
      expect(recorder.last<RoundLottieDialog>().text, strings.strike);

      recorder.dismissAll();
      await tester.pump();

      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      await tester.pump();
      expect(recorder.last<RoundLottieDialog>().timer, 2000);
    });
  });

  group('overlays are sequenced, never stacked', () {
    testWidgets('a second event waits for the first overlay to close',
        (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1), reason: 'no stacking');
      expect(recorder.openCount, 1);

      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(2), reason: 'the queue drained');
      expect(recorder.openCount, 1, reason: 'still one at a time');
    });

    testWidgets(
        'the next dialog is shown as soon as the turn overlay closes — not '
        'after its 1500ms post-close grace period',
        (tester) async {
      await enterRound(tester);

      notifier().onChangeTurn({'arg0': _localId}, recorder.show);
      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      await tester.pump();
      expect(recorder.shown, hasLength(1));

      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(2),
          reason: 'the post-close grace period no longer holds the queue');
    });

    testWidgets('three events arriving together still show one at a time',
        (tester) async {
      await enterRound(tester);

      notifier().onPlayerAnswered({'answerText': 'a'}, recorder.show);
      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      notifier().onPlayerPassed(passedArgs(_localId), recorder.show);
      await tester.pump();

      expect(recorder.openCount, 1);
      for (var i = 0; i < 3; i++) {
        recorder.dismissAll();
        await tester.pump();
      }
      expect(recorder.shown, hasLength(3));
    });
  });

  group('transient overlays are suppressed in the background', () {
    testWidgets('an event arriving while paused shows nothing',
        (tester) async {
      await enterRound(tester);
      await setLifecycle(tester, AppLifecycleState.paused);

      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      notifier().onChangeTurn({'arg0': _localId}, recorder.show);
      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('nothing is replayed on resume', (tester) async {
      await enterRound(tester);
      await setLifecycle(tester, AppLifecycleState.paused);
      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      await tester.pump();

      await setLifecycle(tester, AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 1500));

      expect(recorder.shown, isEmpty, reason: 'transient, not queued');
    });

    testWidgets('foreground overlays work normally again after resuming',
        (tester) async {
      await enterRound(tester);
      await setLifecycle(tester, AppLifecycleState.paused);
      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      await tester.pump();
      expect(recorder.shown, isEmpty);

      await setLifecycle(tester, AppLifecycleState.resumed);
      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
    });

    testWidgets('a queued overlay is dropped if the app leaves first',
        (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      await tester.pump();
      expect(recorder.shown, hasLength(1));

      await setLifecycle(tester, AppLifecycleState.paused);
      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(1),
          reason: 'the queued strike is dropped, not shown off-screen');
    });

    testWidgets('gameplay state is untouched by a lifecycle change',
        (tester) async {
      await enterRound(tester);
      final before = container.read(gameControllerProvider);

      await setLifecycle(tester, AppLifecycleState.paused);
      await setLifecycle(tester, AppLifecycleState.resumed);

      final after = container.read(gameControllerProvider);
      expect(after.phase, before.phase);
      expect(after.game?.currentTurn, before.game?.currentTurn);
      expect(after.me?.passes, before.me?.passes);
      expect(after.me?.penalty, before.me?.penalty);
    });
  });

  // The turn overlay's wording, in both languages and for both sides. The
  // overlay itself — its lottie, its 1500ms timer, its place in the queue —
  // is exercised by the groups above and is untouched here; only the text
  // it carries is asserted.
  group('the turn overlay names the turn, not just the player', () {
    /// Same entry as [enterRound], with the app language chosen per test.
    /// The language is read through SharedPrefs by appLanguageProvider, the
    /// repository's own detection path, rather than being injected.
    Future<void> enterRoundIn(
      WidgetTester tester,
      String language, {
      int type = 1,
    }) async {
      SharedPreferences.setMockInitialValues({
        'user_id': _localId,
        'app_language': language,
      });
      final prefs = await SharedPrefsService.init();
      final signalR = _FakeSignalRService();
      container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          signalRServiceProvider.overrideWithValue(signalR),
          playGameHubBindingsProvider
              .overrideWithValue(_FakeHubBindings(signalR)),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(gameControllerProvider, (_, __) {});
      addTearDown(sub.close);
      recorder = _DialogRecorder();
      await tester.pumpWidget(const SizedBox());
      notifier().applySessionEvent(
        PlayGameHubEvents.gameStarted,
        _gameJson(type: type),
      );
      await tester.pump();
    }

    Future<String?> turnOverlayText(
      WidgetTester tester,
      String language,
      String playerId, {
      int type = 1,
    }) async {
      await enterRoundIn(tester, language, type: type);
      notifier().onChangeTurn({'arg0': playerId, 'arg1': 'g1'}, recorder.show);
      await tester.pump();
      return recorder.last<RoundLottieDialog>().text;
    }

    testWidgets('my turn, Arabic', (tester) async {
      expect(
        await turnOverlayText(tester, AppLanguage.arabic, _localId),
        'دورك\nالآن',
      );
    });

    testWidgets('my turn, English', (tester) async {
      expect(
        await turnOverlayText(tester, AppLanguage.english, _localId),
        'Your turn\nnow',
      );
    });

    testWidgets('the opponent\'s turn, Arabic', (tester) async {
      expect(
        await turnOverlayText(tester, AppLanguage.arabic, _opponentId),
        'دور\nthem',
        reason: 'the player name is still the roster\'s, verbatim',
      );
    });

    testWidgets('the opponent\'s turn, English', (tester) async {
      expect(
        await turnOverlayText(tester, AppLanguage.english, _opponentId),
        'Turn\nthem',
      );
    });

    testWidgets('the name is never invented for an unseated id',
        (tester) async {
      await enterRoundIn(tester, AppLanguage.english);

      notifier().onChangeTurn({'arg0': '999', 'arg1': 'g1'}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty,
          reason: 'the empty-name guard is unchanged — no overlay at all, '
              'rather than a bare "Turn"');
    });

    // The same overlay is raised by Auction and by a Bell ChangeTurn outside
    // a race. They read from one place, so they read identically.
    testWidgets('Auction reads the same', (tester) async {
      expect(
        await turnOverlayText(tester, AppLanguage.english, _opponentId,
            type: 2),
        'Turn\nthem',
      );
    });

    testWidgets('Auction names my own turn the same way', (tester) async {
      expect(
        await turnOverlayText(tester, AppLanguage.arabic, _localId, type: 2),
        'دورك\nالآن',
      );
    });

    testWidgets('a Bell turn outside a race reads the same', (tester) async {
      // No TimeStarted, so bellPhase is idle — this is the plain turn
      // overlay, not the fastest-racer one.
      expect(
        await turnOverlayText(tester, AppLanguage.english, _localId, type: 3),
        'Your turn\nnow',
      );
    });

    testWidgets('the Bell fastest-racer overlay is untouched', (tester) async {
      await enterRoundIn(tester, AppLanguage.english, type: 3);
      // Arm the race: TimeStarted with no turn assigned.
      notifier().applySharedRoundEvent(
        PlayGameHubEvents.changeTurn,
        {'arg0': '', 'arg1': 'g1'},
      );
      notifier().applySharedRoundEvent(PlayGameHubEvents.timeStarted, null);
      await tester.pump();

      notifier().onChangeTurn({'arg0': _localId, 'arg1': 'g1'}, recorder.show);
      await tester.pump();

      final strings = PlayGameStrings.forLanguage(AppLanguage.english);
      expect(recorder.last<RoundLottieDialog>().text, strings.youAreFastest,
          reason: 'winning the race is a different overlay and keeps its '
              'own copy');
    });
  });
}
