import '../constants/app_language.dart';
import 'ar_app_strings.dart';
import 'en_app_strings.dart';

// Language-specific copy. Use [current] or [forLanguage] — never hardcode EN/AR.
abstract class AppStrings {
  const AppStrings();

  static String _languageCode = AppLanguage.english;

  static const AppStrings english = EnAppStrings();
  static const AppStrings arabic = ArAppStrings();

  static String get languageCode => _languageCode;

  static void setLanguage(String? languageCode) {
    _languageCode = AppLanguage.normalize(languageCode);
  }

  static AppStrings get current => forLanguage(_languageCode);

  static AppStrings forLanguage(String? languageCode) {
    return AppLanguage.isArabic(languageCode ?? _languageCode)
        ? arabic
        : english;
  }

  String get confirm;
  String get cancel;
  String get requestFailed;
  String get serverError;
  String get serverErrorShort;
  String get noInternet;
  String get requestTimedOut;
  String get unauthorized;
  String get unknownError;
  String get loginMissingToken;
  String get failedToBuildHeaders;
  String get homeTitle;
  String get play;
  String get pvp;
  String get judge;
  String get allInOne;
  String get settings;
  String get language;
  String get englishName;
  String get arabicName;
  String get pluginComingSoon;
  String get socialMediaId;
  String get register;
  String get registerSuccess;
  String get reconnectNetworkGame;
  String get reconnect;
  String get loader;
  String get connectionLoader;
  String get startHub;
  String get hubConnected;
  String get hubAlreadyConnected;
  String get hubConnectFailed;
  String get gameCode;
  String get joinPrivateGame;
  String get gameCodeRequired;
  String get playerProfile;
  String get clearData;
  String get clearDataSuccess;
}
