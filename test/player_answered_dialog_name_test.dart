import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:play_game/play_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The answer bar's optional attribution line: the answer stays as it was, and
// a non-empty playerName adds a yellow line under it. Empty — the default,
// and the case when the answer is this device's own — renders nothing extra.

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required String answer,
    String playerName = '',
  }) async {
    SharedPreferences.setMockInitialValues({
      'app_language': AppLanguage.english,
    });
    final prefs = await SharedPrefsService.init();
    final container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: PlayerAnsweredDialog(
              answer: answer,
              playerName: playerName,
              // Long enough that the auto-dismiss never runs mid-test.
              timer: 100000,
            ),
          ),
        ),
      ),
    );
    // The slide-in.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The rendered colour of a given text, as the viewer sees it.
  Color? colorOf(WidgetTester tester, String text) {
    final widget = tester.widget<AppTextView>(
      find.ancestor(
        of: find.text(text),
        matching: find.byType(AppTextView),
      ).first,
    );
    return widget.color;
  }

  // The purple bar itself, not the Scaffold's Material.
  Finder purpleBar() => find.byWidgetPredicate(
        (w) => w is Material && w.color == AppColors.purple,
      );

  testWidgets('an empty player name renders no second line', (tester) async {
    await pumpBar(tester, answer: 'blue');

    expect(find.text('blue'), findsOneWidget);
    expect(find.byType(AppTextView), findsOneWidget,
        reason: 'the answer, and nothing else');
  });

  testWidgets('the default is empty', (tester) async {
    await pumpBar(tester, answer: 'blue');

    expect(
      tester.widget<PlayerAnsweredDialog>(find.byType(PlayerAnsweredDialog))
          .playerName,
      isEmpty,
    );
  });

  testWidgets('a player name renders under the answer, in yellow',
      (tester) async {
    await pumpBar(tester, answer: 'blue', playerName: 'them');

    expect(find.text('blue'), findsOneWidget);
    expect(find.text('them'), findsOneWidget);
    expect(colorOf(tester, 'them'), AppColors.yellow);
    expect(colorOf(tester, 'blue'), AppColors.onBackground,
        reason: 'the answer keeps its own colour');
  });

  testWidgets('the name sits below the answer', (tester) async {
    await pumpBar(tester, answer: 'blue', playerName: 'them');

    expect(
      tester.getCenter(find.text('them')).dy,
      greaterThan(tester.getCenter(find.text('blue')).dy),
    );
  });

  testWidgets('a whitespace-only name is treated as empty', (tester) async {
    await pumpBar(tester, answer: 'blue', playerName: '   ');

    expect(find.byType(AppTextView), findsOneWidget);
  });

  testWidgets('the bar keeps its designed height with no name',
      (tester) async {
    await pumpBar(tester, answer: 'blue');

    final bar = tester.getSize(purpleBar());
    expect(bar.height, 70, reason: 'unchanged from before the name was added');
  });

  testWidgets('the bar grows for the name rather than clipping it',
      (tester) async {
    await pumpBar(tester, answer: 'blue', playerName: 'them');

    final bar = tester.getSize(purpleBar());
    expect(bar.height, greaterThanOrEqualTo(70.0));
    expect(tester.takeException(), isNull, reason: 'no overflow');
  });
}
