import 'package:coreapp/coreapp.dart';
import 'package:flutter/material.dart';

import 'lobby_player_card.dart';

class LobbyPlayersRow extends StatelessWidget {
  const LobbyPlayersRow({
    super.key,
    required this.userName,
    required this.opponentName,
    required this.userHint,
    required this.opponentHint,
    this.userImageUrl,
    this.opponentImageUrl,
    this.showUserAvatar = true,
    this.showOpponentAvatar = true,
    this.timerSeconds = 10,
    this.showUserTimer = true,
    this.showOpponentTimer = true,
    this.userEmoteUrl,
    this.opponentEmoteUrl,
    this.opponentCardPulse = 0,
    this.onUserAvatarTap,
    this.onOpponentAvatarTap,
  });

  static const vsSize = 100.0;
  static const cardGap = 12.0;

  final String userName;
  final String opponentName;
  final String userHint;
  final String opponentHint;
  final String? userImageUrl;
  final String? opponentImageUrl;
  final bool showUserAvatar;
  final bool showOpponentAvatar;
  final int timerSeconds;
  final bool showUserTimer;
  final bool showOpponentTimer;
  final String? userEmoteUrl;
  final String? opponentEmoteUrl;
  final int opponentCardPulse;
  final VoidCallback? onUserAvatarTap;
  final VoidCallback? onOpponentAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        IntrinsicHeight(
          child: Row(
            textDirection: TextDirection.ltr,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: LobbyPlayerCard(
                    name: userName,
                    hint: userHint,
                    alignLeft: true,
                    timerSeconds: timerSeconds,
                    showTimer: showUserTimer,
                    imageUrl: userImageUrl,
                    emoteUrl: userEmoteUrl,
                    showAvatar: showUserAvatar,
                    onAvatarTap: onUserAvatarTap,
                  ),
                ),
              ),
              const SizedBox(width: cardGap),
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: _maybeThrob(
                    pulse: opponentCardPulse,
                    child: LobbyPlayerCard(
                      name: opponentName,
                      hint: opponentHint,
                      alignLeft: false,
                      timerSeconds: timerSeconds,
                      showTimer: showOpponentTimer,
                      imageUrl: opponentImageUrl,
                      emoteUrl: opponentEmoteUrl,
                      showAvatar: showOpponentAvatar,
                      onAvatarTap: onOpponentAvatarTap,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const _LobbyVsBadge(),
      ],
    );
  }

  static Widget _maybeThrob({required int pulse, required Widget child}) {
    if (pulse <= 0) {
      return child;
    }
    return AppThrob(
      key: ValueKey(pulse),
      count: 2,
      child: child,
    );
  }
}

class _LobbyVsBadge extends StatefulWidget {
  const _LobbyVsBadge();

  @override
  State<_LobbyVsBadge> createState() => _LobbyVsBadgeState();
}

class _LobbyVsBadgeState extends State<_LobbyVsBadge>
    with SingleTickerProviderStateMixin {
  static const _throbCount = 3;
  static const _throbDuration = Duration(milliseconds: 400);
  static const _throbScale = 1.2;

  late final AnimationController _controller;
  late final Animation<double> _scale;
  int _completedThrobs = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _throbDuration);
    _scale = Tween<double>(
      begin: 1,
      end: _throbScale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.addStatusListener(_onStatus);
    _controller.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _completedThrobs++;
      _controller.reverse();
    } else if (status == AnimationStatus.dismissed &&
        _completedThrobs < _throbCount) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ScaleTransition(
        scale: _scale,
        child: const AppImageView(
          assetPath: AppAssets.vsBadge,
          package: AppAssets.packageName,
          size: LobbyPlayersRow.vsSize,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
