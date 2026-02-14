import '../model/player.dart';

class PlayersRepository {
  PlayersRepository._internal();

  static final PlayersRepository instance =
      PlayersRepository._internal();

  final List<Player> _players = [
    Player(id: '1', name: 'Алексей', rating: 1200),
    Player(id: '2', name: 'Иван', rating: 1150),
    Player(id: '3', name: 'Дмитрий', rating: 1300),
  ];

  // 🔹 получить всех игроков (сортировка по рейтингу)
  List<Player> getAll() {
    final sorted = List<Player>.from(_players);
    sorted.sort((a, b) => b.rating.compareTo(a.rating));
    return sorted;
  }

  // 🔹 получить игроков конкретной команды
  List<Player> getByTeam(int teamIndex) {
    return _players
        .where((p) => p.teamIndex == teamIndex)
        .toList();
  }

  // 🔹 добавить игрока
  void add(Player player) {
    _players.add(player);
  }

  // 🔥 очистить команды у всех игроков (перед новым турниром)
  void clearTeams() {
    for (int i = 0; i < _players.length; i++) {
      _players[i] =
          _players[i].copyWith(teamIndex: null);
    }
  }

  // 🔥 назначить команду игроку
  void assignTeam(String playerId, int teamIndex) {
    final index =
        _players.indexWhere((p) => p.id == playerId);
    if (index == -1) return;

    _players[index] =
        _players[index].copyWith(teamIndex: teamIndex);
  }

  // 🔹 обновить рейтинг
  void updateRating(String playerId, int delta) {
    final index =
        _players.indexWhere((p) => p.id == playerId);
    if (index == -1) return;

    final player = _players[index];
    final newRating =
        (player.rating + delta).clamp(0, 99999);

    _players[index] =
        player.copyWith(rating: newRating);
  }
}
