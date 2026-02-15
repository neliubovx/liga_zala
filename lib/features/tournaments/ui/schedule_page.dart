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

  bool _loading = true;
  bool _finishing = false;
  bool _isCompleted = false;
  bool _statsApplied = false;
  bool _hasStatsAppliedColumn = true;

  final List<MatchGame> _matches = [];
  final Map<int, String> _teamNames = {};
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
    await Future.wait([
      _loadTournamentCompleted(),
      _loadTeamNames(),
      _loadMatches(),
    ]);
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
    } catch (e) {
      debugPrint('❌ Ошибка сохранения матча: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить матч: $e')),
        );
      }
    }
  }

  void _openMatch(MatchGame match) {
    if (_isCompleted) return;
    if (widget.teams == null) return;

    showDialog(
      context: context,
      builder: (_) => MatchDialog(
        match: match,
        teamName: _teamLetter,
        homePlayers: widget.teams![match.homeIndex],
        awayPlayers: widget.teams![match.awayIndex],
        onSave: () async {
          setState(() {});
          await _saveMatchToSupabase(match);
        },
      ),
    );
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
    if (widget.teams == null) return const SizedBox.shrink();

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
              for (int i = 0; i < widget.teams!.length; i++)
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
                          widget.teams![i].map((p) => p.name).join(', '),
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
