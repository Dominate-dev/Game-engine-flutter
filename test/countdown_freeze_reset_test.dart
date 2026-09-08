import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The post-freeze reset.
//
// `freezeAndReset()` freezes immediately — the value the server last
// reported stays readable. `CountdownTimerText.freezeResetDelay` (500ms)
// later the countdown is disposed and the display returns to 00:00, so a
// stale number does not sit on screen for the rest of the round.
//
// This is implemented in the existing timer lifecycle rather than beside it:
// every freeze path in the app goes through `CountdownTimerController`, so
// covering it here covers all of them.

/// Advances one second per pump, the way the round timer suites do — a
/// single multi-second pump does not step a periodic countdown.
Future<void> tick(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Mounts a controller-driven countdown, the same way RoundScoreColumn does.
Future<CountdownTimerController> pumpTimer(
  WidgetTester tester, {
  VoidCallback? onFinished,
}) async {
  final controller = CountdownTimerController();
  SharedPreferences.setMockInitialValues({'app_language': AppLanguage.english});
  final prefs = await SharedPrefsService.init();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Scaffold(
          body: CountdownTimerText(
            seconds: 0,
            controller: controller,
            autoStart: false,
            onFinished: onFinished,
          ),
        ),
      ),
    ),
  );
  return controller;
}

