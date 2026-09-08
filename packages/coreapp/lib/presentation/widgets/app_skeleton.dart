import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';

// Shimmer placeholder. Pass [size] for a square, or [width] / [height].
// With no size it fills the parent (same clip as [AppImageView]).
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    super.key,
    this.size,
    this.width,
    this.height,
    this.radius = 0,
    this.isCircle = false,
    this.baseColor,
    this.highlightColor,
  });

  final double? size;
  final double? width;
  final double? height;
  final double radius;
  final bool isCircle;
  final Color? baseColor;
  final Color? highlightColor;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1200);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width ?? widget.size;
    final height = widget.height ?? widget.size;
    final base = widget.baseColor ?? AppColors.skeleton;
    final highlight = widget.highlightColor ?? AppColors.skeletonHighlight;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.isCircle || widget.radius <= 0
                ? null
                : BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1.5 + 3 * t, 0),
              end: Alignment(-0.5 + 3 * t, 0),
              colors: [base, highlight, base],
            ),
          ),
        );
      },
    );
  }
}
