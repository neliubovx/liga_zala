import 'package:flutter/material.dart';
import 'select_players_page.dart';

class CreateTournamentPage extends StatefulWidget {
  final String hallId;

  const CreateTournamentPage({
    super.key,
    required this.hallId,
  });

  @override
  State<CreateTournamentPage> createState() => _CreateTournamentPageState();
}

class _CreateTournamentPageState extends State<CreateTournamentPage> {
  int _teamsCount = 4;
  int _playersPerTeam = 4;
  int _rounds = 3;

  DateTime _selectedDate = DateTime.now();

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Создание турнира'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // 📅 ДАТА
            const Text(
              'Дата турнира',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),

            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.grey.shade400,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDate(_selectedDate),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const Icon(Icons.calendar_today, size: 18),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // КОМАНДЫ
            const Text(
              'Количество команд',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Wrap(
              spacing: 8,
              children: [3, 4, 5].map((c) {
                return ChoiceChip(
                  label: Text('$c'),
                  selected: _teamsCount == c,
                  onSelected: (_) => setState(() => _teamsCount = c),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // ИГРОКИ
            const Text(
              'Игроков в команде',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Wrap(
              spacing: 8,
              children: [3, 4, 5].map((p) {
                return ChoiceChip(
                  label: Text('$p'),
                  selected: _playersPerTeam == p,
                  onSelected: (_) => setState(() => _playersPerTeam = p),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // КРУГИ
            const Text(
              'Количество кругов',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Wrap(
              spacing: 8,
              children: [1, 2, 3, 4, 5].map((r) {
                return ChoiceChip(
                  label: Text('$r'),
                  selected: _rounds == r,
                  onSelected: (_) => setState(() => _rounds = r),
                );
              }).toList(),
            ),

            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SelectPlayersPage(
                      hallId: widget.hallId, // ✅ ключевой параметр
                      teamsCount: _teamsCount,
                      playersPerTeam: _playersPerTeam,
                      rounds: _rounds,
                      tournamentDate: _selectedDate,
                    ),
                  ),
                );
              },
              child: const Text('Далее'),
            ),
          ],
        ),
      ),
    );
  }
}
