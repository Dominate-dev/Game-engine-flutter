abstract final class AppLanguage {
  static const english = 'en';
  static const arabic = 'ar';

  static String normalize(String? code) {
    final value = code?.trim().toLowerCase() ?? english;
    if (value.startsWith(arabic) || value == 'arabic') {
      return arabic;
    }
    return english;
  }

  static bool isArabic(String languageCode) => normalize(languageCode) == arabic;
}
