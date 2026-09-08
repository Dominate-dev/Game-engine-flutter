import 'package:flutter/material.dart';

/// The smallest comfortable hit area for a round-screen control.
///
/// 48 covers both platform minimums at once — Android Material's 48dp and
/// iOS HIG's 44pt — so one number serves both rather than branching on
/// platform for a two-logical-pixel difference.
const double kMinTouchTarget = 48.0;

/// Grows a control's *hit area* to [kMinTouchTarget] without changing what
/// it draws.
///
/// Flutter bounds hit testing by a render box's own size, so a 20px icon can
/// only ever be tapped within those 20px however much space surrounds it —
/// the box itself has to grow. This keeps [child] at its designed size and
/// centres it inside a transparent box that is at least the minimum on both
/// axes, so the visual stays put and only the tappable region expands.
class RoundTouchTarget extends StatelessWidget {
  const RoundTouchTarget({
    super.key,
    required this.onTap,
    required this.child,
    this.alignment = Alignment.center,
  });

  final VoidCallback? onTap;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque so the transparent margin around the child is tappable too;
      // without it only the painted pixels would respond.
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: kMinTouchTarget,
          minHeight: kMinTouchTarget,
        ),
        child: Align(alignment: alignment, child: child),
      ),
    );
  }
}
