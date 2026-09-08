import 'package:equatable/equatable.dart';

import 'advs.dart';
import 'game_player.dart';
import 'game_result_player.dart';

class GameOverResult extends Equatable {
  const GameOverResult({
    required this.gameId,
    required this.isPrivate,
    required this.winnerId,
    required this.gameResultPlayers,
    this.afterMatchAdv,
    this.isTournamentMatch,
    this.nextStage,
    this.nextStageEn,
  });

  final String gameId;
  final bool isPrivate;
  final String winnerId;
  final List<GameResultPlayer> gameResultPlayers;
  final Advs? afterMatchAdv;
  final bool? isTournamentMatch;
  final String? nextStage;
  final String? nextStageEn;

  // "No winner was named" is not the same as "this user did not win".
  // Callers must check this before treating isWinner() == false as a loss.
  bool get hasKnownWinner => winnerId.trim().isNotEmpty;

  // Tolerant comparison, same as GameSessionState.winnerPlayer already uses
  // for this same winnerId — was a raw `==` that hub-vs-prefs id formatting
  // drift (see playerIdsEqual's own doc comment) could fail to match.
  bool isWinner(String? userId) {
    if (userId == null || userId.isEmpty) {
      return false;
    }
    return playerIdsEqual(winnerId, userId);
  }

  @override
  List<Object?> get props => [gameId, winnerId];
}
