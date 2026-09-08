import 'package:flutter_test/flutter_test.dart';
import 'package:coreapp/coreapp.dart';
import 'package:play_game/play_game.dart';

void main() {
  group('AppStrings', () {
    test('returns English and Arabic classes for the same field', () {
      expect(AppStrings.forLanguage(AppLanguage.english).confirm, 'Confirm');
      expect(AppStrings.forLanguage(AppLanguage.arabic).confirm, 'تأكيد');
      expect(
        AppStrings.forLanguage(AppLanguage.arabic).noInternet,
        'لا يوجد اتصال بالإنترنت',
      );
    });

    test('setLanguage changes AppStrings.current', () {
      AppStrings.setLanguage(AppLanguage.arabic);
      expect(AppStrings.current.cancel, 'إلغاء');
      expect(AppStrings.current, same(AppStrings.arabic));

      AppStrings.setLanguage(AppLanguage.english);
      expect(AppStrings.current.cancel, 'Cancel');
      expect(AppStrings.current, same(AppStrings.english));
    });

    test('Failure defaults follow the current language', () {
      AppStrings.setLanguage(AppLanguage.arabic);
      expect(NoInternetFailure().message, 'لا يوجد اتصال بالإنترنت');

      AppStrings.setLanguage(AppLanguage.english);
      expect(NoInternetFailure().message, 'No internet connection');
    });
  });

  // titleFor is the one place a GamePhase becomes user-facing text. No phase
  // reaches the toolbar today — GameControllerScreen's `isImmersive` covers
  // all nine, so `appBar` is always null — which is exactly why the mapping
  // needs pinning: nothing on screen would reveal a wrong entry.
  group('PlayGameStrings.titleFor', () {
    test('the private lobby uses its own title, not the public lobby one',
        () {
      for (final language in [AppLanguage.english, AppLanguage.arabic]) {
        final strings = PlayGameStrings.forLanguage(language);
        expect(
          strings.titleFor(GamePhase.lobbyPrivate),
          strings.lobbyPrivateTitle,
          reason: '$language',
        );
        expect(
          strings.titleFor(GamePhase.lobbyPrivate),
          isNot(strings.lobbyPlayTitle),
          reason: 'the two lobbies are distinct strings in $language',
        );
      }
    });

    test('every phase maps to a non-empty title in both locales', () {
      for (final language in [AppLanguage.english, AppLanguage.arabic]) {
        final strings = PlayGameStrings.forLanguage(language);
        for (final phase in GamePhase.values) {
          expect(
            strings.titleFor(phase).trim(),
            isNotEmpty,
            reason: '$phase has no title in $language',
          );
        }
      }
    });

    test('the public lobby is unchanged', () {
      final strings = PlayGameStrings.forLanguage(AppLanguage.english);
      expect(strings.titleFor(GamePhase.lobbyPlay), strings.lobbyPlayTitle);
    });
  });
}
