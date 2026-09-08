import 'package:flutter/material.dart';

import 'round_report_button.dart';

/// Row pairing a leading widget (attempts info / pass button, etc.) with
/// the shared [RoundReportButton] on the trailing side.
class RoundActionsRow extends StatelessWidget {
  const RoundActionsRow({super.key, required this.leading});

  final Widget leading;

  /// Most of the row the report button may ever occupy.
  ///
  /// It is a cap, not a width: below it the button is untouched, so at normal
  /// text scale — where it needs roughly a third of the row — the layout is
  /// exactly what it always was, natural width and flush against the trailing
  /// edge. The cap only bites at large text scales, where the button's
  /// intrinsic width grew to 78% of the row and left the leading content less
  /// than its own minimum.
  static const _maxReportButtonFraction = 0.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: leading),
            const SizedBox(width: 8),
            // A Row lays its non-flex children out with an unbounded main
            // axis, so the button previously took its full intrinsic width
            // however little was left for `leading`. Bounding it here is what
            // lets the button's own label ellipsize; making the button
            // flexible instead would have left a gap at the trailing edge at
            // normal sizes, which is not the design.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * _maxReportButtonFraction,
              ),
              child: const RoundReportButton(),
            ),
          ],
        );
      },
    );
  }
}
