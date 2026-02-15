import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../players/model/player.dart';
import '../../tournaments/ui/create_tournament_page.dart';
import '../../tournaments/ui/mvp_vote_page.dart';
import '../../tournaments/ui/tournaments_history_page.dart';
import '../../tournaments/ui/schedule_page.dart';

class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key, required this.hallId});

  final String hallId;

  @override
  State<MatchesPage> createState() => MatchesPageState();
}

class MatchesPageState extends State<MatchesPage> {
  final supabase = Supabase.instance.client;

  String? _activeTournamentId;
  bool _loadingActive = true;

  String? _activeDateText;
  int? _activePlayed;
  int? _activeTotal;

  String? _activeLeaderText; // "A (7 оч.)"

  bool _loadingMvp = true;
  String _mvpSubtitle = 'Проверяем MVP-голосование...';

  String get _prefsKey => 'active_tournament_${widget.hallId}';

  @override
  void initState() {
    super.initState();
    _loadActiveTournament();
    _loadMvpVotingStatus();
  }

  /// ✅ дергаем снаружи (из HallHomePage) при переключении вкладки
  void reloadActive() {
    _loadActiveTournament();
    _loadMvpVotingStatus();
  }

  String _formatDate(dynamic iso) {
    try {
      final dt = DateTime.parse(iso.toString());
      return '${dt.day.toString().padLeft(2, '0')}.'
          '${dt.month.toString().padLeft(2, '0')}.'
          '${dt.year}';
    } catch (_) {
      return iso.toString();
    }
  }

  // ✅ только буквы
  String _teamName(int i) => String.fromCharCode(65 + i);

  Map<int, int> _calcPoints(
    List<Map<String, dynamic>> matches,
    int teamsCount,
  ) {
    final table = <int, int>{};
    for (int i = 0; i < teamsCount; i++) {
      table[i] = 0;
    }

    for (final m in matches) {
      if ((m['finished'] as bool?) != true) continue;

      final h = (m['home_team'] as num?)?.toInt() ?? 0;
      final a = (m['away_team'] as num?)?.toInt() ?? 1;
      final hs = (m['home_score'] as num?)?.toInt() ?? 0;
      final as = (m['away_score'] as num?)?.toInt() ?? 0;

      if (hs > as) {
        table[h] = (table[h] ?? 0) + 3;
      } else if (hs < as) {
        table[a] = (table[a] ?? 0) + 3;
      } else {
        table[h] = (table[h] ?? 0) + 1;
        table[a] = (table[a] ?? 0) + 1;
      }
    }

    return table;
  }

  List<MapEntry<int, int>> _topN(Map<int, int> table, int n) {
    final list = table.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(n).toList();
  }

  int _inferTeamsCountFromMatches(List<Map<String, dynamic>> matches) {
    int maxIdx = -1;
    for (final m in matches) {
      final h = (m['home_team'] as num?)?.toInt();
      final a = (m['away_team'] as num?)?.toInt();
      if (h != null && h > maxIdx) maxIdx = h;
      if (a != null && a > maxIdx) maxIdx = a;
    }
    return maxIdx >= 0 ? maxIdx + 1 : 4;
  }

  bool _isMissingMvpVotingSchemaError(Object error) {
    final text = error.toString().toLowerCase();
    final mentionsMvpSchema =
        text.contains('mvp_voting_ends_at') ||
        text.contains('mvp_votes_finalized') ||
        text.contains('mvp_finalized_at') ||
        text.contains('mvp_winner_player_id') ||
        text.contains('tournament_mvp_votes') ||
        text.contains('finalize_due_mvp_votes');
    return mentionsMvpSchema &&
        (text.contains('does not exist') ||
            text.contains('could not find') ||
            text.contains('function') ||
            text.contains('column'));
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _loadMvpVotingStatus() async {
    if (!mounted) return;

    setState(() {
      _loadingMvp = true;
      _mvpSubtitle = 'Проверяем MVP-голосование...';
    });

    try {
      await supabase.rpc(
        'finalize_due_mvp_votes',
        params: {'p_hall_id': widget.hallId},
      );
    } catch (e) {
      if (!_isMissingMvpVotingSchemaError(e)) {
        debugPrint('⚠️ finalize_due_mvp_votes failed: $e');
      }
    }

    try {
      final rows = await supabase
          .from('tournaments')
          .select(
            'id, date, mvp_voting_ends_at, mvp_votes_finalized, mvp_winner_player_id',
          )
          .eq('hall_id', widget.hallId)
          .eq('completed', true)
          .order('date', ascending: false)
          .limit(1);

      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loadingMvp = false;
          _mvpSubtitle = 'Пока нет завершённых турниров';
        });
        return;
      }

