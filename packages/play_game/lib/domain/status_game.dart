// Mirrors native `StatusGameEnum`.
enum StatusGame {
  waitingPlayers(1),
  isReady(2),
  inProgress(3),
  ended(4);

  const StatusGame(this.id);

  final int id;

  static StatusGame? fromId(int? id) {
    if (id == null) {
      return null;
    }
    for (final value in StatusGame.values) {
      if (value.id == id) {
        return value;
      }
    }
    return null;
  }
}
