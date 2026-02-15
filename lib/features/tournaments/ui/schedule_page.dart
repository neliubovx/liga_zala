import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../players/model/player.dart';
import '../model/match_game.dart';
import '../model/match_event.dart';
import 'match_dialog.dart';
import 'teams_points_line.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({
    super.key,
    required this.tournamentId,
    required this.hallId,
    required this.teamName,
    required this.teams,
  });

  final String hallId;
  final dynamic tournamentId;
  final String Function(int) teamName;

  final List<List<Player>>? teams;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final supabase = Supabase.instance.client;
  final Random _random = Random.secure();
  static final RegExp _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  bool _loading = true;
  bool _finishing = false;
  bool _isCompleted = false;
  bool _statsApplied = false;
  bool _hasStatsAppliedColumn = true;

  final List<MatchGame> _matches = [];
  final Map<int, String> _teamNames = {};
  final Map<int, List<Player>> _teamRosterByIndex = {};
  final Map<String, int> _teamIndexByUserId = {};
  final Map<String, String> _userNameById = {};
  final Map<String, String> _userIdByAppId = {};
  bool _rosterExpanded = false;

  String get _prefsKey => 'active_tournament_${widget.hallId}';

  String _teamLetter(int index) => String.fromCharCode(65 + index);

  String _teamNameOnly(int idx) {
    final name = _teamNames[idx]?.trim();
    final letter = _teamLetter(idx);
    if (name == null || name.isEmpty || name == letter) return '';
    return name;
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await _loadTournamentCompleted();
    await _loadTeamNames();
    await _loadTeamRosters();
    await _loadMatches();
    await _loadMatchEvents();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadTournamentCompleted() async {
    try {
      final row = await supabase
          .from('tournaments')
          .select('completed, stats_applied')
          .eq('id', widget.tournamentId)
          .single();

      _isCompleted = (row['completed'] as bool?) ?? false;
      _statsApplied = (row['stats_applied'] as bool?) ?? false;
      _hasStatsAppliedColumn = true;
    } catch (e) {
      if (_isMissingStatsAppliedColumnError(e)) {
        _hasStatsAppliedColumn = false;

        try {
          final row = await supabase
              .from('tournaments')
              .select('completed')
              .eq('id', widget.tournamentId)
              .single();

          _isCompleted = (row['completed'] as bool?) ?? false;
          _statsApplied = _isCompleted;
        } catch (inner) {
          debugPrint('❌ Ошибка загрузки completed: $inner');
          _isCompleted = false;
          _statsApplied = false;
        }

        return;
      }

      debugPrint('❌ Ошибка загрузки completed/stats_applied: $e');
      _isCompleted = false;
      _statsApplied = false;
    }
  }

  Future<void> _loadTeamNames() async {
    try {
      final rows = await supabase
          .from('teams')
          .select('team_index, name')
          .eq('tournament_id', widget.tournamentId);

      _teamNames.clear();
      for (final r in (rows as List)) {
        final idx = (r['team_index'] as num?)?.toInt();
        final name = (r['name'] ?? '').toString();
        if (idx != null) _teamNames[idx] = name;
      }
    } catch (e) {
      debugPrint('❌ Ошибка загрузки имен команд: $e');
    }
  }

  Future<void> _loadTeamRosters() async {
    _teamRosterByIndex.clear();
    _teamIndexByUserId.clear();
    _userNameById.clear();
    _userIdByAppId.clear();

    try {
      final teamRows = await supabase
          .from('teams')
          .select('id, team_index')
          .eq('tournament_id', widget.tournamentId);

      final teamIndexByTeamId = <String, int>{};
      for (final row in (teamRows as List).cast<Map<String, dynamic>>()) {
        final teamId = row['id']?.toString();
        final teamIndex = (row['team_index'] as num?)?.toInt();
        if (teamId == null || teamIndex == null) continue;
        teamIndexByTeamId[teamId] = teamIndex;
        _teamRosterByIndex.putIfAbsent(teamIndex, () => <Player>[]);
      }

      if (teamIndexByTeamId.isEmpty) {
        await _hydrateRosterFromLocalTeams();
        return;
      }

      final tpRows = await supabase
          .from('team_players')
          .select('team_id, player_id')
          .eq('tournament_id', widget.tournamentId);

      final playerIds = <String>{};
      final teamPlayers = (tpRows as List).cast<Map<String, dynamic>>();
      for (final row in teamPlayers) {
        final playerId = row['player_id']?.toString();
        if (playerId != null && playerId.isNotEmpty) {
          playerIds.add(playerId);
        }
      }

      final playersById = <String, Map<String, dynamic>>{};
      if (playerIds.isNotEmpty) {
        final playerRows = await supabase
            .from('players')
            .select('id, app_id, name, rating')
            .inFilter('id', playerIds.toList());

        for (final row in (playerRows as List).cast<Map<String, dynamic>>()) {
          final playerId = row['id']?.toString();
          if (playerId != null && playerId.isNotEmpty) {
            playersById[playerId] = row;
          }
        }
      }

      for (final row in teamPlayers) {
        final teamId = row['team_id']?.toString();
        final userId = row['player_id']?.toString();
        if (teamId == null || userId == null || userId.isEmpty) continue;

        final teamIndex = teamIndexByTeamId[teamId];
        if (teamIndex == null) continue;

        final player = playersById[userId];
        final name = (player?['name'] ?? 'Игрок').toString();
        final rating = (player?['rating'] as num?)?.toInt() ?? 0;
        final appId = (player?['app_id'] ?? '').toString();

        _teamRosterByIndex.putIfAbsent(teamIndex, () => <Player>[]);
        _teamRosterByIndex[teamIndex]!.add(
          Player(id: userId, name: name, rating: rating, teamIndex: teamIndex),
        );
        _teamIndexByUserId[userId] = teamIndex;
        _userNameById[userId] = name;

        if (appId.isNotEmpty) {
          _userIdByAppId[appId] = userId;
        }
      }

      for (final roster in _teamRosterByIndex.values) {
        roster.sort((a, b) => a.name.compareTo(b.name));
      }

      final hasRoster = _teamRosterByIndex.values.any((it) => it.isNotEmpty);
      if (!hasRoster) {
        await _hydrateRosterFromLocalTeams();
      }
    } catch (e) {
      debugPrint('❌ Ошибка загрузки составов: $e');
      await _hydrateRosterFromLocalTeams();
    }
  }

  Future<void> _hydrateRosterFromLocalTeams() async {
    final localTeams = widget.teams;
    if (localTeams == null) return;

    for (int i = 0; i < localTeams.length; i++) {
      _teamRosterByIndex.putIfAbsent(i, () => <Player>[]);
    }

    final appIds = <String>{};
    for (final team in localTeams) {
      for (final player in team) {
        if (player.id.isNotEmpty) appIds.add(player.id);
      }
    }

    final byAppId = <String, Map<String, dynamic>>{};
    if (appIds.isNotEmpty) {
      try {
        final rows = await supabase
            .from('players')
            .select('id, app_id, name, rating')
            .inFilter('app_id', appIds.toList());
        for (final row in (rows as List).cast<Map<String, dynamic>>()) {
          final appId = row['app_id']?.toString();
          if (appId != null && appId.isNotEmpty) {
            byAppId[appId] = row;
          }
        }
      } catch (e) {
        debugPrint('⚠️ Не удалось сопоставить app_id -> user_id: $e');
      }
    }

    for (int i = 0; i < localTeams.length; i++) {
      final roster = _teamRosterByIndex[i]!;
      if (roster.isNotEmpty) continue;

      for (final player in localTeams[i]) {
        final dbRow = byAppId[player.id];
        final userId = dbRow?['id']?.toString() ?? player.id;
        final name = (dbRow?['name'] ?? player.name).toString();
        final rating = (dbRow?['rating'] as num?)?.toInt() ?? player.rating;

        roster.add(
          Player(id: userId, name: name, rating: rating, teamIndex: i),
        );

        if (dbRow != null) {
          _teamIndexByUserId[userId] = i;
          _userNameById[userId] = name;
          _userIdByAppId[player.id] = userId;
        }
      }
      roster.sort((a, b) => a.name.compareTo(b.name));
    }
  }

  Future<void> _loadMatchEvents() async {
    if (_matches.isEmpty) return;

    for (final match in _matches) {
      match.events = <MatchEvent>[];
    }

    try {
      final rows = await supabase
          .from('match_events')
          .select('match_id, user_id, goals, assists')
          .eq('hall_id', widget.hallId)
          .eq('tournament_id', widget.tournamentId);

      final eventsByMatchId = <String, List<Map<String, dynamic>>>{};
      for (final raw in (rows as List).cast<Map<String, dynamic>>()) {
        final matchId = raw['match_id']?.toString();
        if (matchId == null || matchId.isEmpty) continue;
        eventsByMatchId.putIfAbsent(matchId, () => <Map<String, dynamic>>[]);
        eventsByMatchId[matchId]!.add(raw);
      }

      for (final match in _matches) {
        final rowsForMatch =
            eventsByMatchId[match.id] ?? const <Map<String, dynamic>>[];
        final events = <MatchEvent>[];

        for (final row in rowsForMatch) {
          final userId = row['user_id']?.toString();
          if (userId == null || userId.isEmpty) continue;

          final teamIndex = _teamIndexByUserId[userId];
          if (teamIndex == null) continue;

          final playerName = _userNameById[userId] ?? 'Игрок';
          final goals = (row['goals'] as num?)?.toInt() ?? 0;
          final assists = (row['assists'] as num?)?.toInt() ?? 0;

          for (int i = 0; i < goals; i++) {
            events.add(
              MatchEvent.goal(
                teamIndex: teamIndex,
                playerId: userId,
                playerName: playerName,
              ),
            );
          }
          for (int i = 0; i < assists; i++) {
            events.add(
              MatchEvent.assist(
                teamIndex: teamIndex,
                playerId: userId,
                playerName: playerName,
              ),
            );
          }
        }

        final homeGoalsFromEvents = events
            .where(
              (event) =>
                  event.teamIndex == match.homeIndex &&
                  (event.type == MatchEventType.goal ||
                      event.type == MatchEventType.ownGoal),
            )
            .length;
        final awayGoalsFromEvents = events
            .where(
              (event) =>
                  event.teamIndex == match.awayIndex &&
                  (event.type == MatchEventType.goal ||
                      event.type == MatchEventType.ownGoal),
            )
            .length;

        final missingHomeGoals = match.homeScore - homeGoalsFromEvents;
        final missingAwayGoals = match.awayScore - awayGoalsFromEvents;

        for (int i = 0; i < missingHomeGoals; i++) {
          events.add(MatchEvent.ownGoal(teamIndex: match.homeIndex));
        }
        for (int i = 0; i < missingAwayGoals; i++) {
          events.add(MatchEvent.ownGoal(teamIndex: match.awayIndex));
        }

        match.events = events;
      }
    } catch (e) {
      debugPrint('⚠️ Не удалось загрузить match_events: $e');
    }
  }

  Future<void> _loadMatches() async {
    try {
      final rows = await supabase
          .from('matches')
          .select(
            'id, round, match_no, home_team, away_team, home_score, away_score, finished',
          )
          .eq('tournament_id', widget.tournamentId)
          .order('round', ascending: true)
          .order('match_no', ascending: true);

      _matches
        ..clear()
        ..addAll(
          (rows as List).map((r) {
            final id = r['id'].toString();
            final round = (r['round'] as num?)?.toInt() ?? 1;
            final homeIndex = (r['home_team'] as num?)?.toInt() ?? 0;
            final awayIndex = (r['away_team'] as num?)?.toInt() ?? 1;
            final homeScore = (r['home_score'] as num?)?.toInt() ?? 0;
            final awayScore = (r['away_score'] as num?)?.toInt() ?? 0;
            final finished = (r['finished'] as bool?) ?? false;

            return MatchGame(
              id: id,
              round: round,
              homeIndex: homeIndex,
              awayIndex: awayIndex,
              homeTeamId: '',
              awayTeamId: '',
              homeScore: homeScore,
              awayScore: awayScore,
              finished: finished,
              events: <MatchEvent>[],
            );
          }).toList(),
        );
    } catch (e) {
      debugPrint('❌ Ошибка загрузки матчей: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Ошибка загрузки матчей: $e')));
      }
    }
  }

  Future<void> _saveMatchToSupabase(MatchGame match) async {
    if (_isCompleted) return;

    try {
      await supabase
          .from('matches')
          .update({
            'home_score': match.homeScore,
            'away_score': match.awayScore,
            'finished': match.finished,
          })
          .eq('id', match.id);

      await _saveMatchEvents(match);
    } catch (e) {
      debugPrint('❌ Ошибка сохранения матча: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить матч: $e')),
        );
      }
    }
  }

  List<Player> _playersForTeam(int teamIndex) {
    final roster = _teamRosterByIndex[teamIndex];
    if (roster != null && roster.isNotEmpty) {
      return roster;
    }

    final teams = widget.teams;
    if (teams == null) return const <Player>[];
    if (teamIndex < 0 || teamIndex >= teams.length) return const <Player>[];
    return teams[teamIndex];
  }

  void _openMatch(MatchGame match) {
    if (_isCompleted) return;
    if (widget.teams == null) return;

    showDialog(
      context: context,
      builder: (_) => MatchDialog(
        match: match,
        teamName: _teamLetter,
        homePlayers: _playersForTeam(match.homeIndex),
        awayPlayers: _playersForTeam(match.awayIndex),
        onSave: () async {
          setState(() {});
          await _saveMatchToSupabase(match);
        },
      ),
    );
  }

  Future<void> _saveMatchEvents(MatchGame match) async {
    await supabase.from('match_events').delete().eq('match_id', match.id);

    if (!match.finished || match.events.isEmpty) return;

    final statsByUserId = <String, _EventStatsAccumulator>{};
    for (final event in match.events) {
      if (event.type == MatchEventType.ownGoal) continue;

      if (event.type == MatchEventType.goal) {
        final scorerId = _resolveUserId(event.playerId);
        if (scorerId != null) {
          final scorerStats = statsByUserId.putIfAbsent(
            scorerId,
            () => _EventStatsAccumulator(teamIndex: event.teamIndex),
          );
          scorerStats.goals += 1;
          scorerStats.teamIndex = event.teamIndex;
        }

        final assistId = _resolveUserId(event.assistPlayerId);
        if (assistId != null) {
          final assistStats = statsByUserId.putIfAbsent(
            assistId,
            () => _EventStatsAccumulator(teamIndex: event.teamIndex),
          );
          assistStats.assists += 1;
          assistStats.teamIndex = event.teamIndex;
        }
      }

      if (event.type == MatchEventType.assist) {
        final assistId = _resolveUserId(event.playerId);
        if (assistId != null) {
          final assistStats = statsByUserId.putIfAbsent(
            assistId,
            () => _EventStatsAccumulator(teamIndex: event.teamIndex),
          );
          assistStats.assists += 1;
          assistStats.teamIndex = event.teamIndex;
        }
      }
    }

    if (statsByUserId.isEmpty) return;

    final insertRows = <Map<String, dynamic>>[];
    final nowUtc = DateTime.now().toUtc().toIso8601String();
    statsByUserId.forEach((userId, stats) {
      insertRows.add({
        'id': _newUuidV4(),
        'hall_id': widget.hallId,
        'tournament_id': widget.tournamentId.toString(),
        'match_id': match.id,
        'user_id': userId,
        'goals': stats.goals,
        'assists': stats.assists,
        'result': _resultForTeam(match, stats.teamIndex),
        'was_captain': false,
        'was_mvp': false,
        'created_at': nowUtc,
      });
    });

    await supabase.from('match_events').insert(insertRows);
  }

  String _resultForTeam(MatchGame match, int teamIndex) {
    if (match.homeScore == match.awayScore) return 'draw';

    final isHome = teamIndex == match.homeIndex;
    if (isHome) {
      return match.homeScore > match.awayScore ? 'win' : 'loss';
    }
    return match.awayScore > match.homeScore ? 'win' : 'loss';
  }

  String? _resolveUserId(String? maybeUserOrAppId) {
    if (maybeUserOrAppId == null) return null;
    final value = maybeUserOrAppId.trim();
    if (value.isEmpty) return null;

    final fromAppId = _userIdByAppId[value];
    if (fromAppId != null && fromAppId.isNotEmpty) {
      return fromAppId;
    }
    if (_teamIndexByUserId.containsKey(value)) {
      return value;
    }
    if (_uuidRegex.hasMatch(value)) {
      return value;
    }
    return null;
  }

  String _newUuidV4() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  // --------- UI helpers ----------

  static const double _badgeSize = 22;
  static const double _nameColWidth =
      84; // фикс-колонка под названия в "Составы"
  static const double _scoreColWidth = 78; // фикс-колонка под счет в матчах

  Widget _badge(String letter) {
    return Container(
      width: _badgeSize,
      height: _badgeSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  // слева: [A] Name
  Widget _teamLeftInline(int idx, {TextStyle? style}) {
    final letter = _teamLetter(idx);
    final name = _teamNameOnly(idx);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _badge(letter),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name.isEmpty ? letter : name,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ],
    );
  }

  // справа: Name [B]  (бейдж всегда у правого края)
  Widget _teamRightInline(int idx, {TextStyle? style}) {
    final letter = _teamLetter(idx);
    final name = _teamNameOnly(idx);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            name.isEmpty ? letter : name,
            overflow: TextOverflow.ellipsis,
            style: style,
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 8),
        _badge(letter),
      ],
    );
  }

  // --------- Header "Составы" (ровные колонки) ----------

  Widget _teamsHeader() {
    final maxRosterIndex = _teamRosterByIndex.keys.fold<int>(
      -1,
      (maxIndex, current) => current > maxIndex ? current : maxIndex,
    );
    final teamCount = widget.teams?.length ?? (maxRosterIndex + 1);
    if (teamCount <= 0) return const SizedBox.shrink();

    final titleStyle = TextStyle(
      fontSize: 12,
      height: 1.15,
      fontWeight: FontWeight.w700,
      color: Colors.grey.shade800,
    );

    final rosterStyle = TextStyle(
      fontSize: 12,
      height: 1.15,
      color: Colors.grey.shade800,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTileTheme(
        dense: true,
        minVerticalPadding: 0,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: _rosterExpanded,
            onExpansionChanged: (v) => setState(() => _rosterExpanded = v),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 2,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
            title: const Padding(
              padding: EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Составы',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            children: [
              for (int i = 0; i < teamCount; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // бейдж
                      _badge(_teamLetter(i)),
                      const SizedBox(width: 10),

                      // фикс-колонка под название
                      SizedBox(
                        width: _nameColWidth,
                        child: Text(
                          _teamNameOnly(i).isEmpty ? '—' : _teamNameOnly(i),
                          style: titleStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),

                      // состав (ровно по старту строки)
                      Expanded(
                        child: Text(
                          _playersForTeam(i).map((p) => p.name).join(', '),
                          style: rosterStyle,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // --------- Очки ----------

  Map<int, int> _tableForRound(int roundNumber) {
    final table = <int, int>{};
    final teamsCount = widget.teams?.length ?? 4;

    for (int i = 0; i < teamsCount; i++) {
      table[i] = 0;
    }

    for (final m in _matches) {
      if (!m.finished) continue;
      if (m.round != roundNumber) continue;

      if (m.homeScore > m.awayScore) {
        table[m.homeIndex] = (table[m.homeIndex] ?? 0) + 3;
      } else if (m.homeScore < m.awayScore) {
        table[m.awayIndex] = (table[m.awayIndex] ?? 0) + 3;
      } else {
        table[m.homeIndex] = (table[m.homeIndex] ?? 0) + 1;
        table[m.awayIndex] = (table[m.awayIndex] ?? 0) + 1;
      }
    }
    return table;
  }

  Map<int, int> _tableForTournament() {
    final table = <int, int>{};
    final teamsCount = widget.teams?.length ?? 4;

    for (int i = 0; i < teamsCount; i++) {
      table[i] = 0;
    }

    for (final m in _matches) {
      if (!m.finished) continue;

      if (m.homeScore > m.awayScore) {
        table[m.homeIndex] = (table[m.homeIndex] ?? 0) + 3;
      } else if (m.homeScore < m.awayScore) {
        table[m.awayIndex] = (table[m.awayIndex] ?? 0) + 3;
      } else {
        table[m.homeIndex] = (table[m.homeIndex] ?? 0) + 1;
        table[m.awayIndex] = (table[m.awayIndex] ?? 0) + 1;
      }
    }
    return table;
  }

  Map<String, int> _pointsLineFromTable(Map<int, int> table) {
    final keys = table.keys.toList()..sort();
    return {for (final k in keys) _teamLetter(k): table[k] ?? 0};
  }

  // --------- матч строка (справа бейдж выровнен по правому краю) ----------

  Widget _matchTitle(MatchGame m) {
    final nameStyle = Theme.of(context).textTheme.bodyMedium;

    return Row(
      children: [
        // левый блок занимает место, текст может урезаться
        Expanded(child: _teamLeftInline(m.homeIndex, style: nameStyle)),

        // центр: фикс ширина для счета => все строки одинаково
        SizedBox(
          width: _scoreColWidth,
          child: Center(
            child: Text(
              '${m.homeScore} : ${m.awayScore}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),

        // правый блок: бейдж всегда справа
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: _teamRightInline(m.awayIndex, style: nameStyle),
          ),
        ),
      ],
    );
  }

  Future<void> _finishTournament() async {
    if (_isCompleted || _finishing) return;

    await _loadTournamentCompleted();
    if (_isCompleted && _statsApplied) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Турнир уже завершён.')));
      return;
    }

    if (!mounted) return;
    final notFinished = _matches.where((m) => !m.finished).length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Завершить турнир?'),
        content: Text(
          notFinished > 0
              ? 'Остались не сыгранные матчи: $notFinished.\n\nВсе равно завершить?'
              : 'Все матчи сыграны.\n\nПодтвердить завершение?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final mvpUserId = await _pickTournamentMvp();

    if (!mounted) return;
    setState(() => _finishing = true);

    final tid = widget.tournamentId.toString();
    bool lockAcquired = false;

    try {
      if (_hasStatsAppliedColumn) {
        lockAcquired = await _tryAcquireStatsApplyLock(tid);
      }

      if (!_hasStatsAppliedColumn || lockAcquired) {
        await supabase.rpc(
          'apply_tournament_stats',
          params: {'p_tournament_id': tid},
        );
        await _applyMatchEventsToPlayerStats(tid, mvpUserId: mvpUserId);
      }

      await _markTournamentCompleted(
        tid,
        withStatsApplied: _hasStatsAppliedColumn,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);

      if (!mounted) return;
      setState(() {
        _isCompleted = true;
        if (_hasStatsAppliedColumn) {
          _statsApplied = true;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lockAcquired || !_hasStatsAppliedColumn
                ? 'Турнир завершён. Статистика обновлена ✅'
                : 'Турнир уже был обработан ранее, повторного начисления нет ✅',
          ),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (_hasStatsAppliedColumn && lockAcquired) {
        await _releaseStatsApplyLock(tid);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось завершить турнир: $e')),
      );
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Future<String?> _pickTournamentMvp() {
    final candidatesById = <String, Player>{};
    for (final roster in _teamRosterByIndex.values) {
      for (final player in roster) {
        candidatesById[player.id] = player;
      }
    }

    if (candidatesById.isEmpty && widget.teams != null) {
      for (int i = 0; i < widget.teams!.length; i++) {
        for (final player in widget.teams![i]) {
          final resolvedId = _resolveUserId(player.id) ?? player.id;
          candidatesById[resolvedId] = player.copyWith(id: resolvedId);
        }
      }
    }

    final candidates = candidatesById.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (candidates.isEmpty) return Future.value(null);

    return showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('MVP вратарь (опционально)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (context, index) {
              final player = candidates[index];
              return ListTile(
                title: Text(player.name),
                onTap: () => Navigator.pop(
                  context,
                  _resolveUserId(player.id) ?? player.id,
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Без MVP'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyMatchEventsToPlayerStats(
    String tournamentId, {
    String? mvpUserId,
  }) async {
    final rows = await supabase
        .from('match_events')
        .select('user_id, goals, assists')
        .eq('hall_id', widget.hallId)
        .eq('tournament_id', tournamentId);

    final deltaByUserId = <String, _PlayerStatsDelta>{};
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final userId = _resolveUserId(row['user_id']?.toString());
      if (userId == null) continue;

      final delta = deltaByUserId.putIfAbsent(userId, _PlayerStatsDelta.new);
      delta.goals += (row['goals'] as num?)?.toInt() ?? 0;
      delta.assists += (row['assists'] as num?)?.toInt() ?? 0;
    }

    final resolvedMvpUserId = _resolveUserId(mvpUserId);
    if (resolvedMvpUserId != null) {
      final delta = deltaByUserId.putIfAbsent(
        resolvedMvpUserId,
        _PlayerStatsDelta.new,
      );
      delta.mvpCount += 1;
      await _markMvpRow(tournamentId, resolvedMvpUserId);
    }

    if (deltaByUserId.isEmpty) return;

    final userIds = deltaByUserId.keys.toList();
    final existingRows = await supabase
        .from('player_stats')
        .select('id, user_id, goals, assists, mvp_count')
        .eq('hall_id', widget.hallId)
        .inFilter('user_id', userIds);

    final byUserId = <String, Map<String, dynamic>>{};
    for (final row in (existingRows as List).cast<Map<String, dynamic>>()) {
      final userId = row['user_id']?.toString();
      if (userId != null && userId.isNotEmpty) {
        byUserId[userId] = row;
      }
    }

    for (final entry in deltaByUserId.entries) {
      final existing = byUserId[entry.key];
      if (existing == null) {
        debugPrint(
          '⚠️ player_stats not found for user ${entry.key}, goals/assists update skipped',
        );
        continue;
      }

      final goals = (existing['goals'] as num?)?.toInt() ?? 0;
      final assists = (existing['assists'] as num?)?.toInt() ?? 0;
      final mvpCount = (existing['mvp_count'] as num?)?.toInt() ?? 0;

      await supabase
          .from('player_stats')
          .update({
            'goals': goals + entry.value.goals,
            'assists': assists + entry.value.assists,
            'mvp_count': mvpCount + entry.value.mvpCount,
          })
          .eq('id', existing['id'].toString());
    }
  }

  Future<void> _markMvpRow(String tournamentId, String mvpUserId) async {
    try {
      final row = await supabase
          .from('match_events')
          .select('id')
          .eq('hall_id', widget.hallId)
          .eq('tournament_id', tournamentId)
          .eq('user_id', mvpUserId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row == null) return;
      await supabase
          .from('match_events')
          .update({'was_mvp': true})
          .eq('id', row['id'].toString());
    } catch (e) {
      debugPrint('⚠️ Не удалось отметить MVP в match_events: $e');
    }
  }

  bool _isMissingStatsAppliedColumnError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('stats_applied') &&
        (text.contains('does not exist') || text.contains('could not find'));
  }

  Future<bool> _tryAcquireStatsApplyLock(String tournamentId) async {
    try {
      final row = await supabase
          .from('tournaments')
          .update({'stats_applied': true})
          .eq('id', tournamentId)
          .or('stats_applied.is.null,stats_applied.eq.false')
          .select('id')
          .maybeSingle();

      return row != null;
    } catch (e) {
      if (_isMissingStatsAppliedColumnError(e)) {
        _hasStatsAppliedColumn = false;
        return true;
      }
      rethrow;
    }
  }

  Future<void> _releaseStatsApplyLock(String tournamentId) async {
    try {
      await supabase
          .from('tournaments')
          .update({'stats_applied': false})
          .eq('id', tournamentId)
          .eq('completed', false);
    } catch (_) {
      // Если unlock не удался, повторное применение все равно будет блокироваться на сервере флагом.
    }
  }

  Future<void> _markTournamentCompleted(
    String tournamentId, {
    required bool withStatsApplied,
  }) async {
    final payload = <String, dynamic>{'completed': true};
    if (withStatsApplied) {
      payload['stats_applied'] = true;
    }

    try {
      await supabase.from('tournaments').update(payload).eq('id', tournamentId);
    } catch (e) {
      if (withStatsApplied && _isMissingStatsAppliedColumnError(e)) {
        _hasStatsAppliedColumn = false;
        await supabase
            .from('tournaments')
            .update({'completed': true})
            .eq('id', tournamentId);
        return;
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Расписание')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final rounds = _matches.map((m) => m.round).toSet().toList()..sort();
    final readOnly = widget.teams == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(readOnly ? 'Расписание (просмотр)' : 'Расписание'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isCompleted)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withOpacity(0.30)),
              ),
              child: const Text(
                'Турнир завершён. Редактирование матчей отключено.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),

          _teamsHeader(),

          ...rounds.map((roundNumber) {
            final roundMatches = _matches
                .where((m) => m.round == roundNumber)
                .toList();
            final allFinished = roundMatches.every((m) => m.finished);

            final roundLine = _pointsLineFromTable(_tableForRound(roundNumber));

            return Card(
              margin: const EdgeInsets.only(bottom: 20),
              elevation: 2,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: allFinished ? Colors.green : Colors.grey.shade300,
                      width: 4,
                    ),
                  ),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Круг $roundNumber',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...roundMatches.map(
                      (m) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        tileColor: m.finished
                            ? Colors.green.withOpacity(0.08)
                            : null,
                        title: _matchTitle(m),
                        onTap: (_isCompleted || readOnly)
                            ? null
                            : () => _openMatch(m),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TeamsPointsLine(pointsByTeam: roundLine),
                  ],
                ),
              ),
            );
          }),

          if (rounds.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text(
              'Итог турнира',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TeamsPointsLine(
              pointsByTeam: _pointsLineFromTable(_tableForTournament()),
            ),
          ],

          const SizedBox(height: 12),

          if (!_isCompleted && !readOnly)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _finishing ? null : _finishTournament,
                child: _finishing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Завершить турнир'),
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _EventStatsAccumulator {
  _EventStatsAccumulator({required this.teamIndex});

  int teamIndex;
  int goals = 0;
  int assists = 0;
}

class _PlayerStatsDelta {
  int goals = 0;
  int assists = 0;
  int mvpCount = 0;
}
