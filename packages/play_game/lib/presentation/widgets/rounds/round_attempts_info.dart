import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/play_game_strings.dart';

class RoundAttemptsInfo extends ConsumerWidget {
  const RoundAttemptsInfo({
    super.key,
    required this.tryCount,
    required this.maxTryCount,
  });

  final int tryCount;
  final int maxTryCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(playGameStringsProvider);
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Flexible, not Expanded: with room to spare the row still
              // sizes to its content, so the label sits directly against the
              // value exactly as before. Only when the pair no longer fits —
              // a narrow phone, a long localization, or a raised text scale —
              // does the label give way and wrap, instead of overflowing the
              // row. The count keeps its natural width so it is never the
              // part that breaks.
              Flexible(
                child: AppTextView(
                  strings.numberOfAttempts,
                  fontWeight: AppFontWeight.regular,
                  fontSize: 13,
                  // Wrapping alone is not enough at the largest accessibility
                  // scales on a 320dp screen: a single word can be wider than
                  // the space left over, and a paragraph with nowhere to break
                  // still overflows its constraints. Two lines then an
                  // ellipsis bounds it in every case. Neither takes effect at
                  // normal sizes, where the label fits on one line as before.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppNumberTextView(
                '$tryCount/$maxTryCount',
                fontSize: 14,
                fontWeight: AppFontWeight.enBold,
                color: AppColors.green,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        AppTextView(
          strings.attemptsWarning(maxTryCount),
          fontWeight: AppFontWeight.regular,
          fontSize: 10,
          color: AppColors.onBackground.withValues(alpha: 0.5),
          textAlign: TextAlign.start,
        ),
      ],
    );
  }
}
