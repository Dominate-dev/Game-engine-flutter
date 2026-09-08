import 'package:equatable/equatable.dart';

import 'advs.dart';
import 'auction_game_metadata.dart';
import 'current_question.dart';
import 'game_player.dart';

class CreatedGame extends Equatable {
  const CreatedGame({
    required this.id,
    required this.status,
    required this.mode,
    required this.currentTimerValue,
    required this.groupId,
    required this.isPrivate,
    required this.showInterests,
    required this.multipleInterests,
    required this.type,
    this.players,
    this.currentQuestion,
    this.winnerId,
    this.gameCode,
    this.auctionGameMetadata,
    this.currentTurn,
    this.isTimerStarted,
    this.waitingToBeReadyTimerStart = false,
    this.waitingToBeReadyTimerValue,
    this.beforeMatchAdv,
    this.tournmentGameName,
    this.isAllInOne,
  });

  final String id;
  final int status;
  final int mode;
  final double currentTimerValue;
  final String groupId;
  final List<GamePlayer>? players;
  final CurrentQuestion? currentQuestion;
  final bool isPrivate;
  final String? winnerId;
  final bool showInterests;
  final bool multipleInterests;
  final int type;
  final String? gameCode;
  final AuctionGameMetadata? auctionGameMetadata;
  // Hub sentinel: currentTurn names one player, or ALLOW_ALL for both.
  static const allowAllTurn = 'ALLOW_ALL';

  final String? currentTurn;
  final bool? isTimerStarted;
  final bool? waitingToBeReadyTimerStart;
  final int? waitingToBeReadyTimerValue;
  final Advs? beforeMatchAdv;
  final String? tournmentGameName;
  final bool? isAllInOne;

  GamePlayer? playerById(String id) {
    final list = players;
    if (list == null) {
      return null;
    }
    for (final player in list) {
      if (player.matchesHubUserId(id)) {
        return player;
      }
    }
    return null;
  }

  GamePlayer? selfFor(String userId) {
    if (userId.isNotEmpty) {
      return playerById(userId);
    }
    final list = players;
    if (list == null || list.isEmpty) {
      return null;
    }
    return list.first;
  }

  GamePlayer? opponentFor(String userId) {
    final list = players;
    if (list == null || list.isEmpty) {
      return null;
    }
    if (userId.isNotEmpty) {
      for (final player in list) {
        if (!player.matchesHubUserId(userId)) {
          return player;
        }
      }
      return null;
    }
    return list.length > 1 ? list[1] : null;
  }

  CreatedGame withoutPlayer(String playerId) {
    final list = players;
    if (list == null) {
      return this;
    }
    return copyWith(
      players: list
          .where((player) => !player.matchesHubUserId(playerId))
          .toList(),
    );
  }

  CreatedGame copyWith({
    String? id,
    int? status,
    int? mode,
    double? currentTimerValue,
    String? groupId,
    List<GamePlayer>? players,
    CurrentQuestion? currentQuestion,
    bool? isPrivate,
    String? winnerId,
    bool? showInterests,
    bool? multipleInterests,
    int? type,
    String? gameCode,
    AuctionGameMetadata? auctionGameMetadata,
    String? currentTurn,
    bool? isTimerStarted,
    bool? waitingToBeReadyTimerStart,
    int? waitingToBeReadyTimerValue,
    Advs? beforeMatchAdv,
    String? tournmentGameName,
    bool? isAllInOne,
    bool clearCurrentQuestion = false,
    // Drops the round-scoped auction metadata with the round that ended.
    bool clearAuctionGameMetadata = false,
  }) {
    return CreatedGame(
      id: id ?? this.id,
      status: status ?? this.status,
      mode: mode ?? this.mode,
      currentTimerValue: currentTimerValue ?? this.currentTimerValue,
      groupId: groupId ?? this.groupId,
      players: players ?? this.players,
      currentQuestion: clearCurrentQuestion
          ? null
          : (currentQuestion ?? this.currentQuestion),
      isPrivate: isPrivate ?? this.isPrivate,
      winnerId: winnerId ?? this.winnerId,
      showInterests: showInterests ?? this.showInterests,
      multipleInterests: multipleInterests ?? this.multipleInterests,
      type: type ?? this.type,
      gameCode: gameCode ?? this.gameCode,
      auctionGameMetadata: clearAuctionGameMetadata
          ? null
          : (auctionGameMetadata ?? this.auctionGameMetadata),
      currentTurn: currentTurn ?? this.currentTurn,
      isTimerStarted: isTimerStarted ?? this.isTimerStarted,
      waitingToBeReadyTimerStart:
          waitingToBeReadyTimerStart ?? this.waitingToBeReadyTimerStart,
      waitingToBeReadyTimerValue:
          waitingToBeReadyTimerValue ?? this.waitingToBeReadyTimerValue,
      beforeMatchAdv: beforeMatchAdv ?? this.beforeMatchAdv,
      tournmentGameName: tournmentGameName ?? this.tournmentGameName,
      isAllInOne: isAllInOne ?? this.isAllInOne,
    );
  }

  @override
  List<Object?> get props => [id, status, currentTimerValue, currentTurn, type];
}
