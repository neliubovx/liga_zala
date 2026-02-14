import 'package:supabase_flutter/supabase_flutter.dart';

class TournamentService {
  final supabase = Supabase.instance.client;

  Future<String> createTournament({
    required String hallId,
    required int teamsCount,
    required int rounds,
  }) async {
    final response = await supabase
        .from('tournaments')
        .insert({
          'hall_id': hallId,
          'teams_count': teamsCount,
          'rounds': rounds,
        })
        .select()
        .single();

    return response['id'];
  }

  Future<void> createMatches({
    required String tournamentId,
    required List<Map<String, dynamic>> matches,
  }) async {
    final data = matches.map((m) {
      return {
        'tournament_id': tournamentId,
        'round': m['round'],
        'home_team': m['home_team'],
        'away_team': m['away_team'],
      };
    }).toList();

    await supabase.from('matches').insert(data);
  }
}
