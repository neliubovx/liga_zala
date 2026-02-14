import 'match_game.dart';
import '../../players/model/player.dart';

class Tournament {
  final String id;
  final DateTime date;
  final int teamsCount;
  final int playersPerTeam;
  final int rounds;

  final List<List<Player>> teams;
  final List<MatchGame> matches;

  bool manuallyCompleted;

  // ✅ Новый флаг — чтобы не добавлять турнир 100 раз
  bool savedToHistory;

  Tournament({
    required this.id,
    required this.date,
    required this.teamsCount,
    required this.playersPerTeam,
    required this.rounds,
    required this.teams,
    required this.matches,
    this.manuallyCompleted = false,
    this.savedToHistory = false,
  });

  /// Автоматически завершён,
  /// если все матчи сыграны
  bool get autoCompleted =>
      matches.isNotEmpty &&
      matches.every((m) => m.finished);

  /// Итоговое состояние турнира
  bool get isCompleted =>
      manuallyCompleted || autoCompleted;
}
