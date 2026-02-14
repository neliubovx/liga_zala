import '../model/match_game.dart';

class ScheduleBuilder {
  static List<MatchGame> roundRobin4Teams({
    required int rounds,
  }) {
    final baseRounds = [
      // 1 круг
      [
        [0, 1],
        [2, 3],
        [0, 2],
        [1, 3],
        [0, 3],
        [1, 2],
      ],
      // 2 круг
      [
        [0, 3],
        [1, 2],
        [1, 3],
        [0, 2],
        [0, 1],
        [2, 3],
      ],
      // 3 круг
      [
        [0, 1],
        [2, 3],
        [0, 2],
        [1, 3],
        [0, 3],
        [1, 2],
      ],
    ];

    final List<MatchGame> matches = [];
    int matchIndex = 0;

    for (int round = 0; round < rounds; round++) {
      final pattern = baseRounds[round % baseRounds.length];

      for (final pair in pattern) {
        matches.add(
          MatchGame(
            id: 'match_$matchIndex',
            round: round + 1,
            homeIndex: pair[0],
            awayIndex: pair[1],
            // ✅ обязательные поля модели MatchGame
            homeTeamId: '',
            awayTeamId: '',
            homeScore: 0,
            awayScore: 0,
            finished: false,
          ),
        );

        matchIndex++;
      }
    }

    return matches;
  }
}
