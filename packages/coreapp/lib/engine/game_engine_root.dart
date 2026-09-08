import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../presentation/app_theme.dart';
import '../presentation/providers/app_language_provider.dart';
import '../presentation/widgets/loader_overlay.dart';

// The engine's own root, for when a native host is driving.
//
// Deliberately not `AppRoot`, which is the debug launcher's: that one carries
// `AppTheme.navigatorKey` (null in release, so useless for host-driven
// navigation), the `homeLauncherRouteObserver` that exists only to run the
// launcher's clearGameData, and `HomeLauncherPage` as its home. None of the
// three belongs in a hosted engine. What the two genuinely share — locale,
// the theme, the localization delegates and the loader overlay — is reused
// from AppTheme and LoaderOverlay rather than copied.
//
// The engine starts idle: no game, no connection, nothing dispatched. It sits
// on [idle] until the host issues a Public API command, and the game flows
// then push their routes onto this navigator.
class GameEngineRoot extends ConsumerWidget {
  const GameEngineRoot({
    super.key,
    required this.navigatorKey,
    this.idle,
  });

  // The engine's navigator, created and owned by GameEngineRuntime. Never
  // handed across the native boundary — the host names a flow, and the engine
  // navigates.
  final GlobalKey<NavigatorState> navigatorKey;

  // What shows before the host asks for anything. A blank surface by default:
  // inventing a menu here would put product decisions in the engine.
  final Widget? idle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languageCode = ref.watch(appLanguageProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: AppTheme.localeFromLanguageCode(languageCode),
      supportedLocales: AppTheme.supportedLocales,
      localizationsDelegates: AppTheme.localizationsDelegates,
      navigatorKey: navigatorKey,
      theme: AppTheme.light(languageCode: languageCode),
      // The connection loader and the API loader both live here, exactly as
      // they do for the debug launcher.
      builder: (context, child) => LoaderOverlay(child: child!),
      home: idle ?? const GameEngineIdlePage(),
    );
  }
}

// The engine's resting state. Blank on purpose — the host's own UI is behind
// the Flutter view until a flow is requested.
class GameEngineIdlePage extends StatelessWidget {
  const GameEngineIdlePage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}
