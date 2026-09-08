import '../../domain/entities/auction_game_metadata.dart';
import 'game_json.dart';

abstract final class AuctionGameMetadataModel {
  static AuctionGameMetadata fromJson(Map<String, dynamic> json) {
    return AuctionGameMetadata(
      currentBid: GameJson.integer(json, 'currentBid'),
      currentScore: GameJson.integer(json, 'currentScore'),
      latestBidder: GameJson.stringOrNull(json, 'latestBidder'),
      phase: GameJson.integer(json, 'phase'),
      answerTimeout: GameJson.integer(json, 'answerTimeout'),
      // Absent stays absent — see AuctionGameMetadata.wrongScore.
      wrongScore: GameJson.integerOrNull(json, 'wrongScore'),
    );
  }
}
