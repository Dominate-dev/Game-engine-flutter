import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:coreapp/coreapp.dart';

import 'features/home/presentation/pages/home_launcher_page.dart';

// Anchors the host entry point into the build. `flutter build aar` compiles
// from `lib/main.dart` and says so itself — "This command assumes that the
// entrypoint is lib/main.dart. This cannot currently be configured." — and the
// Gradle plugin's source integration defaults to the same file. A library this
// one does not reach is absent from the module's kernel/AOT snapshot, so
// without this line `gameEngineMain` ships nowhere and the host's
// DartEntrypoint never resolves. A compilation edge only: the two entry points
// stay separate.
export 'engine_entry.dart' show gameEngineMain;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPrefsService.init();
  AppStrings.setLanguage(prefs.getLanguage());

  final container = ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
    ],
  );

  final lifecycleObserver = AppLifecycleObserver(
    container.read(signalRServiceProvider),
  );
  WidgetsBinding.instance.addObserver(lifecycleObserver);

  AppLogger.log('main() — hub idle until Start Hub');

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AppRoot(),
    ),
  );
}

class AppRoot extends ConsumerWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languageCode = ref.watch(appLanguageProvider);
    final locale = AppTheme.localeFromLanguageCode(languageCode);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppTheme.supportedLocales,
      localizationsDelegates: AppTheme.localizationsDelegates,
      navigatorKey: AppTheme.navigatorKey,
      navigatorObservers: [homeLauncherRouteObserver],
      theme: AppTheme.light(languageCode: languageCode),
      builder: (context, child) => LoaderOverlay(child: child!),
      home: const HomeLauncherPage(),
    );
  }
}
