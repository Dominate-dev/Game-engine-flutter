import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:coreapp/coreapp.dart';
import 'package:game_engine/core/constants/debug_config.dart';
import 'package:game_engine/features/home/presentation/pages/home_launcher_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('HomeLauncherPage shows four game buttons', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPrefsService.init();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: HomeLauncherPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('PvP'), findsOneWidget);
    expect(find.text('Judge'), findsOneWidget);
    expect(find.text('All In One'), findsOneWidget);
    expect(find.text('Loader'), findsOneWidget);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Start hub'), findsOneWidget);
    // Read from DebugConfig rather than duplicated here: the launcher
    // prefills this field from it, and which test account is active is
    // changed there routinely (the alternatives sit commented beside it).
    // Pinning the literal made a deliberate account switch look like a
    // regression.
    expect(find.text(DebugConfig.socialMedia), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}
