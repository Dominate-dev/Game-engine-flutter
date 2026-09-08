import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../constants/app_assets.dart';

/// Shared Lottie player. Core animations use [AppAssets.packageName] so
/// any game plugin can play them without re-bundling the JSON.
class AppLottieView extends StatelessWidget {
  const AppLottieView({
    super.key,
    required this.asset,
    this.package = AppAssets.packageName,
    this.size,
    this.width,
    this.height,
    this.repeat = true,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  });

  /// Lobby / waiting animation (`anim_lobby.json`).
  const AppLottieView.lobby({
    super.key,
    this.size = 200,
    this.width,
    this.height,
    this.repeat = true,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieLobby,
        package = AppAssets.packageName;

  /// Emoji / reactions animation (`emojis_animation.json`).
  const AppLottieView.emojis({
    super.key,
    this.size = 80,
    this.width,
    this.height,
    this.repeat = true,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieEmojis,
        package = AppAssets.packageName;

  /// Current-turn ring around a player avatar (`lottie_turn_two.json`).
  const AppLottieView.turn({
    super.key,
    this.size = 60,
    this.width,
    this.height,
    this.repeat = true,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieTurn,
        package = AppAssets.packageName;

  /// Win-dialog confetti/rewards celebration (`claim_rewards.json`).
  /// Plays once (no loop), matching the native `lottie_loop="false"`.
  const AppLottieView.claimRewards({
    super.key,
    this.size = 350,
    this.width,
    this.height,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieClaimRewards,
        package = AppAssets.packageName,
        repeat = false;

  /// Sand-clock "get ready" animation shown between rounds
  /// (`anim_round_sand_clock.json`).
  const AppLottieView.sandClock({
    super.key,
    this.size,
    this.width,
    this.height,
    this.repeat = true,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieSandClock,
        package = AppAssets.packageName;

  /// WDYK round intro (`anim_agme_what_do_you_know.json`). Plays once.
  const AppLottieView.wdyk({
    super.key,
    this.size,
    this.width,
    this.height,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieWdyk,
        package = AppAssets.packageName,
        repeat = false;

  /// Strike result (`anim_stricke.json`). Plays once.
  const AppLottieView.strike({
    super.key,
    this.size,
    this.width,
    this.height,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieStrike,
        package = AppAssets.packageName,
        repeat = false;

  /// Circular blue result (`anim_circular_blue.json`). Plays once.
  const AppLottieView.circularBlue({
    super.key,
    this.size,
    this.width,
    this.height,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieCircularBlue,
        package = AppAssets.packageName,
        repeat = false;

  /// Circular green result (`anim_circular_green.json`). Plays once.
  const AppLottieView.circularGreen({
    super.key,
    this.size,
    this.width,
    this.height,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieCircularGreen,
        package = AppAssets.packageName,
        repeat = false;

  /// Circular red result (`anim_circular_red.json`). Plays once.
  const AppLottieView.circularRed({
    super.key,
    this.size,
    this.width,
    this.height,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieCircularRed,
        package = AppAssets.packageName,
        repeat = false;

  /// Correct-answer result (`anim_correct_answer.json`). Plays once.
  const AppLottieView.correctAnswer({
    super.key,
    this.size,
    this.width,
    this.height,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieCorrectAnswer,
        package = AppAssets.packageName,
        repeat = false;

  /// Wrong-answer result (`anim_wrong_answer.json`). Plays once.
  const AppLottieView.wrongAnswer({
    super.key,
    this.size,
    this.width,
    this.height,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieWrongAnswer,
        package = AppAssets.packageName,
        repeat = false;

  /// Timer overlay (`anim_timer.json`).
  const AppLottieView.timer({
    super.key,
    this.size,
    this.width,
    this.height,
    this.repeat = true,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieTimer,
        package = AppAssets.packageName;

  /// Bell round intro (`anim_game_bell.json`). Plays once.
  const AppLottieView.bell({
    super.key,
    this.size,
    this.width,
    this.height,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieBell,
        package = AppAssets.packageName,
        repeat = false;

  /// Auction round intro (`anim_game_auction.json`). Plays once.
  const AppLottieView.auction({
    super.key,
    this.size,
    this.width,
    this.height,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieAuction,
        package = AppAssets.packageName,
        repeat = false;

  /// Tiebreaker round intro (`anim_game_breaker.json`). Plays once.
  const AppLottieView.breaker({
    super.key,
    this.size,
    this.width,
    this.height,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieBreaker,
        package = AppAssets.packageName,
        repeat = false;

  /// Comeback round intro (`anim_game_come_back.json`). Plays once.
  const AppLottieView.comeBack({
    super.key,
    this.size,
    this.width,
    this.height,
    this.animate = true,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.scale = 1,
    this.controller,
    this.onLoaded,
  })  : asset = AppAssets.lottieComeBack,
        package = AppAssets.packageName,
        repeat = false;

  final String asset;
  final String? package;
  final double? size;
  final double? width;
  final double? height;
  final bool repeat;
  final bool animate;
  final BoxFit fit;
  final Alignment alignment;

  /// Crops empty Lottie canvas by scaling inside a clipped box.
  final double scale;
  final AnimationController? controller;
  final void Function(LottieComposition composition)? onLoaded;

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;
    final lottie = Lottie.asset(
      asset,
      package: package,
      width: w,
      height: h,
      repeat: repeat,
      animate: animate,
      fit: fit,
      alignment: alignment,
      controller: controller,
      onLoaded: onLoaded,
    );
    if (scale == 1) {
      return lottie;
    }
    return SizedBox(
      width: w,
      height: h,
      child: ClipRect(
        child: Transform.scale(
          scale: scale,
          alignment: alignment,
          child: lottie,
        ),
      ),
    );
  }
}
