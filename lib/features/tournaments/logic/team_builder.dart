import '../../players/model/player.dart';
import '../../players/data/players_repository.dart';
import '../ui/select_players_page.dart';

class TeamBuilder {
  static List<List<Player>> buildTeams({
    required List<Player> players,
    required int teamsCount,
    required TeamSplitMethod method,
  }) {
    final repo = PlayersRepository.instance;

    // очищаем старые teamIndex
    for (final p in players) {
      repo.assignTeam(p.id, -1);
    }

    final List<List<Player>> teams =
        List.generate(teamsCount, (_) => []);

    List<Player> workingList = List.from(players);

    switch (method) {
      case TeamSplitMethod.rating:
        workingList.sort(
            (a, b) => b.rating.compareTo(a.rating));

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
        workingList.sort(
            (a, b) => b.rating.compareTo(a.rating));

        final basketSize =
            (workingList.length / teamsCount).ceil();

        for (int b = 0; b < basketSize; b++) {
          final basket = workingList
              .skip(b * teamsCount)
              .take(teamsCount)
              .toList()
            ..shuffle();

          for (int i = 0; i < basket.length; i++) {
            final player = basket[i];
            teams[i].add(player);
            repo.assignTeam(player.id, i);
          }
        }
        break;
    }

    return teams;
  }
}
