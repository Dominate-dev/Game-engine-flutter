import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/games/domain/entities/game_player.dart';
import '../../features/games/domain/entities/game_result_player.dart';
import '../../l10n/play_game_strings.dart';

/// Shown when this device's own player is the `GameOver` winner.
///
/// Real `GameOver.gameResultPlayers` payloads leave `playerName` /
/// `profileImageUrl` empty, so display identity ([winner], [me], [opponent])
/// comes from the roster (`GameSessionState.me` / `.opponent` /
/// `.winnerPlayer`), never from `GameResultPlayer`. Points/coins/xp
/// ([meResult] / [opponentResult]) are unchanged — still the resolved
/// `GameResultPlayer` rows (`GameSessionState.myResult` / `.opponentResult`).
/// Every field is nullable and falls back to empty/zero rather than
/// crashing or showing stale data.
class WinDialog extends ConsumerWidget {
  const WinDialog({
    super.key,
    this.winner,
    this.me,
    this.opponent,
    this.meResult,
    this.opponentResult,
  });

  /// The actual `GameOver.winnerId` player, resolved against the roster —
  /// the caller already falls this back to [me] when it cannot be resolved
  /// (no gameOver / no winnerId / neither seated player matches).
  final GamePlayer? winner;
  final GamePlayer? me;
  final GamePlayer? opponent;
  final GameResultPlayer? meResult;
  final GameResultPlayer? opponentResult;

  static const _dividerColor = Color(0x7EECEAEA);
  static const _secondaryTextColor = Color(0xFF454545);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(playGameStringsProvider);

    return GameDialog(
      insetPadding: EdgeInsets.zero,
      // Fixed max width (not tied to MediaQuery/screen size) so the
      // dialog renders identically on phones and tablets alike — only
      // extremely narrow screens shrink it down to avoid overflow.
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                const Positioned(
                  top: -150,
                  child: AppLottieView.claimRewards(size: 400),
                ),
                _cardUi(context, ref, strings),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardUi(BuildContext context, WidgetRef ref, PlayGameStrings strings) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        GameDialogCard(
          margin: const EdgeInsets.only(top: 100),
          contentPadding: const EdgeInsets.fromLTRB(16, 32, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _winnerUi(strings),
              const SizedBox(height: 10),
              Container(height: 1, color: _dividerColor),
              const SizedBox(height: 10),
              _resultUi(strings),
              const SizedBox(height: 10),
              Container(height: 1, color: _dividerColor),
              const SizedBox(height: 10),
              _rewardsUi(strings),
              const SizedBox(height: 20),
              GameButton(
                label: strings.collectRewards,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Positioned(
          top: -46,
          child: AppImageView(
            assetPath: AppAssets.starsWinIcon,
            package: AppAssets.packageName,
            width: 140,
            height: 71,
            fit: BoxFit.contain,
          ),
        ),
        _ribbonUi(strings),
      ],
    );
  }

  Widget _ribbonUi(PlayGameStrings strings) {
    return Positioned(
      top: 26,
      left: -14,
      right: -14,
      child: AspectRatio(
        aspectRatio: 351 / 118,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const AppImageView(
              assetPath: AppAssets.winRibbon,
              package: AppAssets.packageName,
              fit: BoxFit.fill,
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: AppTextView(
                strings.winTitle,
                fontWeight: AppFontWeight.medium,
                fontSize: 16,
                color: Colors.white,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _winnerUi(PlayGameStrings strings) {
    final winnerName = winner?.playerName ?? '';

    return Column(
      children: [
        AppImageView(
          imageUrl: winner?.profileImageUrl,
          assetPath: AppAssets.defaultAvatar,
          package: AppAssets.packageName,
          size: 65,
          isCircle: true,
          fit: BoxFit.cover,
        ),
        const SizedBox(height: 8),
        AppTextView(
          winnerName,
          fontWeight: AppFontWeight.bold,
          fontSize: 12,
          color: Colors.black,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 5),
        AppTextView(
          strings.winMessage,
          fontWeight: AppFontWeight.bold,
          fontSize: 16,
          color: AppColors.purple,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _resultUi(PlayGameStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextView(
          strings.result,
          fontWeight: AppFontWeight.regular,
          fontSize: 14,
          color: Colors.black,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        _resultRowUi(me?.playerName ?? '', _displayPoints(meResult)),
        const SizedBox(height: 6),
        _resultRowUi(opponent?.playerName ?? '', _displayPoints(opponentResult)),
      ],
    );
  }

  // A negative points value (server-side penalties can push a player below
  // zero) has nothing meaningful to show here — floor it at 0.
  int _displayPoints(GameResultPlayer? result) {
    final points = result?.points ?? 0;
    return points < 0 ? 0 : points;
  }

  // Forced LTR regardless of the app's ambient locale/Directionality
  // (MaterialApp.locale flips it for Arabic): the player's name always
  // reads on the left with their points on the right, matching the native
  // layout, which does not mirror this row.
  Widget _resultRowUi(String name, int points) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          Expanded(
            child: AppTextView(
              name,
              fontWeight: AppFontWeight.bold,
              fontSize: 11,
              color: _secondaryTextColor,
              textAlign: TextAlign.left,
            ),
          ),
          const SizedBox(width: 8),
          AppNumberTextView(
            '$points',
            fontSize: 11,
            color: Colors.black,
          ),
        ],
      ),
    );
  }

  Widget _rewardsUi(PlayGameStrings strings) {
    final coins = meResult?.winningCoins ?? 0;
    final xp = meResult?.winningXp ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextView(
          strings.rewards,
          fontWeight: AppFontWeight.regular,
          fontSize: 14,
          color: Colors.black,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AppImageView(
              assetPath: AppAssets.coinIcon,
              package: AppAssets.packageName,
              size: 20,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 6),
            const AppTextView(
              '+',
              fontWeight: AppFontWeight.bold,
              fontSize: 11,
              color: _secondaryTextColor,
            ),
            AppNumberTextView(
              '$coins',
              fontSize: 11,
              color: _secondaryTextColor,
            ),
            const SizedBox(width: 20),
            const AppImageView(
              assetPath: AppAssets.xpIcon,
              package: AppAssets.packageName,
              size: 20,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 6),
            const AppTextView(
              '+',
              fontWeight: AppFontWeight.bold,
              fontSize: 11,
              color: _secondaryTextColor,
            ),
            AppNumberTextView(
              '$xp',
              fontSize: 11,
              color: _secondaryTextColor,
            ),
            const SizedBox(width: 4),
            const AppTextView(
              'xp',
              fontWeight: AppFontWeight.bold,
              fontSize: 11,
              color: _secondaryTextColor,
            ),
          ],
        ),
      ],
    );
  }
}
