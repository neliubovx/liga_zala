import '../model/tournament.dart';

class TournamentRepository {
  TournamentRepository._internal();

  static final TournamentRepository instance =
      TournamentRepository._internal();

  final List<Tournament> _tournaments = [];

  List<Tournament> getAll() {
    return List.unmodifiable(_tournaments);
  }

  void add(Tournament tournament) {
    _tournaments.add(tournament);
  }

  void remove(String id) {
    _tournaments.removeWhere((t) => t.id == id);
  }
}
