import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';

import '../../dialogs/interaction_dialog.dart';
import '../../dialogs/setting_game_dialog.dart';
import 'round_touch_target.dart';

class RoundHeaderBar extends StatelessWidget {
  const RoundHeaderBar({
    super.key,
    this.onSettingsTap,
    this.onEmojisTap,
  });

  final VoidCallback? onSettingsTap;
  final VoidCallback? onEmojisTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          // Both icons keep their designed size — 20 and 35 — and only their
          // hit areas grow to the 48 minimum. A render box is hit-tested
          // within its own bounds, so a 20px icon was a 20px target however
          // much empty space sat around it.
          RoundTouchTarget(
            alignment: AlignmentDirectional.centerStart,
            onTap: onSettingsTap ??
                () => showDialog<void>(
                      context: context,
                      builder: (_) => const SettingGameDialog(),
                    ),
            child: const AppImageView(
              assetPath: AppAssets.settingsIcon,
              package: AppAssets.packageName,
              size: 20,
              fit: BoxFit.contain,
            ),
          ),
          const Spacer(),
          RoundTouchTarget(
            alignment: AlignmentDirectional.centerEnd,
            onTap: onEmojisTap ??
                () => showDialog<void>(
                      context: context,
                      builder: (_) => const InteractionDialog(),
                    ),
            child: const AppLottieView.emojis(
              size: 35,
              fit: BoxFit.contain,
              scale: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
