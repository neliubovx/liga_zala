class RatingFormula {
  RatingFormula._();

  // Excel-формула + MVP:
  // total_score =
  // tournaments*0.3 + wins*0.3 + draws*0.1 +
  // (goals+assists)*0.025 + (wins_4+draws_4)*0.1 + mvp_count*0.25
  static const double coefTournaments = 0.3;
  static const double coefWins = 0.3;
  static const double coefDraws = 0.1;
  static const double coefGoalAssist = 0.025;
  static const double coefFourTeam = 0.10;
  static const double coefMvp = 0.25;

  static int asInt(dynamic value) => (value as num?)?.toInt() ?? 0;

  static String asString(dynamic value) => (value ?? '').toString();

  static int goalPlusAssist(Map<String, dynamic> row) {
    return asInt(row['goals']) + asInt(row['assists']);
  }

  static double dopCoef(Map<String, dynamic> row) {
    final wins4 = asInt(row['wins_4']);
    final draws4 = asInt(row['draws_4']);
    return (wins4 + draws4) * coefFourTeam;
  }

  static double totalScore(Map<String, dynamic> row) {
    final tournaments = asInt(row['tournaments']);
    final wins = asInt(row['wins']);
    final draws = asInt(row['draws']);
    final gpa = goalPlusAssist(row);
    final mvp = asInt(row['mvp_count']); // если MVP не выбран, это 0

    return (tournaments * coefTournaments) +
        (wins * coefWins) +
        (draws * coefDraws) +
        (gpa * coefGoalAssist) +
        dopCoef(row) +
        (mvp * coefMvp);
  }

  static double averageScore(Map<String, dynamic> row) {
    final tournaments = asInt(row['tournaments']);
    if (tournaments <= 0) return 0;
    return totalScore(row) / tournaments;
  }

  static int compareRows(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byScore = totalScore(b).compareTo(totalScore(a));
    if (byScore != 0) return byScore;

    final byWins = asInt(b['wins']).compareTo(asInt(a['wins']));
    if (byWins != 0) return byWins;

    final byPoints = asInt(b['points']).compareTo(asInt(a['points']));
    if (byPoints != 0) return byPoints;

    return asInt(b['matches_played']).compareTo(asInt(a['matches_played']));
  }
}
