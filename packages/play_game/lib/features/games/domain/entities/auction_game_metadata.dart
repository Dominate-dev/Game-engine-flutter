import 'package:equatable/equatable.dart';

class AuctionGameMetadata extends Equatable {
  const AuctionGameMetadata({
    required this.currentBid,
    required this.currentScore,
    required this.phase,
    required this.answerTimeout,
    this.latestBidder,
    this.wrongScore,
  });

  final int currentBid;
  final int currentScore;
  final String? latestBidder;
  final int phase;
  final int answerTimeout;

  // Wrong answers so far in the answer phase.
  // Nullable on purpose: a payload that omits it must leave the value already
  // held from `AuctionAnswerPhaseScoreUpdate` alone, rather than reset it to 0.
  final int? wrongScore;

  @override
  List<Object?> get props => [
        currentBid,
        currentScore,
        latestBidder,
        phase,
        answerTimeout,
        wrongScore,
      ];
}
