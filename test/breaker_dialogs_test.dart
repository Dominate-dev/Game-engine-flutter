import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Breaker (round 5) dialogs — confirmed to share Comeback's exact dialog
// lifecycle (onComebackTimeStarted/onComebackCorrectAnswer/onComebackPenalty
// are the same methods Comeback uses, dispatched dynamically against
// `_s.phase`). This file proves that shared mechanism activates correctly
// for GamePhase.breaker and proves the one genuinely Breaker-specific piece
// — the round intro dialog, which already has its own dedicated
// AppLottieView.breaker asset and breakerRoundHeading string in the
// existing shared showRoundIntro machinery.

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

/// Keeps each dialog "open" until the test dismisses it, so stacking shows up.
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

/// Silences playback the same way the WDYK/Bell intro tests do.
class _FakeAudioService extends AudioService {
  final musicStarted = <String>[];

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
  }) async {
    musicStarted.add(asset);
  }

  @override
  Future<void> playSfx(
    String asset, {
    String? package,
    double? volume,
  }) async {}
}

Map<String, dynamic> _breakerGame() => {
      'id': 'g1',
      'status': 3,
      'type': 5, // GameType.breaker
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
        'text': 'q',
        'textEn': 'q',
        'answers': [
          {'id': 10, 'text': 'a1', 'textEn': 'a1'},
        ],
      },
    };

void main() {
  late ProviderContainer container;
  late _DialogRecorder recorder;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

  final strings = PlayGameStrings.forLanguage(AppLanguage.english);

  Future<void> enterRound(WidgetTester tester) async {
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

    await tester.pumpWidget(const SizedBox());
    notifier()
        .applySessionEvent(PlayGameHubEvents.gameStarted, _breakerGame());
    await tester.pump();
  }

  // CorrectAnswer is (text, textEn, playerId, gameId) per the established
  // W-CONTRACT shape every round's CorrectAnswer already shares — arg2 is
  // the player.
  Map<String, dynamic> correctAnswerArgs(String playerId) => {
        'arg0': 'answer',
        'arg1': 'answer en',
        'arg2': playerId,
      };

  group('round intro — the one genuinely Breaker-specific dialog', () {
    testWidgets(
        'uses the Breaker Lottie asset and heading, distinct from Comeback, '
        'for 2000ms', (tester) async {
      await enterRound(tester);
      final audio = _FakeAudioService();

      unawaited(notifier().showRoundIntro(recorder.show, audio));
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      final dialog = recorder.last<RoundLottieDialog>();
      expect(dialog.text, strings.breakerRoundHeading);
      expect(dialog.text, isNot(strings.comeBackRoundHeading));
      expect((dialog.lottie as AppLottieView).asset, AppAssets.lottieBreaker);
      expect((dialog.lottie as AppLottieView).asset,
          isNot(AppAssets.lottieComeBack));
      expect(dialog.timer, 2000);

      recorder.dismissAll();
      await tester.pump();
    });
  });

  group('TimeStarted', () {
    testWidgets('enqueues the Start Timer overlay for 2000ms, the same '
        'dialog Comeback uses', (tester) async {
      await enterRound(tester);

      notifier().onTimeStarted(null, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      final dialog = recorder.last<RoundLottieDialog>();
      expect(dialog.timer, 2000);
      expect(dialog.text, strings.startTimer);
      expect(dialog.sound, AppSounds.startTime);
    });
  });

  group('CorrectAnswer', () {
    testWidgets('mine → my own correct-answer overlay, 1500ms',
        (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      final dialog = recorder.last<RoundLottieDialog>();
      expect(dialog.text, strings.correctAnswer);
      expect((dialog.lottie as AppLottieView).asset,
          AppAssets.lottieCorrectAnswer);
      expect(dialog.sound, AppSounds.rightAnswer);
      expect(dialog.timer, 1500);
    });

    testWidgets("the opponent's → the answer bar naming them, 2000ms — the "
        'same treatment Comeback uses', (tester) async {
      await enterRound(tester);

      notifier()
          .onCorrectAnswer(correctAnswerArgs(_opponentId), recorder.show);
      await tester.pump();

      final dialog = recorder.last<PlayerAnsweredDialog>();
      expect(dialog.answer, 'answer en');
      expect(dialog.playerName, 'them');
      expect(dialog.timer, 2000);
    });
  });

  group('Penalty', () {
    testWidgets('type 2 (wrong) for me shows the wrong-answer dialog, '
        '1500ms', (tester) async {
      await enterRound(tester);

      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().text, strings.wrongAnswer);
      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });

    testWidgets('type 2 (wrong) for the opponent shows nothing to me',
        (tester) async {
      await enterRound(tester);

      notifier()
          .onPenalty({'playerId': _opponentId, 'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.shown, isEmpty);
    });

    testWidgets('type 1 (timeout) shows the timeout dialog, 1500ms, to both',
        (tester) async {
      await enterRound(tester);

      notifier()
          .onPenalty({'playerId': _opponentId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(1));
      expect(recorder.last<RoundLottieDialog>().text, strings.timeout);
      expect(recorder.last<RoundLottieDialog>().timer, 1500);
    });
  });

  group('queue behaviour — dequeues correctly against GamePhase.breaker',
      () {
    testWidgets('a dialog enqueued while in Breaker still shows once its '
        'turn comes, and is dropped only if the phase actually changed',
        (tester) async {
      await enterRound(tester);

      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      notifier()
          .onPenalty({'playerId': _opponentId, 'type': 1}, recorder.show);
      await tester.pump();

      expect(recorder.openCount, 1, reason: 'no stacking');
      recorder.dismissAll();
      await tester.pump();

      expect(recorder.shown, hasLength(2));
      expect(
        recorder.shown[0],
        isA<RoundLottieDialog>()
            .having((d) => d.text, 'text', strings.correctAnswer),
      );
      expect(
        recorder.shown[1],
        isA<RoundLottieDialog>().having((d) => d.text, 'text', strings.timeout),
      );
    });
  });
}
