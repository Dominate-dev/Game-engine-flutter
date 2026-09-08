import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../constants/app_language.dart';
import '../providers/app_language_provider.dart';
import 'app_throb.dart';

class GameDialog extends ConsumerWidget {
  const GameDialog({
    super.key,
    required this.child,
    this.insetPadding = const EdgeInsets.symmetric(horizontal: 24),
  });

  final Widget child;
  final EdgeInsets insetPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: insetPadding,
      child: Directionality(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AppThrob(child: child),
      ),
    );
  }
}

// Shared gradient-bordered white card used inside every [GameDialog] —
// mirrors the Android `@drawable/border_dialog` background.
class GameDialogCard extends StatelessWidget {
  const GameDialogCard({
    super.key,
    required this.child,
    this.margin,
    this.borderWidth = 6,
    this.borderRadius = 20,
    this.innerBorderRadius = 16,
    this.contentPadding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets? margin;
  final double borderWidth;
  final double borderRadius;
  final double innerBorderRadius;
  final EdgeInsets contentPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: EdgeInsets.all(borderWidth),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFAF78F6), Color(0xFF5730F1)],
        ),
      ),
      child: Container(
        padding: contentPadding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(innerBorderRadius),
        ),
        child: child,
      ),
    );
  }
}
