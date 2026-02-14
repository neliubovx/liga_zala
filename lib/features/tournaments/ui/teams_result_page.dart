import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../players/model/player.dart';
import 'schedule_page.dart';
import 'select_players_page.dart';

class TeamsResultPage extends StatefulWidget {
  const TeamsResultPage({
    super.key,
    required this.hallId,
    required this.teams,
    required this.rounds,
    required this.tournamentDate,
    required this.splitMethod,
  });

  final String hallId;
  final List<List<Player>> teams;
  final int rounds;
  final DateTime tournamentDate;
  final TeamSplitMethod splitMethod;

  @override
  State<TeamsResultPage> createState() => _TeamsResultPageState();
}

class _TeamsResultPageState extends State<TeamsResultPage> {
  final supabase = Supabase.instance.client;

  bool _creating = false;
  bool _loadingActive = true;
  String? _tournamentId;

  late final List<String> _teamNames;

  String get _prefsKey => 'active_tournament_${widget.hallId}';
  String _teamLetter(int i) => String.fromCharCode(65 + i);

  bool get _hideRating => widget.splitMethod == TeamSplitMethod.random;

  String get _methodLabel {
    switch (widget.splitMethod) {
      case TeamSplitMethod.rating:
        return 'По рейтингу';
      case TeamSplitMethod.baskets:
        return 'По корзинам';
      case TeamSplitMethod.random:
        return 'Случайно';
    }
  }

  @override
  void initState() {
    super.initState();
    _teamNames = List.generate(widget.teams.length, (i) => _teamLetter(i));
    _loadActiveIfAny();
  }

  // ---------- UI helpers ----------

