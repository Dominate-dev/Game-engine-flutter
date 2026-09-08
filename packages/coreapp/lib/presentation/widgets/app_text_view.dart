import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_fonts.dart';
import '../providers/app_language_provider.dart';

// Language-aware text. [fontWeight] selects En* or Ar* from the current
// app language (`medium` + `en` → EnMedium, `medium` + `ar` → ArMedium).
class AppTextView extends ConsumerWidget {
  const AppTextView(
    this.text, {
    super.key,
    this.fontWeight = AppFontWeight.regular,
    this.fontSize,
    this.color,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.height,
    this.letterSpacing,
    this.decoration,
    this.padding,
  });

  final String text;
  final AppFontWeight fontWeight;
  final double? fontSize;
  final Color? color;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final double? height;
  final double? letterSpacing;
  final TextDecoration? decoration;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languageCode = ref.watch(appLanguageProvider);

    final textWidget = Text(
      text,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
      style: AppFonts.style(
        languageCode: languageCode,
        weight: fontWeight,
        fontSize: fontSize,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        decoration: decoration,
      ),
    );

    final resolved = padding;
    if (resolved == null) {
      return textWidget;
    }
    return Padding(padding: resolved, child: textWidget);
  }
}

// Digits — defaults to [AppFontFamily.numbers], independent of language.
// Pass [fontWeight] to use another family (e.g. [AppFontWeight.enBold]).
class AppNumberTextView extends ConsumerWidget {
  const AppNumberTextView(
    this.text, {
    super.key,
    this.fontWeight = AppFontWeight.enBold,
    this.fontSize,
    this.color,
    this.textAlign,
  });

  final String text;
  final AppFontWeight fontWeight;
  final double? fontSize;
  final Color? color;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppTextView(
      text,
      fontWeight: fontWeight,
      fontSize: fontSize,
      color: color,
      textAlign: textAlign,
    );
  }
}
