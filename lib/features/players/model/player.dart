class Player {
  final String id;
  final String name;
  final int rating;

  /// индекс команды (A = 0, B = 1, C = 2 ...)
  /// null — если игрок пока не в команде
  final int? teamIndex;

  const Player({
    required this.id,
    required this.name,
    required this.rating,
    this.teamIndex,
  });

  Player copyWith({
    String? id,
    String? name,
    int? rating,
    int? teamIndex,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      rating: rating ?? this.rating,
      teamIndex: teamIndex ?? this.teamIndex,
    );
  }
}