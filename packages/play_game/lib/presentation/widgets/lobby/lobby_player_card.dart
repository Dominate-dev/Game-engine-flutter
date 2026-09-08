import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';

import '../emote_zoom_image.dart';

class LobbyPlayerCard extends StatelessWidget {
  const LobbyPlayerCard({
    super.key,
    required this.name,
    required this.hint,
    required this.alignLeft,
    required this.timerSeconds,
    this.showTimer = true,
    this.imageUrl,
    this.emoteUrl,
    this.showAvatar = true,
    this.onAvatarTap,
  });

  static const avatarSize = 90.0;
  static const emoteSize = 80.0;
  static const nameFontSize = 12.0;
  static const timerFontSize = 12.0;
  static const hintFontSize = 8.0;
  static const cardRadius = 16.0;

  final String name;
  final String hint;
  final bool alignLeft;
  final int timerSeconds;
  final bool showTimer;
  final String? imageUrl;
  final String? emoteUrl;
  final bool showAvatar;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final textAlign = alignLeft ? TextAlign.left : TextAlign.right;
    final hasEmote = emoteUrl != null && emoteUrl!.isNotEmpty;

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(cardRadius),
      ),
      child: Column(
        crossAxisAlignment: alignLeft
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          // An empty seat builds no avatar at all — not even a hidden one.
          // Visibility(maintainSize:) only suppresses *painting*: the
          // default-avatar asset was still constructed and decoded behind a
          // seat that has no player, which is exactly the fallback imagery
          // the private lobby must not carry before its own game exists.
          // The reserved box is the avatar's own size, so the layout the
          // Visibility used to hold is unchanged.
          if (showAvatar)
            GestureDetector(
              onTap: onAvatarTap,
              child: AppImageView(
                imageUrl: imageUrl,
                assetPath: AppAssets.defaultAvatar,
                package: AppAssets.packageName,
                size: avatarSize,
                isCircle: true,
                fit: BoxFit.contain,
              ),
            )
          else
            const SizedBox.square(dimension: avatarSize),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: AppTextView(
              name,
              fontWeight: AppFontWeight.bold,
              fontSize: nameFontSize,
              textAlign: textAlign,
              maxLines: 2,
            ),
          ),
          const Spacer(),
          if (showTimer && timerSeconds > 0) ...[
            const SizedBox(height: 10),
            CountdownTimerText(
              seconds: timerSeconds,
              fontSize: timerFontSize,
              textAlign: textAlign,
            ),
            const SizedBox(height: 4),
            AppTextView(
              hint,
              fontWeight: AppFontWeight.light,
              fontSize: hintFontSize,
              textAlign: textAlign,
            ),
          ] else
            const SizedBox(height: 10),
        ],
      ),
    );

    if (!hasEmote) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: card,
      );
    }

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            left: 0,
            right: 0,
            bottom: -emoteSize / 2,
            child: Center(
              child: EmoteZoomImage(
                key: ValueKey(emoteUrl),
                imageUrl: emoteUrl!,
                size: emoteSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
