import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_language.dart';
import '../../di/providers.dart';
import '../../l10n/app_strings.dart';

// Current app language from native SharedPreferences (`app_language`).
// Call [AppLanguageNotifier.setLanguage] to persist and rebuild UI.
final appLanguageProvider =
    NotifierProvider<AppLanguageNotifier, String>(AppLanguageNotifier.new);

final appStringsProvider = Provider<AppStrings>((ref) {
  return AppStrings.forLanguage(ref.watch(appLanguageProvider));
});

class AppLanguageNotifier extends Notifier<String> {
  @override
  String build() {
    final code = AppLanguage.normalize(
      ref.watch(sharedPrefsProvider).getLanguage(),
    );
    AppStrings.setLanguage(code);
    return code;
  }

  Future<void> setLanguage(String languageCode) async {
    final code = AppLanguage.normalize(languageCode);
    await ref.read(sharedPrefsProvider).setLanguage(value: code);
    AppStrings.setLanguage(code);
    state = code;
  }
}
