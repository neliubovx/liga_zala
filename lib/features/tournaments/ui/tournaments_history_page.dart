import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/cities_halls_cache.dart';
import 'schedule_page.dart';

class TournamentsHistoryPage extends StatefulWidget {
  const TournamentsHistoryPage({super.key, required this.hallId});

  final String hallId;

  @override
  State<TournamentsHistoryPage> createState() => _TournamentsHistoryPageState();
}

class _TournamentsHistoryPageState extends State<TournamentsHistoryPage> {
  final supabase = Supabase.instance.client;
  final cache = CitiesHallsCache.instance;

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String? _cacheBanner;
  List<Map<String, dynamic>> _tournaments = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _formatDate(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return 'Без даты';

    final dt = DateTime.tryParse(text)?.toLocal();
    if (dt == null) return text;

    final date =
        '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year}';

    final hasTime = dt.hour != 0 || dt.minute != 0;
    if (!hasTime) return date;

    return '$date ${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _teamCode(int i) => String.fromCharCode(65 + i);
  String _teamName(int i) => 'Команда ${_teamCode(i)}';

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
      if (h < 0 || a < 0 || h >= teamsCount || a >= teamsCount) continue;

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
      ..sort((a, b) {
        final byPoints = b.value.compareTo(a.value);
        if (byPoints != 0) return byPoints;
        return a.key.compareTo(b.key);
      });
    return list.take(n).toList();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!mounted) return;

    if (_tournaments.isEmpty) {
      setState(() {
        _loading = true;
        _refreshing = false;
        _error = null;
        _cacheBanner = null;
      });
    } else {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    }

    if (!forceRefresh && _tournaments.isEmpty) {
      final cached = await cache.readTournamentHistory(widget.hallId);
      if (!mounted) return;
      if (cached.hasItems) {
        setState(() {
          _tournaments = cached.items;
          _loading = false;
          _refreshing = true;
          _cacheBanner = cached.isFresh(CitiesHallsCache.ttl)
              ? null
              : 'Показаны сохраненные данные. Нажми "Обновить", чтобы подтянуть свежие.';
        });
      }
    }

