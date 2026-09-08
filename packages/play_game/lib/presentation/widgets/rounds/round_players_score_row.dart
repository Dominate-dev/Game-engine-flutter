import 'package:flutter/material.dart';

class RoundPlayersScoreRow extends StatelessWidget {
  const RoundPlayersScoreRow({
    super.key,
    required this.leftPlayer,
    required this.score,
    required this.rightPlayer,
  });

  final Widget leftPlayer;
  final Widget score;
  final Widget rightPlayer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 10, child: leftPlayer),
          Expanded(flex: 11, child: score),
          Expanded(flex: 10, child: rightPlayer),
        ],
      ),
    );
  }
}
