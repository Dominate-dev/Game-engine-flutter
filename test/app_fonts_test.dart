import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coreapp/coreapp.dart';

void main() {
  group('AppFonts.familyFor', () {
    test('medium uses EnMedium for English and ArMedium for Arabic', () {
      expect(
        AppFonts.familyFor(
          languageCode: 'en',
          weight: AppFontWeight.medium,
        ),
        AppFontFamily.enMedium,
      );
      expect(
        AppFonts.familyFor(
          languageCode: 'ar',
          weight: AppFontWeight.medium,
        ),
        AppFontFamily.arMedium,
      );
    });

    test('light / regular / bold follow language', () {
      expect(
        AppFonts.familyFor(
          languageCode: 'en',
          weight: AppFontWeight.light,
        ),
        AppFontFamily.enLight,
      );
      expect(
        AppFonts.familyFor(
          languageCode: 'ar',
          weight: AppFontWeight.light,
        ),
        AppFontFamily.arLight,
      );
      expect(
        AppFonts.familyFor(
          languageCode: 'en',
          weight: AppFontWeight.bold,
        ),
        AppFontFamily.enBold,
      );
      expect(
        AppFonts.familyFor(
          languageCode: 'ar',
          weight: AppFontWeight.bold,
        ),
        AppFontFamily.arBold,
      );
    });

    test('semiBold uses EnMedium when English (no EN semi-bold file)', () {
      expect(
        AppFonts.familyFor(
          languageCode: 'en',
          weight: AppFontWeight.semiBold,
        ),
        AppFontFamily.enMedium,
      );
      expect(
        AppFonts.familyFor(
          languageCode: 'ar',
          weight: AppFontWeight.semiBold,
        ),
        AppFontFamily.arSemiBold,
      );
    });

    test('style pins w400 so theme weight cannot replace the family file', () {
      final style = AppFonts.style(
        languageCode: 'en',
        weight: AppFontWeight.bold,
        fontSize: 16,
      );
      expect(style.fontFamily, 'packages/coreapp/${AppFontFamily.enBold}');
      expect(style.fontWeight, FontWeight.w400);
    });

    test('enBold / arBold ignore language', () {
      expect(
        AppFonts.familyFor(
          languageCode: 'ar',
          weight: AppFontWeight.enBold,
        ),
        AppFontFamily.enBold,
      );
      expect(
        AppFonts.familyFor(
          languageCode: 'en',
          weight: AppFontWeight.arBold,
        ),
        AppFontFamily.arBold,
      );
    });

    test('number uses Numbers for both languages', () {
      expect(
        AppFonts.familyFor(
          languageCode: 'en',
          weight: AppFontWeight.number,
        ),
        AppFontFamily.numbers,
      );
      expect(
        AppFonts.familyFor(
          languageCode: 'ar',
          weight: AppFontWeight.number,
        ),
        AppFontFamily.numbers,
      );
    });
  });
}
