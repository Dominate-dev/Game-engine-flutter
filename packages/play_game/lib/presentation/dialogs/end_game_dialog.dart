import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/play_game_strings.dart';

class EndGameDialog extends ConsumerWidget {
  const EndGameDialog({super.key});

  static const _textColor = Color(0xFF454545);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(playGameStringsProvider);

    return GameDialog(
      child: GameDialogCard(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextView(
              strings.theGameIsOver,
              fontWeight: AppFontWeight.bold,
              fontSize: 14,
              color: _textColor,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GameButton(
              label: strings.back,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
