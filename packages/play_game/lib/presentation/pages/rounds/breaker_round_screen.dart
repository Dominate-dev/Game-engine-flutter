import 'package:flutter/widgets.dart';

import 'comeback_style_round_content.dart';

/// Breaker (round 5) — confirmed to share Comeback's exact game flow and
/// answering behavior: both players may answer simultaneously, gated only
/// by each player's own `makeupTryCount`/`maxMakeupTryCount`, never by
/// `currentTurn`. The native reference describes Breaker as "almost the
/// same screen" as Comeback with a different intro; that intro is already
/// handled by the existing shared round-intro machinery (its own
/// `AppLottieView.breaker` asset and `breakerRoundHeading` string), and the
/// heading here is derived from the live session phase via
/// [ComebackStyleRoundContent], so nothing Breaker-specific needs
/// reimplementing.
class BreakerRoundScreen extends StatelessWidget {
  const BreakerRoundScreen({super.key});

  @override
  Widget build(BuildContext context) => const ComebackStyleRoundContent();
}
