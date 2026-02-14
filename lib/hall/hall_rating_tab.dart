import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HallRatingTab extends StatefulWidget {
  final String hallId;

  const HallRatingTab({
    super.key,
    required this.hallId,
  });

  @override
  State<HallRatingTab> createState() => _HallRatingTabState();
}

class _HallRatingTabState extends State<HallRatingTab> {
  final supabase = Supabase.instance.client;

  // 🔧 коэффициенты формулы
  static const double coefTournaments = 0.3;
  static const double coefWins = 0.3;
  static const double coefDraws = 0.1;
  static const double coefGoalAssist = 0.025;
  static const double coefMvp = 0.25;

  // ⚠️ доп. коэффициент за формат 4 команды
  static const double coefFourTeam = 0.10;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await supabase
          .from('v_hall_player_stats')
          .select(
            'user_id, name, tournaments, matches_played, wins, draws, losses, points, goals, assists, mvp_count, wins_4, draws_4, updated_at',
          )
          .eq('hall_id', widget.hallId);

      _rows = (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _error = e.toString();
      _rows = const [];
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
  String _s(dynamic v) => (v ?? '').toString();

  double _ratingScore(Map<String, dynamic> r) {
    final t = _i(r['tournaments']);
    final w = _i(r['wins']);
    final d = _i(r['draws']);
    final goals = _i(r['goals']);
    final assists = _i(r['assists']);
    final mvp = _i(r['mvp_count']);
    final w4 = _i(r['wins_4']);
    final d4 = _i(r['draws_4']);

    final dop = (w4 + d4) * coefFourTeam;

    final score = (t * coefTournaments) +
        (w * coefWins) +
        (d * coefDraws) +
        ((goals + assists) * coefGoalAssist) +
        (mvp * coefMvp) +
        dop;

    return score;
  }

  List<Map<String, dynamic>> _filteredAndSorted() {
    final q = _query.trim().toLowerCase();

    final list = _rows.where((r) {
      if (q.isEmpty) return true;
      final name = _s(r['name']).toLowerCase();
      return name.contains(q);
    }).toList();

    list.sort((a, b) {
      final sa = _ratingScore(a);
      final sb = _ratingScore(b);

      final byScore = sb.compareTo(sa);
      if (byScore != 0) return byScore;

      // тай-брейкеры
      final bw = _i(b['wins']).compareTo(_i(a['wins']));
      if (bw != 0) return bw;

      final bp = _i(b['points']).compareTo(_i(a['points']));
      if (bp != 0) return bp;

      return _i(b['matches_played']).compareTo(_i(a['matches_played']));
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final data = _filteredAndSorted();

    return RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? ListView(
              children: const [
                SizedBox(height: 180),
                Center(child: CircularProgressIndicator()),
              ],
            )
          : _error != null
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Ошибка загрузки рейтинга:\n$_error',
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Повторить'),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        hintText: 'Поиск игрока…',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (data.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 90),
                        child: Center(
                          child: Text(
                            'Нет данных по запросу.\nПопробуй другой поиск.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      for (int index = 0; index < data.length; index++)
                        _PlayerRowCard(
                          index: index,
                          row: data[index],
                          score: _ratingScore(data[index]),
                        ),
                  ],
                ),
    );
  }
}

class _PlayerRowCard extends StatelessWidget {
  final int index;
  final Map<String, dynamic> row;
  final double score;

  const _PlayerRowCard({
    required this.index,
    required this.row,
    required this.score,
  });

  int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
  String _s(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final name = _s(row['name']).isEmpty ? 'Без имени' : _s(row['name']);

    final points = _i(row['points']);
    final mp = _i(row['matches_played']);
    final w = _i(row['wins']);
    final d = _i(row['draws']);
    final l = _i(row['losses']);
    final t = _i(row['tournaments']);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _PlayerStatsDetailsPage(row: row, score: score),
            ),
          );
        },
        leading: CircleAvatar(child: Text('${index + 1}')),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text('Турниры: $t • Матчи: $mp • $w-$d-$l • Очки: $points'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'Рейтинг',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Text(
              score.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerStatsDetailsPage extends StatelessWidget {
  final Map<String, dynamic> row;
  final double score;

  const _PlayerStatsDetailsPage({required this.row, required this.score});

  int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
  String _s(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final name = _s(row['name']).isEmpty ? 'Без имени' : _s(row['name']);

    final tournaments = _i(row['tournaments']);
    final matches = _i(row['matches_played']);
    final wins = _i(row['wins']);
    final draws = _i(row['draws']);
    final losses = _i(row['losses']);
    final points = _i(row['points']);

    final goals = _i(row['goals']);
    final assists = _i(row['assists']);
    final mvp = _i(row['mvp_count']);
    final wins4 = _i(row['wins_4']);
    final draws4 = _i(row['draws_4']);

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatRow(label: 'Рейтинг', value: score.toStringAsFixed(2)),
          const Divider(height: 24),
          _StatRow(label: 'Очки (3/1/0)', value: '$points'),
          _StatRow(label: 'Турниры', value: '$tournaments'),
          _StatRow(label: 'Матчи', value: '$matches'),
          _StatRow(
            label: 'Победы / Ничьи / Поражения',
            value: '$wins / $draws / $losses',
          ),
          const Divider(height: 24),
          _StatRow(label: 'Голы', value: '$goals'),
          _StatRow(label: 'Пасы', value: '$assists'),
          _StatRow(label: 'MVP', value: '$mvp'),
          const Divider(height: 24),
          _StatRow(label: 'Победы (4 команды)', value: '$wins4'),
          _StatRow(label: 'Ничьи (4 команды)', value: '$draws4'),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
