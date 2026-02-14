import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RatingPage extends StatefulWidget {
  final String hallId;

  const RatingPage({super.key, required this.hallId});

  @override
  State<RatingPage> createState() => _RatingPageState();
}

class _RatingPageState extends State<RatingPage> {
  final supabase = Supabase.instance.client;

  List<dynamic> _rating = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRating();
  }

  Future<void> _loadRating() async {
    try {
      final data = await supabase.rpc(
        'calculate_rating',
        params: {'p_hall': widget.hallId},
      );

      setState(() {
        _rating = data;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки рейтинга: $e');
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_rating.isEmpty) {
      return const Center(
        child: Text('Пока нет статистики'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _rating.length,
      itemBuilder: (_, index) {
        final player = _rating[index];

        final place = index + 1;
        final name = player['display_name'] ?? 'Без имени';
        final tournaments = player['tournaments'] ?? 0;
        final wins = player['wins'] ?? 0;
        final draws = player['draws'] ?? 0;
        final gpa = player['goal_plus_assist'] ?? 0;
        final total = player['total_score'] ?? 0;

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
              'Турниры: $tournaments  |  Победы: $wins  |  Ничьи: $draws  |  Г+П: $gpa',
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
    );
  }
}
