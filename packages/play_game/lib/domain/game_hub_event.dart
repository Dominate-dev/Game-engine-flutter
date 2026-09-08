class GameHubEvent {
  const GameHubEvent({
    required this.name,
    this.data,
  });

  final String name;
  final Map<String, dynamic>? data;
}
