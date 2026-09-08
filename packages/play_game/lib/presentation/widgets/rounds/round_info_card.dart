import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bordered info card used for the question title (wdyk/auction/bell) and
/// the person name (comeback/breaker) — identical layout either way.
///
/// The text is server-provided, so it is laid out in the app language's own
/// direction rather than the round's. Every round root forces
/// `Directionality.rtl` for its mirrored chrome; inheriting that put English
/// trailing punctuation on the wrong side (`what do you know?` rendering as
/// `?what do you know`). This is the same rule [SelectableChipsBox] already
/// applies to the answer chips, and it resolves the language from the same
/// canonical source.
class RoundInfoCard extends ConsumerWidget {
  const RoundInfoCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 25),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.blue, width: 2),
      ),
      child: Directionality(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: AppTextView(
          text,
          fontWeight: AppFontWeight.bold,
          fontSize: 13,
          textAlign: TextAlign.start,
        ),
      ),
    );
  }
}
