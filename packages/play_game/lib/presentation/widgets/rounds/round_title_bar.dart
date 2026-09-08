import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Purple round-title bar — heading centered, question count end-aligned.
///
/// The heading is laid out in the app language's own direction rather than
/// the round's. Every round root forces `Directionality.rtl` for its mirrored
/// chrome; inheriting that reordered the bidi-neutral punctuation in English
/// headings, rendering `Round: What do you know?` as
/// `?what do you know :Round`. Only the heading's text run is re-anchored —
/// the count stays end-positioned against the round's RTL, which is what puts
/// it on the correct side of the bar.
class RoundTitleBar extends ConsumerWidget {
  const RoundTitleBar({
    super.key,
    required this.heading,
    required this.count,
  });

  final String heading;
  final String count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));

    return Container(
      width: double.infinity,
      color: AppColors.purple,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Directionality(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            child: AppTextView(
              heading,
              fontWeight: AppFontWeight.bold,
              fontSize: 14,
              textAlign: TextAlign.center,
            ),
          ),
          PositionedDirectional(
            end: 16,
            child: AppNumberTextView(
              count,
              fontSize: 15,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
