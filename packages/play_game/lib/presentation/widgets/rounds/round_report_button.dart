import 'dart:async';

import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/play_game_strings.dart';
import '../../../features/games/data/models/created_game_model.dart';
import '../../game_controller/game_controller.dart';

class RoundReportButton extends ConsumerWidget {
  const RoundReportButton({super.key, this.onTap});

  static const _reportEmail = 'naser.b@dominate.dev';

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(playGameStringsProvider);

    return GestureDetector(
      onTap: onTap ??
          () {
            final session = ref.read(gameControllerProvider);
            final questionId = CreatedGameModel.reportQuestionId(
              game: session.game,
              data: session.data,
            );
            final subject = strings.reportEmailSubject(
              questionId?.toString() ?? '',
            );
            unawaited(
              AppEmail.openEmail(_reportEmail, subject: subject),
            );
          },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.blue, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppImageView(
              assetPath: AppAssets.warningIcon,
              package: AppAssets.packageName,
              size: 18,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 5),
            // The row still sizes to its content (mainAxisSize.min) and the
            // label is laid out unbounded wherever this button is given room
            // — the Align call sites in Bell and Auction — so nothing changes
            // there. Only when a caller hands it a bounded width, which
            // RoundActionsRow now does, can the label give way instead of
            // pushing the button past what the row can afford.
            Flexible(
              child: AppTextView(
                strings.report,
                fontWeight: AppFontWeight.enExtraBold,
                fontSize: 14,
                color: AppColors.blue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
