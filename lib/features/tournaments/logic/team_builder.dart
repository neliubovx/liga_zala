import '../../players/model/player.dart';
import '../../players/data/players_repository.dart';
import '../ui/select_players_page.dart';

class TeamBuilder {
  static List<List<Player>> buildTeams({
    required List<Player> players,
    required int teamsCount,
    required TeamSplitMethod method,
    Map<String, int>? basketByPlayerId,
  }) {
    final repo = PlayersRepository.instance;

    // очищаем старые teamIndex
    for (final p in players) {
      repo.assignTeam(p.id, -1);
    }

    final List<List<Player>> teams = List.generate(teamsCount, (_) => []);

    List<Player> workingList = List.from(players);

    switch (method) {
      case TeamSplitMethod.rating:
        workingList.sort((a, b) => b.rating.compareTo(a.rating));

        for (int i = 0; i < workingList.length; i++) {
          final teamIndex = i % teamsCount;
          final player = workingList[i];

          teams[teamIndex].add(player);
          repo.assignTeam(player.id, teamIndex);
        }
        break;

      case TeamSplitMethod.random:
        workingList.shuffle();

        for (int i = 0; i < workingList.length; i++) {
          final teamIndex = i % teamsCount;
          final player = workingList[i];

          teams[teamIndex].add(player);
          repo.assignTeam(player.id, teamIndex);
        }
        break;

      case TeamSplitMethod.baskets:
        _buildByBaskets(
          repo: repo,
          players: workingList,
          teams: teams,
          teamsCount: teamsCount,
          basketByPlayerId: basketByPlayerId ?? const {},
        );
        break;
    }

    return teams;
  }

  static void _buildByBaskets({
    required PlayersRepository repo,
    required List<Player> players,
    required List<List<Player>> teams,
    required int teamsCount,
    required Map<String, int> basketByPlayerId,
  }) {
    final targetSize = (players.length / teamsCount).ceil();

    final grouped = <int, List<Player>>{};
    for (final player in players) {
      final basket = basketByPlayerId[player.id] ?? 1;
      grouped.putIfAbsent(basket, () => []).add(player);
    }

    final basketIds = grouped.keys.toList()..sort();
    var leftToRight = true;

    for (final basketId in basketIds) {
      final bucket = grouped[basketId]!..shuffle();

      for (int i = 0; i < bucket.length; i++) {
        final preferred = leftToRight
            ? i % teamsCount
            : (teamsCount - 1 - (i % teamsCount));
        final teamIndex = _pickTeamIndex(teams, preferred, targetSize);
        final player = bucket[i];

        teams[teamIndex].add(player);
        repo.assignTeam(player.id, teamIndex);
      }

      leftToRight = !leftToRight;
    }
  }

  static int _pickTeamIndex(
    List<List<Player>> teams,
    int preferred,
    int targetSize,
  ) {
    if (teams[preferred].length < targetSize) return preferred;

    int minSize = 1 << 30;
    int minIndex = 0;
    for (int i = 0; i < teams.length; i++) {
      final size = teams[i].length;
      if (size < minSize) {
        minSize = size;
        minIndex = i;
      }
    }
    return minIndex;
  }
}
