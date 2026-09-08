/// Auction `auctionGameMetadata.phase` — 1 bidding, 2 answering.
///
/// [fromId] returns `null` for anything else: an unrecognised phase is left
/// unresolved rather than guessed, the same rule [TypePenalty] follows.
enum AuctionPhase {
  bidding(1),
  answering(2);

  const AuctionPhase(this.id);

  final int id;

  static AuctionPhase? fromId(int? id) {
    if (id == null) {
      return null;
    }
    for (final value in AuctionPhase.values) {
      if (value.id == id) {
        return value;
      }
    }
    return null;
  }
}

/// Outcome of the current auction round as announced by the server.
///
/// The subject is the player named by `PlayerWonAuctionRound` /
/// `PlayerLostAuctionRound`; this enum records the outcome only, never who it
/// belongs to, and is never derived from a penalty or a wrong count.
enum AuctionResult { none, won, lost }
