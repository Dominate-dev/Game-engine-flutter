import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_fonts.dart';
import 'app_icon_button.dart';
import 'app_text_view.dart';

/// Shared app bar — same building blocks as every other custom widget:
/// [AppTextView] for the title (language-aware EN/AR font via
/// [AppFontWeight]) and [AppIconButton] for the back/leading and trailing
/// actions. Drop it into `Scaffold.appBar` like a normal [AppBar].
///
/// The default [backIcon] ([Icons.arrow_back_ios_new]) has
/// `IconData.matchTextDirection` set by Flutter itself, so it auto-mirrors
/// for Arabic without any extra work here.
class AppToolbar extends StatelessWidget implements PreferredSizeWidget {
  const AppToolbar({
    super.key,
    this.title,
    this.titleWidget,
    this.titleFontWeight = AppFontWeight.semiBold,
    this.titleFontSize = AppToolbar.defaultTitleFontSize,
    this.titleColor = AppColors.onBackground,
    this.centerTitle = true,
    this.titleSpacing,
    this.showBackButton = true,
    this.backIcon = Icons.arrow_back_ios_new,
    this.onBackPressed,
    this.leading,
    this.leadingWidth,
    this.actions,
    this.actionsPadding = const EdgeInsets.only(right: 4),
    this.backgroundColor = AppColors.background,
    this.iconColor = AppColors.onBackground,
    this.iconSize = AppToolbar.defaultIconSize,
    this.elevation = 0,
    this.scrolledUnderElevation = 0,
    this.height = kToolbarHeight,
    this.bottom,
    this.systemOverlayStyle,
  }) : assert(
          title == null || titleWidget == null,
          'Provide either title or titleWidget, not both.',
        );

  static const defaultTitleFontSize = 20.0;
  static const defaultIconSize = 22.0;

  /// Plain string title — rendered with [AppTextView] using [titleFontWeight]
  /// / [titleFontSize] / [titleColor]. Ignored if [titleWidget] is set.
  final String? title;

  /// Full control over the title widget (e.g. a logo, a search field).
  final Widget? titleWidget;

  final AppFontWeight titleFontWeight;
  final double titleFontSize;
  final Color titleColor;
  final bool centerTitle;
  final double? titleSpacing;

  /// Shows an auto-mirrored back button — on by default. Tapping it pops
  /// the current screen ([Navigator.maybePop], so it's a no-op instead of
  /// throwing if there's nothing to pop) unless [onBackPressed] is set.
  /// Ignored if [leading] is provided.
  final bool showBackButton;
  final IconData backIcon;
  final VoidCallback? onBackPressed;

  /// Overrides the back button entirely (e.g. a close icon, a drawer icon).
  final Widget? leading;
  final double? leadingWidth;

  final List<Widget>? actions;
  final EdgeInsetsGeometry actionsPadding;

  final Color backgroundColor;
  final Color iconColor;
  final double iconSize;
  final double elevation;
  final double scrolledUnderElevation;

  /// Toolbar height, excluding [bottom].
  final double height;

  /// Extra row below the title — e.g. a connection-status banner or tabs.
  final PreferredSizeWidget? bottom;

  final SystemUiOverlayStyle? systemOverlayStyle;

  @override
  Size get preferredSize =>
      Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final resolvedLeading = leading ??
        (showBackButton
            ? AppIconButton(
                icon: backIcon,
                size: iconSize,
                color: iconColor,
                onPressed: onBackPressed ?? () => Navigator.of(context).maybePop(),
              )
            : null);

    final resolvedTitle = titleWidget ??
        (title == null
            ? null
            : AppTextView(
                title!,
                fontWeight: titleFontWeight,
                fontSize: titleFontSize,
                color: titleColor,
              ));

    return AppBar(
      leading: resolvedLeading,
      automaticallyImplyLeading: false,
      leadingWidth: leadingWidth,
      title: resolvedTitle,
      centerTitle: centerTitle,
      titleSpacing: titleSpacing,
      actions: actions == null
          ? null
          : [
              ...actions!,
              Padding(padding: actionsPadding),
            ],
      backgroundColor: backgroundColor,
      foregroundColor: iconColor,
      iconTheme: IconThemeData(color: iconColor, size: iconSize),
      elevation: elevation,
      scrolledUnderElevation: scrolledUnderElevation,
      toolbarHeight: height,
      systemOverlayStyle: systemOverlayStyle,
      bottom: bottom,
    );
  }
}
