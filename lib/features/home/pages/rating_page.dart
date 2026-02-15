import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../rating/rating_formula.dart';

class RatingPage extends StatefulWidget {
  final String hallId;

  const RatingPage({super.key, required this.hallId});

  @override
  State<RatingPage> createState() => _RatingPageState();
}

class _RatingPageState extends State<RatingPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _rating = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRating();
  }

  Future<void> _loadRating() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await supabase
          .from('v_hall_player_stats')
          .select(
            'hall_id, user_id, name, tournaments, matches_played, wins, draws, losses, points, goals, assists, mvp_count, wins_4, draws_4, updated_at',
          )
          .eq('hall_id', widget.hallId);

      final rows = (data as List)
          .cast<Map<String, dynamic>>()
          .where((row) => RatingFormula.asString(row['user_id']).isNotEmpty)
          .toList();

      rows.sort(RatingFormula.compareRows);

      if (!mounted) return;
      setState(() {
        _rating = rows;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки рейтинга: $e');
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось загрузить рейтинг. Нажми "Повторить".';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadRating,
      child: _loading
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 180),
                Center(child: CircularProgressIndicator()),
              ],
            )
          : _error != null
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _loadRating,
                  child: const Text('Повторить'),
                ),
              ],
            )
          : _rating.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 180),
                Center(child: Text('Пока нет статистики')),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _rating.length,
              itemBuilder: (_, index) {
                final player = _rating[index];

                final place = index + 1;
                final name =
                    RatingFormula.asString(player['name']).trim().isEmpty
                    ? 'Без имени'
                    : RatingFormula.asString(player['name']);
                final tournaments = RatingFormula.asInt(player['tournaments']);
                final wins = RatingFormula.asInt(player['wins']);
                final draws = RatingFormula.asInt(player['draws']);
                final gpa = RatingFormula.goalPlusAssist(player);
                final mvp = RatingFormula.asInt(player['mvp_count']);
                final total = RatingFormula.totalScore(player);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  child: ListTile(
                    leading: Text(
                      '$place',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'Турниры: $tournaments | Победы: $wins | Ничьи: $draws | Г+П: $gpa | MVP: $mvp',
                    ),
                    trailing: Text(
                      total.toStringAsFixed(3),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