    try {
      final fresh = await _fetchHistoryWithRetry();
      await cache.writeTournamentHistory(widget.hallId, fresh);

      if (!mounted) return;
      setState(() {
        _tournaments = fresh;
        _loading = false;
        _refreshing = false;
        _error = null;
        _cacheBanner = null;
      });
    } catch (e) {
      if (!mounted) return;

      if (_tournaments.isNotEmpty) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _error = null;
          _cacheBanner = _friendlyCachedBanner(e);
        });
        return;
      }

      setState(() {
        _tournaments = const [];
        _loading = false;
        _refreshing = false;
        _error = _friendlyLoadError(e);
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchHistoryWithRetry() {
    return _runWithRetry<List<Map<String, dynamic>>>(() async {
      final tRows = await supabase
          .from('tournaments')
          .select('id, date, teams_count, rounds, completed')
          .eq('hall_id', widget.hallId)
          .order('date', ascending: false)
          .timeout(const Duration(seconds: 12));

      final tournaments = (tRows as List).cast<Map<String, dynamic>>();
      if (tournaments.isEmpty) return const [];

      final ids = tournaments.map((t) => t['id'].toString()).toList();
      final mRows = await supabase
          .from('matches')
          .select(
            'tournament_id, home_team, away_team, home_score, away_score, finished',
          )
          .inFilter('tournament_id', ids)
          .timeout(const Duration(seconds: 12));

      final matchesAll = (mRows as List).cast<Map<String, dynamic>>();
      final byTid = <String, List<Map<String, dynamic>>>{};
      for (final m in matchesAll) {
        final tid = m['tournament_id']?.toString() ?? '';
        if (tid.isEmpty) continue;
        (byTid[tid] ??= []).add(m);
      }

      final enriched = <Map<String, dynamic>>[];
      for (final row in tournaments) {
        final t = Map<String, dynamic>.from(row);
        final tid = t['id']?.toString() ?? '';
        final teamsCountRaw = (t['teams_count'] as num?)?.toInt() ?? 4;
        final teamsCount = teamsCountRaw < 2 ? 2 : teamsCountRaw;

        final list = byTid[tid] ?? const <Map<String, dynamic>>[];
        final total = list.length;
        final played = list
            .where((x) => (x['finished'] as bool?) == true)
            .length;

        final table = _calcPoints(list, teamsCount);
        final ranking = _topN(table, 3);
        final leader = ranking.isEmpty ? null : ranking.first;

        t['_played'] = played;
        t['_total'] = total;
        t['_leader_name'] = leader == null ? '—' : _teamName(leader.key);
        t['_leader_code'] = leader == null ? '—' : _teamCode(leader.key);
        t['_leader_pts'] = leader?.value ?? 0;
        t['_top3'] = ranking
            .asMap()
            .entries
            .map(
              (entry) => <String, dynamic>{
                'rank': entry.key + 1,
                'team_name': _teamName(entry.value.key),
                'team_code': _teamCode(entry.value.key),
                'points': entry.value.value,
              },
            )
            .toList(growable: false);

        enriched.add(t);
      }

      return enriched;
    });
  }

  Future<T> _runWithRetry<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } catch (e) {
        lastError = e;
        final canRetry = _isNetworkIssue(e) && attempt < maxAttempts;
        if (!canRetry) break;
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }
    throw lastError ?? Exception('Неизвестная ошибка загрузки');
  }

  String _friendlyCachedBanner(Object error) {
    if (_isNetworkIssue(error)) {
      return 'Нет сети. Показаны сохраненные данные.';
    }
    return 'Обновить историю сейчас не удалось. Показаны сохраненные данные.';
  }

  String _friendlyLoadError(Object error) {
    if (_isNetworkIssue(error)) {
      return 'Не удалось загрузить историю турниров. Проверь интернет/VPN и нажми "Повторить".';
    }
    return 'Не удалось загрузить историю турниров. Нажми "Повторить".';
  }

  bool _isNetworkIssue(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('network') ||
        text.contains('dns') ||
        text.contains('timed out') ||
        text.contains('timeout');
  }

  Widget _buildCacheBanner(String text) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          TextButton(
            onPressed: () => _load(forceRefresh: true),
            child: const Text('Обновить'),
          ),
        ],
      ),
    );
  }

  Widget _buildTop3(List<dynamic> rows) {
    if (rows.isEmpty) {
      return const Text('Топ-3: —', style: TextStyle(color: Colors.black54));
    }

    final chips = <Widget>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final rank = (row['rank'] as num?)?.toInt() ?? 0;
      final code = (row['team_code'] ?? '?').toString();
      final points = (row['points'] as num?)?.toInt() ?? 0;
      chips.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('$rank) $code • $points'),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _buildTournamentCard(Map<String, dynamic> t) {
    final id = t['id'].toString();
    final date = _formatDate(t['date']);
    final teamsCount = (t['teams_count'] as num?)?.toInt() ?? 0;
    final rounds = (t['rounds'] as num?)?.toInt() ?? 0;
    final completed = (t['completed'] as bool?) ?? false;

    final played = (t['_played'] as num?)?.toInt() ?? 0;
    final total = (t['_total'] as num?)?.toInt() ?? 0;
    final leaderCode = (t['_leader_code'] ?? '—').toString();
    final leaderPts = (t['_leader_pts'] as num?)?.toInt() ?? 0;
    final top3Rows = (t['_top3'] as List?) ?? const <dynamic>[];

    final progress = total <= 0 ? 0.0 : (played / total).clamp(0.0, 1.0);
    final leaderTitle = completed ? 'Победитель' : 'Лидер';

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SchedulePage(
                tournamentId: id,
                hallId: widget.hallId,
                teamName: (k) => _teamName(k),
                teams: null,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      date,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: completed
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      completed ? 'Завершён' : 'Идёт',
                      style: TextStyle(
                        color: completed
                            ? Colors.green.shade800
                            : Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('$teamsCount команд • $rounds кругов'),
              const SizedBox(height: 8),
              Text('Сыграно: $played/$total'),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(minHeight: 6, value: progress),
              ),
              const SizedBox(height: 10),
              Text('$leaderTitle: Команда $leaderCode ($leaderPts оч.)'),
              const SizedBox(height: 8),
              _buildTop3(top3Rows),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _tournaments.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_error != null && _tournaments.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _load(forceRefresh: true),
            child: const Text('Повторить'),
          ),
        ],
      );
    }

    final children = <Widget>[
      if (_refreshing) const LinearProgressIndicator(minHeight: 2),
      if (_cacheBanner != null) _buildCacheBanner(_cacheBanner!),
    ];

    if (_tournaments.isEmpty) {
      children.addAll(const [
        SizedBox(height: 120),
        Center(child: Text('Пока нет турниров')),
      ]);
    } else {
      children.addAll(_tournaments.map(_buildTournamentCard));
      children.add(const SizedBox(height: 16));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
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
            onPressed: () => _load(forceRefresh: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: _buildBody(),
      ),
    );
  }
}
