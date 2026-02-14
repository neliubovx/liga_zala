import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'schedule_page.dart';

class TournamentsHistoryPage extends StatefulWidget {
  const TournamentsHistoryPage({
    super.key,
    required this.hallId,
  });

  final String hallId;

  @override
  State<TournamentsHistoryPage> createState() => _TournamentsHistoryPageState();
}

class _TournamentsHistoryPageState extends State<TournamentsHistoryPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  List<Map<String, dynamic>> _tournaments = [];

  @override
  void initState() {
    super.initState();
    _load();
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

  String _teamName(int i) => 'Команда ${String.fromCharCode(65 + i)}';

  Map<int, int> _calcPoints(List<Map<String, dynamic>> matches, int teamsCount) {
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

  String _top3Text(Map<int, int> table) {
    final top3 = _topN(table, 3);
    if (top3.isEmpty) return '—';

    // 1) A 7 • 2) B 6 • 3) C 4
    final parts = <String>[];
    for (int i = 0; i < top3.length; i++) {
      final e = top3[i];
      parts.add('${i + 1}) ${_teamName(e.key)} ${e.value}');
    }
    return parts.join(' • ');
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final tRows = await supabase
          .from('tournaments')
          .select('id, date, teams_count, rounds, completed')
          .eq('hall_id', widget.hallId)
          .order('date', ascending: false);

      final tournaments = (tRows as List).cast<Map<String, dynamic>>();

      if (tournaments.isEmpty) {
        _tournaments = [];
        if (mounted) setState(() => _loading = false);
        return;
      }

      final ids = tournaments.map((t) => t['id'].toString()).toList();

      final mRows = await supabase
          .from('matches')
          .select('tournament_id, home_team, away_team, home_score, away_score, finished')
          .inFilter('tournament_id', ids);

      final matchesAll = (mRows as List).cast<Map<String, dynamic>>();

      final byTid = <String, List<Map<String, dynamic>>>{};
      for (final m in matchesAll) {
        final tid = m['tournament_id'].toString();
        (byTid[tid] ??= []).add(m);
      }

      for (final t in tournaments) {
        final tid = t['id'].toString();
        final teamsCount = (t['teams_count'] as num?)?.toInt() ?? 4;

        final list = byTid[tid] ?? const <Map<String, dynamic>>[];

        final total = list.length;
        final played = list.where((x) => (x['finished'] as bool?) == true).length;

        final table = _calcPoints(list, teamsCount);
        final top1 = _topN(table, 1);
        final winnerName = top1.isEmpty ? '—' : _teamName(top1[0].key);
        final winnerPts = top1.isEmpty ? 0 : top1[0].value;

        t['_played'] = played;
        t['_total'] = total;
        t['_winner'] = winnerName;
        t['_winnerPts'] = winnerPts;
        t['_top3'] = _top3Text(table);
      }

      _tournaments = tournaments;
    } catch (e) {
      debugPrint('❌ Ошибка истории: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка истории: $e')),
        );
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('История турниров'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tournaments.isEmpty
              ? const Center(child: Text('Пока нет турниров'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tournaments.length,
                  itemBuilder: (_, i) {
                    final t = _tournaments[i];
                    final id = t['id'].toString();
                    final date = _formatDate(t['date']);
                    final teamsCount = (t['teams_count'] ?? '').toString();
                    final rounds = (t['rounds'] ?? '').toString();
                    final completed = (t['completed'] as bool?) ?? false;

                    final played = (t['_played'] ?? 0).toString();
                    final total = (t['_total'] ?? 0).toString();
                    final winner = (t['_winner'] ?? '—').toString();
                    final winnerPts = (t['_winnerPts'] ?? 0).toString();
                    final top3 = (t['_top3'] ?? '—').toString();

                    final subtitle = [
                      '$teamsCount команд • $rounds кругов',
                      'Сыграно: $played/$total',
                      completed ? 'Победитель: $winner ($winnerPts оч.)' : 'Лидер: $winner ($winnerPts оч.)',
                      'Топ-3: $top3',
                    ].join('\n');

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: Icon(completed ? Icons.check_circle : Icons.timelapse),
                        title: Text(date),
                        subtitle: Text(subtitle),
                        isThreeLine: true,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SchedulePage(
                                tournamentId: id,
                                hallId: widget.hallId,
                                teamName: (k) => 'Команда ${String.fromCharCode(65 + k)}',
                                teams: null,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
