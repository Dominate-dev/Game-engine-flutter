import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelectableChip extends StatelessWidget {
  const SelectableChip({
    super.key,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple : AppColors.answerChip,
          borderRadius: BorderRadius.circular(50),
          border: selected
              ? null
              : Border.all(color: AppColors.onBackground, width: 1),
        ),
        child: AppTextView(
          text,
          fontWeight: AppFontWeight.bold,
          fontSize: 12,
          textAlign: TextAlign.start,
        ),
      ),
    );
  }
}

class SelectableChipsBox extends ConsumerWidget {
  const SelectableChipsBox({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> items;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArabic = AppLanguage.isArabic(ref.watch(appLanguageProvider));

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 130),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.purple, width: 2),
      ),
      child: Directionality(
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            for (var i = 0; i < items.length; i++)
              SelectableChip(
                text: items[i],
                selected: selectedIndex == i,
                // The click lands on the tap itself, before whatever guard
                // the round applies to the submission. One place, so every
                // round gets it once and none of them can double it.
                onTap: () {
                  unawaited(ref.read(audioServiceProvider).playAnswerClick());
                  onSelected(i);
                },
              ),
          ],
        ),
      ),
    );
  }
}
