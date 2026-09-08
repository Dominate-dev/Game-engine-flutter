import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/game_session_state.dart';
import '../../game_controller/game_controller.dart';
import '../../pages/player_profile/player_profile_screen.dart';
import '../emote_zoom_image.dart';

/// Player avatar + turn ring + name, with an optional trailing widget
/// (e.g. strikes row on wdyk, answer number on auction). Tapping the
/// avatar opens [PlayerProfileScreen] unless [onTap] is provided.
///
/// [PlayerEmoted] matches native: sticker is larger than the avatar and
/// centered on the avatar's bottom edge so it laps the photo and the name.
class RoundPlayerAvatar extends ConsumerWidget {
  const RoundPlayerAvatar({
    super.key,
    required this.name,
    required this.isTurn,
    this.imageUrl,
    this.playerId,
    this.isLocalUser = false,
    this.trailing,
    this.flipTrailing = false,
    this.trailingSpacing = 10,
    this.onTap,
  });

  static const avatarSize = 65.0;
  static const emoteSize = 85.0;

  final String name;
  final bool isTurn;
  final String? imageUrl;
  final String? playerId;
  final bool isLocalUser;
  final Widget? trailing;
  final bool flipTrailing;
  final double trailingSpacing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(gameControllerProvider);
    final id = _resolvedPlayerId(ref);
    final emoteUrl = AppUrl.httpOrNull(
      isLocalUser ? session.meEmote?.imageUrl : session.opponentEmote?.imageUrl,
    );
    final hasEmote = emoteUrl != null && emoteUrl.isNotEmpty;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Column(
          children: [
            GestureDetector(
              onTap: onTap ?? () => _openProfile(context, ref, session, id),
              child: SizedBox(
                width: avatarSize,
                height: avatarSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: isTurn ? 1 : 0.3,
                      child: AppImageView(
                        imageUrl: AppUrl.httpOrNull(imageUrl),
                        assetPath: AppAssets.defaultAvatar,
                        package: AppAssets.packageName,
                        size: avatarSize,
                        isCircle: true,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if (isTurn)
                      IgnorePointer(
                        child: Transform.scale(
                          scale: 1.2,
                          child: const AppLottieView.turn(
                            size: avatarSize,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            AppTextView(
              name,
              fontWeight: AppFontWeight.bold,
              fontSize: 12,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (trailing != null) ...[
              SizedBox(height: trailingSpacing),
              flipTrailing
                  ? Transform.flip(flipX: true, child: trailing)
                  : trailing!,
            ],
          ],
        ),
        if (hasEmote)
          Positioned(
            top: avatarSize - emoteSize / 2,
            left: 0,
            right: 0,
            child: Center(
              child: IgnorePointer(
                child: EmoteZoomImage(
                  key: ValueKey(emoteUrl),
                  imageUrl: emoteUrl,
                  size: emoteSize,
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _resolvedPlayerId(WidgetRef ref) {
    final explicit = playerId?.trim() ?? '';
    if (explicit.isNotEmpty) {
      return explicit;
    }
    final session = ref.read(gameControllerProvider);
    if (isLocalUser) {
      return session.me?.userId ?? session.me?.id ?? _prefsUserId(ref);
    }
    return session.opponent?.userId ??
        session.opponent?.id ??
        session.game?.opponentFor(_prefsUserId(ref))?.id ??
        '';
  }

  String _prefsUserId(WidgetRef ref) {
    final userId = ref.read(sharedPrefsProvider).getUserId();
    return userId == 0 ? '' : userId.toString();
  }

  void _openProfile(
    BuildContext context,
    WidgetRef ref,
    GameSessionState session,
    String id,
  ) {
    final player = isLocalUser ? session.me : session.opponent;
    if (player?.isBot ?? false) {
      return;
    }
    final parsed = int.tryParse(id);
    if (parsed == null || parsed == 0) {
      return;
    }
    PlayerProfileScreen.show(context, playerId: parsed);
  }
}
