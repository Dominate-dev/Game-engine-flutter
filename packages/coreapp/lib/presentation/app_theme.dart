import 'package:chucker_flutter/chucker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../constants/app_colors.dart';
import '../constants/app_fonts.dart';
import '../constants/app_language.dart';

abstract final class AppTheme {
  static const supportedLocales = [
    Locale(AppLanguage.english),
    Locale(AppLanguage.arabic),
  ];

  // Required by Chucker so it can open the HTTP inspector.
  static GlobalKey<NavigatorState>? get navigatorKey =>
      kDebugMode ? ChuckerFlutter.navigatorKey : null;

  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static ThemeData light({required String languageCode}) {
    final code = AppLanguage.normalize(languageCode);
    final textTheme = AppFonts.textTheme(code).apply(
      bodyColor: AppColors.onBackground,
      displayColor: AppColors.onBackground,
    );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.background,
      brightness: Brightness.dark,
    ).copyWith(
      surface: AppColors.background,
      onSurface: AppColors.onBackground,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      hintColor: AppColors.hint,
      dividerColor: AppColors.onBackground.withValues(alpha: 0.24),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.onBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      iconTheme: const IconThemeData(color: AppColors.onBackground),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.onBackground,
        textColor: AppColors.onBackground,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.background,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.background,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: AppColors.hint),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.hint),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.onBackground),
        ),
      ),
    );
  }

  static Locale localeFromLanguageCode(String languageCode) {
    return AppLanguage.isArabic(languageCode)
        ? const Locale(AppLanguage.arabic)
        : const Locale(AppLanguage.english);
  }
}