void main() {
  group('the freeze itself is unchanged', () {
    testWidgets('freezeAndReset freezes at the current value immediately',
        (tester) async {
      final controller = await pumpTimer(tester);

      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);
      expect(find.text('00:07'), findsOneWidget);

      controller.freezeAndReset();
      await tester.pump();

      expect(find.text('00:07'), findsOneWidget,
          reason: 'the freeze is immediate — no reset yet');
      expect(find.text('00:00'), findsNothing);
    });

    testWidgets('the value holds for the whole reset window', (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);

      controller.freezeAndReset();
      await tester.pump();

      // Just short of the delay: still frozen, and the countdown has not
      // resumed either.
      await tester.pump(const Duration(milliseconds: 499));
      expect(find.text('00:07'), findsOneWidget);
    });

    testWidgets('the countdown does not resume during the window',
        (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 2);
      expect(find.text('00:08'), findsOneWidget);

      controller.freezeAndReset();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('00:08'), findsOneWidget,
          reason: 'frozen, not ticking — 00:07 would mean it kept running');
    });
  });

  group('after the delay', () {
    testWidgets('the display resets to 00:00', (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);

      controller.freezeAndReset();
      await tester.pump();
      await tester.pump(CountdownTimerText.freezeResetDelay);

      expect(find.text('00:00'), findsOneWidget);
      expect(find.text('00:07'), findsNothing);
    });

    testWidgets('no stale tick can change the value afterwards',
        (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);

      controller.freezeAndReset();
      await tester.pump();
      await tester.pump(CountdownTimerText.freezeResetDelay);
      expect(find.text('00:00'), findsOneWidget);

      // Well past several would-be ticks of the disposed countdown.
      await tick(tester, 5);

      expect(find.text('00:00'), findsOneWidget,
          reason: 'the countdown was disposed — nothing may drive it below '
              'zero or resurrect the frozen value');
    });

    testWidgets('onFinished is not fired by the reset', (tester) async {
      var finished = 0;
      final controller = await pumpTimer(tester, onFinished: () => finished++);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);

      controller.freezeAndReset();
      await tester.pump();
      await tester.pump(CountdownTimerText.freezeResetDelay);
      await tick(tester, 2);

      expect(finished, 0,
          reason: 'clearing the display is not the countdown expiring — the '
              'server already resolved this question');
    });

    testWidgets('two stops in a row leave only one pending reset',
        (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);

      controller.freezeAndReset();
      controller.freezeAndReset();
      await tester.pump();
      await tester.pump(CountdownTimerText.freezeResetDelay);

      expect(find.text('00:00'), findsOneWidget);
      await tick(tester, 2);
      expect(find.text('00:00'), findsOneWidget);
    });
  });

  group('a new server value still starts the timer normally', () {
    testWidgets('after the reset has landed', (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);
      controller.freezeAndReset();
      await tester.pump();
      await tester.pump(CountdownTimerText.freezeResetDelay);
      expect(find.text('00:00'), findsOneWidget);

      controller.startTimer(8);
      await tester.pump();
      expect(find.text('00:08'), findsOneWidget);

      await tick(tester, 1);
      expect(find.text('00:07'), findsOneWidget,
          reason: 'the server-authoritative start is unaffected');
    });

    testWidgets('and inside the reset window, superseding the pending reset',
        (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);

      controller.freezeAndReset();
      await tester.pump();
      // A TimerUpdatedSeconds lands before the reset would have.
      await tester.pump(const Duration(milliseconds: 200));
      controller.startTimer(8);
      await tester.pump();
      expect(find.text('00:08'), findsOneWidget);

      // The moment the cancelled reset would have fired.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('00:00'), findsNothing,
          reason: 'the pending reset must not zero a countdown the server '
              'just restarted');

      await tick(tester, 1);
      expect(find.text('00:07'), findsOneWidget);
    });

    testWidgets('a freeze after a restart resets from the new value',
        (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      controller.freezeAndReset();
      await tester.pump();
      controller.startTimer(5);
      await tester.pump();
      await tick(tester, 1);
      expect(find.text('00:04'), findsOneWidget);

      controller.freezeAndReset();
      await tester.pump();
      expect(find.text('00:04'), findsOneWidget, reason: 'frozen');

      await tester.pump(CountdownTimerText.freezeResetDelay);
      expect(find.text('00:00'), findsOneWidget);
    });
  });

  group('disposal', () {
    testWidgets('a pending reset does not fire after the widget is gone',
        (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);

      controller.freezeAndReset();
      await tester.pump();

      // Unmounted mid-window — the reset must not call setState on a dead
      // State.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tick(tester, 2);

      expect(tester.takeException(), isNull);
    });
  });

  // The split: only the terminal path clears. `stopTimer()` is the plain
  // stop, and `startTimer()` — which is what every TimerUpdatedSeconds goes
  // through — never schedules a clear and always cancels a pending one.
  group('stopTimer is the plain stop, with no delayed clear', () {
    testWidgets('the frozen value stays indefinitely', (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);

      controller.stopTimer();
      await tester.pump();
      await tester.pump(CountdownTimerText.freezeResetDelay);
      await tick(tester, 3);

      expect(find.text('00:07'), findsOneWidget,
          reason: 'no clear was scheduled — that belongs to the terminal path');
    });

    testWidgets('it also cancels a clear a terminal freeze had pending',
        (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);

      controller.freezeAndReset();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      controller.stopTimer();
      await tester.pump();
      await tick(tester, 2);

      expect(find.text('00:07'), findsOneWidget,
          reason: 'the superseding stop owns the display now');
    });
  });

  group('a server value is applied immediately, never delayed', () {
    testWidgets('a value of 7 starts at once', (tester) async {
      final controller = await pumpTimer(tester);

      controller.startTimer(7);
      await tester.pump();

      expect(find.text('00:07'), findsOneWidget);
      await tick(tester, 1);
      expect(find.text('00:06'), findsOneWidget);
    });

    testWidgets('a value of 7 is unaffected by a pending terminal clear',
        (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);

      controller.freezeAndReset();
      await tester.pump();
      controller.startTimer(7);
      await tester.pump();
      expect(find.text('00:07'), findsOneWidget);

      // The instant the cancelled clear would have fired.
      await tester.pump(CountdownTimerText.freezeResetDelay);
      expect(find.text('00:00'), findsNothing,
          reason: 'a stale clear must never zero a fresh server value');
      await tick(tester, 1);
      expect(find.text('00:06'), findsOneWidget);
    });

    testWidgets('a value of 3 mid-countdown takes effect at once and '
        'continues', (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 2);
      expect(find.text('00:08'), findsOneWidget);

      controller.startTimer(3);
      await tester.pump();
      expect(find.text('00:03'), findsOneWidget,
          reason: 'the server value replaces the running countdown');

      await tick(tester, 1);
      expect(find.text('00:02'), findsOneWidget);
    });

    testWidgets('a value of 0 shows 00:00 immediately, with no delay',
        (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);
      expect(find.text('00:07'), findsOneWidget);

      controller.startTimer(0);
      await tester.pump();

      expect(find.text('00:00'), findsOneWidget,
          reason: 'zeroed on arrival — not frozen for 500ms first');
    });

    testWidgets('a value of 0 does not leave a clear pending either',
        (tester) async {
      final controller = await pumpTimer(tester);
      controller.startTimer(0);
      await tester.pump();
      expect(find.text('00:00'), findsOneWidget);

      controller.startTimer(6);
      await tester.pump();
      expect(find.text('00:06'), findsOneWidget);

      await tester.pump(CountdownTimerText.freezeResetDelay);
      expect(find.text('00:06'), findsOneWidget,
          reason: 'nothing was scheduled by the zero value');
    });
  });

  // At zero the countdown is over, not running out — so it drops the danger
  // colour. Asserted through `normalColor`/`dangerColor` rather than a
  // literal, because the widget is parameterised: the round timer passes
  // blue (RoundScoreColumn), the lobby ready timer keeps the default.
  group('the colour at 00:00', () {
    const normal = Color(0xFF0000FF);
    const danger = Color(0xFFFF0000);

    Future<CountdownTimerController> pumpColoured(WidgetTester tester) async {
      final controller = CountdownTimerController();
      SharedPreferences.setMockInitialValues(
        {'app_language': AppLanguage.english},
      );
      final prefs = await SharedPrefsService.init();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            home: Scaffold(
              body: CountdownTimerText(
                seconds: 0,
                controller: controller,
                autoStart: false,
                normalColor: normal,
                dangerColor: danger,
              ),
            ),
          ),
        ),
      );
      return controller;
    }

    Color colourOf(WidgetTester tester) => tester
        .widget<AppNumberTextView>(find.byType(AppNumberTextView))
        .color!;

    testWidgets('a countdown that expires on its own ends on the normal '
        'colour', (tester) async {
      final controller = await pumpColoured(tester);
      controller.startTimer(2);
      await tester.pump();
      await tick(tester, 2);

      expect(find.text('00:00'), findsOneWidget);
      expect(colourOf(tester), normal,
          reason: 'over, not running out — no red at zero');
    });

    testWidgets('the value cleared after a terminal freeze is normal too',
        (tester) async {
      final controller = await pumpColoured(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 3);

      controller.freezeAndReset();
      await tester.pump();
      await tester.pump(CountdownTimerText.freezeResetDelay);

      expect(find.text('00:00'), findsOneWidget);
      expect(colourOf(tester), normal);
    });

    testWidgets('a server value of zero is normal, not danger',
        (tester) async {
      final controller = await pumpColoured(tester);
      controller.startTimer(0);
      await tester.pump();

      expect(find.text('00:00'), findsOneWidget);
      expect(colourOf(tester), normal);
    });

    testWidgets('the danger colour is still used while time remains',
        (tester) async {
      final controller = await pumpColoured(tester);
      controller.startTimer(10);
      await tester.pump();
      await tick(tester, 9);

      expect(find.text('00:01'), findsOneWidget);
      expect(colourOf(tester), danger,
          reason: 'the warning itself is unchanged — only zero was wrong');
    });

    testWidgets('a full-value countdown still starts on the normal colour',
        (tester) async {
      final controller = await pumpColoured(tester);
      controller.startTimer(10);
      await tester.pump();

      expect(colourOf(tester), normal);
    });
  });
}
