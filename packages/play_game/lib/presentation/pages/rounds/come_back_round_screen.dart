import 'package:flutter/widgets.dart';

import 'comeback_style_round_content.dart';

/// Comeback (round 4) — a limited-try catch-up. The live content is
/// [ComebackStyleRoundContent], shared with [BreakerRoundScreen] (round 5),
/// which is confirmed to have the identical game flow and answering
/// behavior. Comeback is that content's source of truth; this screen is
/// deliberately kept as a thin, named entry point so routing/tests can keep
/// referring to `ComeBackRoundScreen` while the implementation lives in one
/// place.
class ComeBackRoundScreen extends StatelessWidget {
  const ComeBackRoundScreen({super.key});

  @override
  Widget build(BuildContext context) => const ComebackStyleRoundContent();
}
