import 'package:equatable/equatable.dart';

class GamePlayer extends Equatable {
  const GamePlayer({
    required this.id,
    required this.playerName,
    required this.penalty,
    required this.points,
    required this.isReady,
    required this.makeupTryCount,
    required this.maxMakeupTryCount,
    this.userId,
    this.profileImageUrl,
    this.passes = 0,
    this.isBot = false,
  });

  final String id;
  // Account id when the hub sends both `id` (often a GUID) and `userId`.
  final String? userId;
  final String playerName;
  final String? profileImageUrl;
  final int penalty;
  final int points;
  final int passes;
  final bool isReady;
  final int makeupTryCount;
  final int maxMakeupTryCount;
  final bool isBot;

  // Hub `PlayerEmoted.userId` / prefs `user_id` vs this player's ids.
  bool matchesHubUserId(String? hubUserId) {
    if (playerIdsEqual(id, hubUserId)) {
      return true;
    }
    return playerIdsEqual(userId, hubUserId);
  }

  GamePlayer copyWith({
    String? id,
    String? userId,
    String? playerName,
    String? profileImageUrl,
    int? penalty,
    int? points,
    int? passes,
    bool? isReady,
    int? makeupTryCount,
    int? maxMakeupTryCount,
    bool? isBot,
  }) {
    return GamePlayer(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      playerName: playerName ?? this.playerName,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      penalty: penalty ?? this.penalty,
      points: points ?? this.points,
      passes: passes ?? this.passes,
      isReady: isReady ?? this.isReady,
      makeupTryCount: makeupTryCount ?? this.makeupTryCount,
      maxMakeupTryCount: maxMakeupTryCount ?? this.maxMakeupTryCount,
      isBot: isBot ?? this.isBot,
    );
  }

  @override
  List<Object?> get props => [id, userId];
}

// Hub / prefs ids (`47` vs `"47"`).
bool playerIdsEqual(String? left, String? right) {
  final a = left?.trim() ?? '';
  final b = right?.trim() ?? '';
  if (a.isEmpty || b.isEmpty) {
    return false;
  }
  if (a == b) {
    return true;
  }
  final aInt = int.tryParse(a);
  final bInt = int.tryParse(b);
  return aInt != null && aInt == bInt;
}
