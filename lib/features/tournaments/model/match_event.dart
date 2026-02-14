enum MatchEventType {
  goal,
  assist,
  ownGoal,
}

class MatchEvent {
  final MatchEventType type;
  final int teamIndex;

  final String? playerId;
  final String? playerName;

  final String? assistPlayerId;
  final String? assistPlayerName;

  MatchEvent({
    required this.type,
    required this.teamIndex,
    this.playerId,
    this.playerName,
    this.assistPlayerId,
    this.assistPlayerName,
  });

  // 🔥 ГОЛ
  factory MatchEvent.goal({
    required int teamIndex,
    required String playerId,
    required String playerName,
    String? assistPlayerId,
    String? assistPlayerName,
  }) {
    return MatchEvent(
      type: MatchEventType.goal,
      teamIndex: teamIndex,
      playerId: playerId,
      playerName: playerName,
      assistPlayerId: assistPlayerId,
      assistPlayerName: assistPlayerName,
    );
  }

  // 🔥 АССИСТ (если вдруг отдельно понадобится)
  factory MatchEvent.assist({
    required int teamIndex,
    required String playerId,
    required String playerName,
  }) {
    return MatchEvent(
      type: MatchEventType.assist,
      teamIndex: teamIndex,
      playerId: playerId,
      playerName: playerName,
    );
  }

  // 🔥 АВТОГОЛ
  factory MatchEvent.ownGoal({
    required int teamIndex,
  }) {
    return MatchEvent(
      type: MatchEventType.ownGoal,
      teamIndex: teamIndex,
    );
  }
}
