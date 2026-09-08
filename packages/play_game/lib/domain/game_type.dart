import 'game_phase.dart';

// Mirrors native round `type` on [CreatedGame].
enum GameType {
  wdyk(1),
  auction(2),
  bell(3),
  comeBack(4),
  breaker(5);

  const GameType(this.id);

  final int id;

  GamePhase get phase => switch (this) {
        wdyk => GamePhase.wdyk,
        auction => GamePhase.auction,
        bell => GamePhase.bell,
        comeBack => GamePhase.comeBack,
        breaker => GamePhase.breaker,
      };

  static GameType? fromId(int? id) {
    if (id == null) {
      return null;
    }
    for (final value in GameType.values) {
      if (value.id == id) {
        return value;
      }
    }
    return null;
  }
}