  Widget _methodChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Text(
        'Формат: $_methodLabel',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  bool _hasCustomName(int index) {
    final letter = _teamLetter(index);
    final name = _teamNames[index].trim();
    return name.isNotEmpty && name != letter;
  }

  // ---------- active tournament ----------

  Future<void> _loadActiveIfAny() async {
    setState(() => _loadingActive = true);

    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefsKey);

    if (savedId == null) {
      if (!mounted) return;
      setState(() {
        _tournamentId = null;
        _loadingActive = false;
      });
      return;
    }

    try {
      final t = await supabase
          .from('tournaments')
          .select('id, completed')
          .eq('id', savedId)
          .single();

      final completed = (t['completed'] as bool?) ?? false;

      if (completed) {
        await prefs.remove(_prefsKey);
        if (!mounted) return;
        setState(() {
          _tournamentId = null;
          _loadingActive = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _tournamentId = savedId;
        _loadingActive = false;
      });
    } catch (_) {
      await prefs.remove(_prefsKey);

      if (!mounted) return;
      setState(() {
        _tournamentId = null;
        _loadingActive = false;
      });
    }
  }

  // ---------- rename team ----------

  Future<void> _renameTeam(int index) async {
    final controller = TextEditingController(
      text: _hasCustomName(index) ? _teamNames[index] : '',
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Название команды ${_teamLetter(index)}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Например: Локомотив',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ''), // сброс
            child: const Text('Сбросить'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (newName == null) return;

    final finalName = newName.isEmpty ? _teamLetter(index) : newName;

    setState(() => _teamNames[index] = finalName);

    // если турнир уже создан — сохраняем в Supabase
    final tid = _tournamentId;
    if (tid != null) {
      try {
        await supabase
            .from('teams')
            .update({'name': finalName})
            .eq('tournament_id', tid)
            .eq('team_index', index);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить имя команды: $e')),
        );
      }
    }
  }

  // ---------- ensure players (без UNIQUE) ----------

  Future<Map<String, String>> _fetchAppIdToUuid(Set<String> appIds) async {
    if (appIds.isEmpty) return {};

    final rows = await supabase
        .from('players')
        .select('id, app_id')
        .inFilter('app_id', appIds.toList());

    final list = (rows as List).cast<Map<String, dynamic>>();
    final map = <String, String>{};

    for (final r in list) {
      final uuid = r['id'].toString();
      final appId = (r['app_id'] ?? '').toString();
      if (appId.isNotEmpty) map[appId] = uuid;
    }
    return map;
  }

  Future<Map<String, String>> _ensurePlayersExistInSupabase() async {
    final allPlayers = widget.teams.expand((t) => t).toList();
    final appIds = allPlayers.map((p) => p.id).toSet();

    final existing = await _fetchAppIdToUuid(appIds);
    final missing =
        allPlayers.where((p) => !existing.containsKey(p.id)).toList();

    if (missing.isNotEmpty) {
      final payload = missing
          .map((p) => {
                'app_id': p.id,
                'name': p.name,
                'rating': p.rating,
              })
          .toList();

      await supabase.from('players').insert(payload);
    }

    return _fetchAppIdToUuid(appIds);
  }

  // ---------- create tournament ----------

  Future<void> _createTournament() async {
    if (_creating) return;
    setState(() => _creating = true);

    try {
      // 1) создаём турнир
      final inserted = await supabase
          .from('tournaments')
          .insert({
            'hall_id': widget.hallId,
            'teams_count': widget.teams.length,
            'rounds': widget.rounds,
            'date': widget.tournamentDate.toIso8601String(),
            'completed': false,
          })
          .select('id')
          .single();

      final tournamentId = inserted['id'].toString();

      // 2) записываем активный турнир в prefs
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, tournamentId);

      // 3) создаём команды (с именами)
      final teamRows = <Map<String, dynamic>>[];
      for (int i = 0; i < widget.teams.length; i++) {
        teamRows.add({
          'tournament_id': tournamentId,
          'team_index': i,
          'name': _teamNames[i],
        });
      }

      final createdTeams = await supabase
          .from('teams')
          .insert(teamRows)
          .select('id, team_index');

      final created = (createdTeams as List).cast<Map<String, dynamic>>();
      final teamIdByIndex = <int, String>{};
      for (final r in created) {
        final idx = (r['team_index'] as num?)?.toInt();
        final id = r['id'].toString();
        if (idx != null) teamIdByIndex[idx] = id;
      }

      // 4) ensure players uuids
      final appIdToUuid = await _ensurePlayersExistInSupabase();

      // 5) team_players
      final tpRows = <Map<String, dynamic>>[];
      for (int i = 0; i < widget.teams.length; i++) {
        final teamId = teamIdByIndex[i];
        if (teamId == null) continue;

        for (final p in widget.teams[i]) {
          final playerUuid = appIdToUuid[p.id];
          if (playerUuid == null) continue;

          tpRows.add({
  'team_id': teamId,
  'player_id': playerUuid,
  'tournament_id': tournamentId, // ✅ ОБЯЗАТЕЛЬНО теперь
});

        }
      }
      if (tpRows.isNotEmpty) {
        await supabase.from('team_players').insert(tpRows);
      }

      // 6) matches (круговая)
      final teamsCount = widget.teams.length;
      final matchesToInsert = <Map<String, dynamic>>[];

      for (int round = 1; round <= widget.rounds; round++) {
        int matchNo = 1;
        for (int i = 0; i < teamsCount; i++) {
          for (int j = i + 1; j < teamsCount; j++) {
            matchesToInsert.add({
              'tournament_id': tournamentId,
              'round': round,
              'match_no': matchNo,
              'home_team': i,
              'away_team': j,
              'home_score': 0,
              'away_score': 0,
              'finished': false,
            });
            matchNo++;
          }
        }
      }

      await supabase.from('matches').insert(matchesToInsert);

      if (!mounted) return;

      setState(() => _tournamentId = tournamentId);

      await _openTournament(tournamentId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать турнир: $e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openTournament(String tournamentId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SchedulePage(
          tournamentId: tournamentId,
          hallId: widget.hallId,
          teams: widget.teams,
          teamName: (i) => _teamLetter(i),
        ),
      ),
    );

    await _loadActiveIfAny();
  }

  Future<void> _startNewTournament() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SelectPlayersPage(
          hallId: widget.hallId,
          teamsCount: widget.teams.length,
          playersPerTeam: widget.teams.isNotEmpty ? widget.teams[0].length : 4,
          rounds: widget.rounds,
          tournamentDate: widget.tournamentDate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTournament = _tournamentId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Команды')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: _loadingActive
              ? const SizedBox(
                  height: 48,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : hasTournament
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _creating
                                ? null
                                : () => _openTournament(_tournamentId!),
                            child: const Text('Вернуться в турнир'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _creating ? null : _startNewTournament,
                            child: const Text('Начать новый турнир'),
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _creating ? null : _createTournament,
                        child: _creating
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Сформировать турнир'),
                      ),
                    ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _methodChip(),
          ),
          const SizedBox(height: 10),

          for (int i = 0; i < widget.teams.length; i++) ...[
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => _renameTeam(i),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              _teamLetter(i),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            if (_hasCustomName(i)) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _teamNames[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ] else
                              const Spacer(),
                            Icon(Icons.edit, size: 16, color: Colors.grey.shade600),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    LayoutBuilder(
                      builder: (context, c) {
                        final players = widget.teams[i];
                        final half = (players.length / 2).ceil();
                        final left = players.take(half).toList();
                        final right = players.skip(half).toList();

                        Widget col(List<Player> list) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: list.map((p) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: _hideRating
                                      ? Text(
                                          p.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        )
                                      : Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                p.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '${p.rating}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                );
                              }).toList(),
                            );

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: col(left)),
                            const SizedBox(width: 12),
                            Expanded(child: col(right)),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
