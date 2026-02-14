import 'package:flutter/material.dart';

import '../../tournaments/ui/create_tournament_page.dart';
import '../../tournaments/ui/tournaments_history_page.dart';

class HallTournamentsPage extends StatelessWidget {
  const HallTournamentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.add_circle_outline),
            title: const Text('Создать турнир'),
            subtitle: const Text('Новый турнир / матч'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CreateTournamentPage(),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        Card(
          child: ListTile(
            leading: const Icon(Icons.history),
            title: const Text('История турниров'),
            subtitle: const Text('Список завершённых турниров'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const TournamentHistoryPage(),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 24),

        // Можем позже заменить на Supabase-реалтайм список турниров зала
        const Text(
          'ℹ️ Сейчас турнирный флоу работает локально.\n'
          'Supabase подключим следующим шагом: турниры/матчи/события будут храниться в облаке.',
          style: TextStyle(fontSize: 13, height: 1.4, color: Colors.black54),
        ),
      ],
    );
  }
}
