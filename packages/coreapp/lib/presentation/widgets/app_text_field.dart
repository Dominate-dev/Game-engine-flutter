import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_fonts.dart';
import '../providers/app_language_provider.dart';

// Language-aware text field. [fontWeight] selects En* or Ar* from the
// current app language, same as [AppTextView].
class AppTextField extends ConsumerWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hint,
    this.fontWeight = AppFontWeight.regular,
    this.fontSize = 16,
    this.color = AppColors.onBackground,
    this.textAlign,
    this.maxLines = 1,
    this.maxLength,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.showCursor,
    this.enableInteractiveSelection,
    this.decoration,
    this.fillColor = Colors.transparent,
    this.borderColor = AppColors.onBackground,
    this.borderRadius = AppTextField.defaultBorderRadius,
    this.borderWidth = 1,
    this.focusedBorderWidth = 1.5,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 12,
    ),
  });

  static const defaultBorderRadius = 8.0;

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hint;
  final AppFontWeight fontWeight;
  final double fontSize;
  final Color color;
  final TextAlign? textAlign;
  final int? maxLines;
  final int? maxLength;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool? showCursor;
  final bool? enableInteractiveSelection;
  final InputDecoration? decoration;
  final Color fillColor;
  final Color borderColor;
  final double borderRadius;
  final double borderWidth;
  final double focusedBorderWidth;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languageCode = ref.watch(appLanguageProvider);
    final style = AppFonts.style(
      languageCode: languageCode,
      weight: fontWeight,
      fontSize: fontSize,
      color: color,
    );
    final hintStyle = style.copyWith(
      color: color.withValues(alpha: 0.5),
    );

    final enabledBorder = _outline(borderColor, borderWidth);
    final focusedBorder = _outline(borderColor, focusedBorderWidth);
    final disabledBorder = _outline(
      borderColor.withValues(alpha: 0.4),
      borderWidth,
    );

    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: style,
        textAlign: textAlign ?? TextAlign.start,
        maxLines: obscureText ? 1 : maxLines,
        maxLength: maxLength,
        obscureText: obscureText,
        enabled: enabled,
        readOnly: readOnly,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onTap: onTap,
        showCursor: showCursor,
        enableInteractiveSelection: enableInteractiveSelection,
        cursorColor: color,
        decoration: (decoration ?? const InputDecoration()).copyWith(
          hintText: hint ?? decoration?.hintText,
          hintStyle: decoration?.hintStyle ?? hintStyle,
          contentPadding: decoration?.contentPadding ?? contentPadding,
          filled: true,
          fillColor: decoration?.fillColor ?? fillColor,
          hoverColor: Colors.transparent,
          border: decoration?.border ?? enabledBorder,
          enabledBorder: decoration?.enabledBorder ?? enabledBorder,
          focusedBorder: decoration?.focusedBorder ?? focusedBorder,
          disabledBorder: decoration?.disabledBorder ?? disabledBorder,
        ),
      ),
    );
  }

  OutlineInputBorder _outline(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
