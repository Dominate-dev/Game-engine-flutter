import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

// Shared icon button. [isHighlighter] defaults to `false` so there is no
// splash / highlight; set it `true` to restore Material ink.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = AppIconButton.defaultSize,
    this.color = AppColors.onBackground,
    this.disabledColor,
    this.tooltip,
    this.padding = const EdgeInsets.all(8),
    this.alignment = Alignment.center,
    this.constraints,
    this.splashRadius,
    this.isHighlighter = false,
    this.autofocus = false,
    this.focusNode,
    this.visualDensity,
  });

  static const defaultSize = 24.0;
  static const disabledOpacity = 0.38;

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color color;
  final Color? disabledColor;
  final String? tooltip;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;
  final BoxConstraints? constraints;
  final double? splashRadius;
  final bool isHighlighter;
  final bool autofocus;
  final FocusNode? focusNode;
  final VisualDensity? visualDensity;

  bool get _isEnabled => onPressed != null;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = _isEnabled
        ? color
        : (disabledColor ?? color.withValues(alpha: disabledOpacity));

    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      padding: padding,
      alignment: alignment,
      constraints: constraints,
      splashRadius: isHighlighter ? splashRadius : 0.0001,
      autofocus: autofocus,
      focusNode: focusNode,
      visualDensity: visualDensity,
      iconSize: size,
      color: resolvedColor,
      disabledColor: resolvedColor,
      splashColor: isHighlighter ? null : Colors.transparent,
      highlightColor: isHighlighter ? null : Colors.transparent,
      hoverColor: isHighlighter ? null : Colors.transparent,
      focusColor: isHighlighter ? null : Colors.transparent,
      style: IconButton.styleFrom(
        foregroundColor: resolvedColor,
        disabledForegroundColor: resolvedColor,
        padding: padding,
        iconSize: size,
        highlightColor: isHighlighter ? null : Colors.transparent,
        overlayColor: isHighlighter ? null : Colors.transparent,
        splashFactory:
            isHighlighter ? null : NoSplash.splashFactory,
      ),
      icon: Icon(icon, size: size, color: resolvedColor),
    );
  }
}
