// Hub Penalty `type`.
enum TypePenalty {
  timeout(1),
  wrongAnswer(2);

  const TypePenalty(this.id);

  final int id;

  static TypePenalty? fromId(int? id) {
    if (id == null) {
      return null;
    }
    for (final value in TypePenalty.values) {
      if (value.id == id) {
        return value;
      }
    }
    return null;
  }
}
