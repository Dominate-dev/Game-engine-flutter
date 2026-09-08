import 'package:flutter/material.dart';

import 'app_language.dart';

/// Pubspec family names — one family per TTF so each [AppFontWeight]
/// loads the exact asset (no synthetic bold).
abstract final class AppFontFamily {
  static const enLight = 'EnLight';
  static const enRegular = 'EnRegular';
  static const enMedium = 'EnMedium';
  static const enBold = 'EnBold';
  static const enExtraBold = 'EnExtraBold';

  static const arLight = 'ArLight';
  static const arRegular = 'ArRegular';
  static const arMedium = 'ArMedium';
  static const arSemiBold = 'ArSemiBold';
  static const arBold = 'ArBold';

  static const gameIcons = 'GameIcons';
  static const numbers = 'Numbers';
}

/// Weight token.
///
/// Language-aware: [light], [regular], [medium], [semiBold], [bold],
/// [extraBold] → En* or Ar* from the current app language.
///
/// Specific (ignore language): [enBold], [arBold], [enMedium], …
enum AppFontWeight {
  light,
  regular,
  medium,
  semiBold,
  bold,
  extraBold,

  enLight,
  enRegular,
  enMedium,
  enBold,
  enExtraBold,

  arLight,
  arRegular,
  arMedium,
  arSemiBold,
  arBold,

  /// Language-independent [AppFontFamily.numbers].
  number,
}

/// Resolves En/Ar font families from language + [AppFontWeight].
abstract final class AppFonts {
  /// Fonts are declared in this package's pubspec. [TextStyle.package]
  /// is required so the host app loads `packages/coreapp/EnBold` instead
  /// of looking for `EnBold` in its own FontManifest (and silently
  /// falling back to the system font).
  static const packageName = 'coreapp';

  static bool isArabic(String languageCode) =>
      AppLanguage.isArabic(languageCode);

  /// Exact pubspec family for [languageCode] + [weight].
  static String familyFor({
    required String languageCode,
    AppFontWeight weight = AppFontWeight.regular,
  }) {
    final arabic = isArabic(languageCode);
    return switch (weight) {
      AppFontWeight.light =>
        arabic ? AppFontFamily.arLight : AppFontFamily.enLight,
      AppFontWeight.regular =>
        arabic ? AppFontFamily.arRegular : AppFontFamily.enRegular,
      AppFontWeight.medium =>
        arabic ? AppFontFamily.arMedium : AppFontFamily.enMedium,
      AppFontWeight.semiBold =>
        arabic ? AppFontFamily.arSemiBold : AppFontFamily.enMedium,
      AppFontWeight.bold =>
        arabic ? AppFontFamily.arBold : AppFontFamily.enBold,
      AppFontWeight.extraBold => AppFontFamily.enExtraBold,
      AppFontWeight.enLight => AppFontFamily.enLight,
      AppFontWeight.enRegular => AppFontFamily.enRegular,
      AppFontWeight.enMedium => AppFontFamily.enMedium,
      AppFontWeight.enBold => AppFontFamily.enBold,
      AppFontWeight.enExtraBold => AppFontFamily.enExtraBold,
      AppFontWeight.arLight => AppFontFamily.arLight,
      AppFontWeight.arRegular => AppFontFamily.arRegular,
      AppFontWeight.arMedium => AppFontFamily.arMedium,
      AppFontWeight.arSemiBold => AppFontFamily.arSemiBold,
      AppFontWeight.arBold => AppFontFamily.arBold,
      AppFontWeight.number => AppFontFamily.numbers,
    };
  }

  static TextStyle style({
    required String languageCode,
    AppFontWeight weight = AppFontWeight.regular,
    double? fontSize,
    Color? color,
    double? height,
    TextDecoration? decoration,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: familyFor(
        languageCode: languageCode,
        weight: weight,
      ),
      package: packageName,
      // Each family is a single TTF registered as w400. Pin normal so
      // Theme/DefaultTextStyle (often w500 in Material 3) cannot look up
      // a missing weight and silently keep the previous font.
      fontWeight: FontWeight.w400,
      fontSize: fontSize,
      color: color,
      height: height,
      decoration: decoration ?? TextDecoration.none,
      letterSpacing: letterSpacing,
      leadingDistribution: TextLeadingDistribution.proportional,
    );
  }

  static TextTheme textTheme(String languageCode) {
    TextStyle s(AppFontWeight weight, {double? size}) => style(
          languageCode: languageCode,
          weight: weight,
          fontSize: size,
        );

    return TextTheme(
      displayLarge: s(AppFontWeight.extraBold, size: 57),
      displayMedium: s(AppFontWeight.bold, size: 45),
      displaySmall: s(AppFontWeight.bold, size: 36),
      headlineLarge: s(AppFontWeight.bold, size: 32),
      headlineMedium: s(AppFontWeight.semiBold, size: 28),
      headlineSmall: s(AppFontWeight.semiBold, size: 24),
      titleLarge: s(AppFontWeight.semiBold, size: 22),
      titleMedium: s(AppFontWeight.medium, size: 16),
      titleSmall: s(AppFontWeight.medium, size: 14),
      bodyLarge: s(AppFontWeight.regular, size: 16),
      bodyMedium: s(AppFontWeight.regular, size: 14),
      bodySmall: s(AppFontWeight.light, size: 12),
      labelLarge: s(AppFontWeight.bold, size: 14),
      labelMedium: s(AppFontWeight.medium, size: 12),
      labelSmall: s(AppFontWeight.regular, size: 11),
    );
  }
}