      final t = list.first;
      final finalized = (t['mvp_votes_finalized'] as bool?) ?? false;
      final winnerPlayerId = t['mvp_winner_player_id']?.toString();
      final endsAt = _parseDateTimeOrNull(t['mvp_voting_ends_at']);
      final nowUtc = DateTime.now().toUtc();

      String subtitle;
      if (finalized) {
        subtitle = winnerPlayerId == null || winnerPlayerId.isEmpty
            ? 'MVP-голосование завершено (без победителя)'
            : 'MVP выбран, результаты учтены в рейтинге';
      } else if (endsAt == null) {
        subtitle = 'Голосование MVP ещё не настроено для последнего турнира';
      } else if (nowUtc.isBefore(endsAt)) {
        subtitle = 'Идёт голосование до ${_formatDateTime(endsAt)}';
      } else {
        subtitle = 'Голосование закрыто, ожидается автоматический подсчёт';
      }

      if (!mounted) return;
      setState(() {
        _loadingMvp = false;
        _mvpSubtitle = subtitle;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMvp = false;
        _mvpSubtitle = _isMissingMvpVotingSchemaError(e)
            ? 'Нужно применить SQL для MVP-голосования'
            : 'Не удалось загрузить статус MVP-голосования';
      });
    }
  }

  DateTime? _parseDateTimeOrNull(dynamic raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  Future<void> _loadActiveTournament() async {
    if (!mounted) return;

    setState(() {
      _loadingActive = true;
      _activeDateText = null;
      _activePlayed = null;
      _activeTotal = null;
      _activeLeaderText = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_prefsKey);

    if (savedId == null) {
      if (!mounted) return;
      setState(() {
        _activeTournamentId = null;
        _loadingActive = false;
      });
      return;
    }

    try {
      final t = await supabase
          .from('tournaments')
          .select('id, date, completed')
          .eq('id', savedId)
          .single();

      final completed = (t['completed'] as bool?) ?? false;
      if (completed) {
        await prefs.remove(_prefsKey);
        if (!mounted) return;
        setState(() {
          _activeTournamentId = null;
          _loadingActive = false;
        });
        return;
      }

      final mRows = await supabase
          .from('matches')
          .select('home_team, away_team, home_score, away_score, finished')
          .eq('tournament_id', savedId);

      final list = (mRows as List).cast<Map<String, dynamic>>();

      final total = list.length;
      final played = list.where((x) => (x['finished'] as bool?) == true).length;

      final teamsCount = _inferTeamsCountFromMatches(list);

      String? leaderText;
      if (list.isNotEmpty) {
        final table = _calcPoints(list, teamsCount);
        final top1 = _topN(table, 1);
        if (top1.isNotEmpty) {
          leaderText = '${_teamName(top1[0].key)} (${top1[0].value} оч.)';
        }
      }

      if (!mounted) return;
      setState(() {
        _activeTournamentId = savedId;
        _activeDateText = _formatDate(t['date']);
        _activePlayed = played;
        _activeTotal = total;
        _activeLeaderText = leaderText;
        _loadingActive = false;
      });
    } catch (_) {
      await prefs.remove(_prefsKey);
      if (!mounted) return;
      setState(() {
        _activeTournamentId = null;
        _loadingActive = false;
      });
    }
  }

  Future<List<List<Player>>> _fetchTeamsForTournament(
    String tournamentId,
  ) async {
    final teamRows = await supabase
        .from('teams')
        .select('id, team_index')
        .eq('tournament_id', tournamentId)
        .order('team_index', ascending: true);

    final teams = (teamRows as List).cast<Map<String, dynamic>>();
    if (teams.isEmpty) return [];

    final teamIdByIndex = <int, String>{};
    final teamIds = <String>[];

    for (final t in teams) {
      final idx = (t['team_index'] as num?)?.toInt();
      final id = t['id'].toString();
      if (idx != null) {
        teamIdByIndex[idx] = id;
        teamIds.add(id);
      }
    }

    final maxIndex = teamIdByIndex.keys.isEmpty
        ? 0
        : teamIdByIndex.keys.reduce((a, b) => a > b ? a : b);

    final result = List.generate(maxIndex + 1, (_) => <Player>[]);

    final tpRows = await supabase
        .from('team_players')
        .select('team_id, player_id')
        .inFilter('team_id', teamIds);

    final tps = (tpRows as List).cast<Map<String, dynamic>>();

    final playerUuids = <String>{};
    for (final r in tps) {
      playerUuids.add(r['player_id'].toString());
    }

    if (playerUuids.isEmpty) return result;

    final pRows = await supabase
        .from('players')
        .select('id, app_id, name, rating')
        .inFilter('id', playerUuids.toList());

    final players = (pRows as List).cast<Map<String, dynamic>>();
    final playerByUuid = <String, Player>{};

    for (final p in players) {
      final uuid = p['id'].toString();
      final appId = (p['app_id'] ?? uuid).toString();
      playerByUuid[uuid] = Player(
        id: appId,
        name: (p['name'] ?? '').toString(),
        rating: (p['rating'] as num?)?.toInt() ?? 0,
      );
    }

    final indexByTeamId = <String, int>{};
    teamIdByIndex.forEach((idx, teamId) {
      indexByTeamId[teamId] = idx;
    });

    for (final r in tps) {
      final teamId = r['team_id'].toString();
      final playerUuid = r['player_id'].toString();
      final idx = indexByTeamId[teamId];
      final pl = playerByUuid[playerUuid];

      if (idx != null && pl != null) {
        result[idx].add(pl);
      }
    }

    return result;
  }

  Future<void> _openActiveTournament() async {
    final id = _activeTournamentId;
    if (id == null) return;

    try {
      final teams = await _fetchTeamsForTournament(id);

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SchedulePage(
            tournamentId: id,
            hallId: widget.hallId,
            teamName: (i) => _teamName(i),
            teams: teams.isEmpty ? null : teams,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SchedulePage(
            tournamentId: id,
            hallId: widget.hallId,
            teamName: (i) => _teamName(i),
            teams: null,
          ),
        ),
      );
    } finally {
      _loadActiveTournament();
      _loadMvpVotingStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = _activeTournamentId != null;

    final parts = <String>[];
    if (_activeDateText != null) parts.add('Дата: $_activeDateText');
    if (_activePlayed != null && _activeTotal != null) {
      parts.add('Сыграно: $_activePlayed/$_activeTotal');
    }
    if (_activeLeaderText != null) parts.add('Лидер: $_activeLeaderText');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_loadingActive)
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: LinearProgressIndicator(),
          ),

        if (hasActive) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Открыть активный турнир'),
              subtitle: Text(parts.join(' • ')),
              onTap: _openActiveTournament,
            ),
          ),
          const SizedBox(height: 12),
        ],

        Card(
          child: ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Создать турнир'),
            subtitle: const Text('Новый матч / турнир'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateTournamentPage(hallId: widget.hallId),
                ),
              ).then((_) {
                _loadActiveTournament();
                _loadMvpVotingStatus();
              });
            },
          ),
        ),

        const SizedBox(height: 16),

        Card(
          child: ListTile(
            leading: const Icon(Icons.how_to_vote),
            title: const Text('MVP голосование'),
            subtitle: Text(_loadingMvp ? 'Загрузка...' : _mvpSubtitle),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TournamentMvpVotePage(hallId: widget.hallId),
                ),
              );
              _loadMvpVotingStatus();
            },
          ),
        ),

        const SizedBox(height: 16),

        Card(
          child: ListTile(
            leading: const Icon(Icons.history),
            title: const Text('История турниров'),
            subtitle: const Text('Топ-3 + прогресс'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TournamentsHistoryPage(hallId: widget.hallId),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
