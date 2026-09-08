import 'package:equatable/equatable.dart';

class GameResultPlayer extends Equatable {
  const GameResultPlayer({
    required this.playerId,
    required this.points,
    required this.strikes,
    required this.correctAnswersCount,
    required this.wrongAnswersCount,
    required this.answersSpeed,
    required this.winningCoins,
    required this.winningXp,
    this.playerName,
    this.profile,
    this.profileImageUrl,
  });

  final String playerId;
  final int points;
  final int strikes;
  final int correctAnswersCount;
  final int wrongAnswersCount;
  final double answersSpeed;
  final int winningCoins;
  final int winningXp;
  final String? playerName;

  // Server-confirmed field, distinct from [profileImageUrl]; no dialog UI
  // currently displays it, so it is parsed but otherwise unused.
  final String? profile;
  final String? profileImageUrl;

  @override
  List<Object?> get props => [playerId];
}
