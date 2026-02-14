import 'match_event.dart';

class MatchGame {
  /// uuid из Supabase (строкой)
  final String id;

  final int round;

  /// индексы команд (0..n-1) для UI
  final int homeIndex;
  final int awayIndex;

  /// uuid команд в Supabase (строкой)
  final String homeTeamId;
  final String awayTeamId;

  int homeScore;
  int awayScore;
  bool finished;

  List<MatchEvent> events;

  MatchGame({
    required this.id,
    required this.round,
    required this.homeIndex,
    required this.awayIndex,
    required this.homeTeamId,
    required this.awayTeamId,
    this.homeScore = 0,
    this.awayScore = 0,
    this.finished = false,
    List<MatchEvent>? events,
  }) : events = events ?? [];
}
