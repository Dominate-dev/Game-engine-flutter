// Fast pacing: round messages are short banners that never block play.
//
// The classic presentation queued every message behind the last and drew it
// over a dark barrier that swallowed taps, and the server waited for each
// one. A turn change, a correct answer and a penalty arriving together took
// four to five seconds to clear before the player could act. With fast
// pacing each message shows at once (the newest replaces the last), lasts a
// little over half as long, and never takes a tap.

import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
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
  // Fast pacing is the default for this module; set explicitly so the file
  // states what it covers.
  setUp(() => GamePace.fast = true);

  late ProviderContainer container;
  late _DialogRecorder recorder;

  GameController notifier() =>
      container.read(gameControllerProvider.notifier);

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
    await tester.pumpWidget(const SizedBox());
    notifier().applySessionEvent(
      PlayGameHubEvents.gameStarted,
      _gameJson(type: type),
    );
    await tester.pump();
  }

  Map<String, dynamic> correctAnswerArgs(String playerId) => {
        'arg0': 'answer',
        'arg1': 'answer en',
        'arg2': playerId,
      };

  group('round messages never hold up the game', () {
    testWidgets('a new message shows at once, without waiting for the last',
        (tester) async {
      await enterRound(tester);

      notifier().onChangeTurn({'arg0': _localId}, recorder.show);
      notifier().onCorrectAnswer(correctAnswerArgs(_localId), recorder.show);
      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      await tester.pump();

      expect(recorder.shown, hasLength(3),
          reason: 'nothing queues behind an open message');
    });

    testWidgets('messages are a little over half their classic length',
        (tester) async {
      await enterRound(tester);

      notifier().onChangeTurn({'arg0': _localId}, recorder.show);
      await tester.pump();
      expect(recorder.last<RoundLottieDialog>().timer, 825); // classic 1500

      notifier().onPenalty({'playerId': _localId, 'type': 2}, recorder.show);
      await tester.pump();
      expect(recorder.last<RoundLottieDialog>().timer, 1100); // classic 2000
    });
  });

  group('the message layer never takes a tap', () {
    testWidgets('a button under an open message still works', (tester) async {
      var taps = 0;
      final scope = ProviderContainer();
      addTearDown(scope.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Center(
                    child: ElevatedButton(
                      onPressed: () => taps++,
                      child: const Text('answer'),
                    ),
                  ),
                  const RoundSubPanelLayer(),
                ],
              ),
            ),
          ),
        ),
      );

      unawaited(scope.read(roundSubPanelProvider.notifier).show(const Text('your turn')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('your turn'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(RoundSubPanelLayer), matching: find.byType(ModalBarrier)),
        findsNothing,
      );
      await tester.tap(find.text('answer'));
      expect(taps, 1);
    });
  });

  group('the server is asked for fast pacing', () {
    test('every request carries game-pace: fast', () async {
      SharedPreferences.setMockInitialValues({'user_id': _localId});
      final prefs = await SharedPrefsService.init();
      final headers = await ApiHeadersBuilder(prefs).buildGlobalHeaders();
      expect(headers['game-pace'], 'fast');
    });

    test('classic sends no pacing header', () async {
      GamePace.fast = false;
      addTearDown(() => GamePace.fast = true);
      SharedPreferences.setMockInitialValues({'user_id': _localId});
      final prefs = await SharedPrefsService.init();
      final headers = await ApiHeadersBuilder(prefs).buildGlobalHeaders();
      expect(headers.containsKey('game-pace'), isFalse);
    });
  });
}
