import 'package:flutter/material.dart';

import 'package:liga_zala/features/home/pages/matches_page.dart';
import 'package:liga_zala/hall/hall_admin_page.dart';
import 'package:liga_zala/hall/hall_players_tab.dart';
import 'package:liga_zala/hall/hall_rating_tab.dart';

class HallHomePage extends StatefulWidget {
  final String hallId;
  final String hallName;
  final bool isOwner;

  const HallHomePage({
    super.key,
    required this.hallId,
    required this.hallName,
    required this.isOwner,
  });

  @override
  State<HallHomePage> createState() => _HallHomePageState();
}

class _HallHomePageState extends State<HallHomePage> {
  int _currentIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    _pages = [
      const _HomeTab(),
      HallPlayersTab(
        hallId: widget.hallId,
        isOwner: widget.isOwner,
      ),
      MatchesPage(hallId: widget.hallId),
      HallRatingTab(hallId: widget.hallId),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.hallName),
        actions: [
          if (widget.isOwner)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HallAdminPage(
                      hallId: widget.hallId,
                      hallName: widget.hallName,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Главная',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.group),
            label: 'Игроки',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_soccer),
            label: 'Турниры',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard),
            label: 'Рейтинг',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Главная зала\n\n'
        'Здесь будет:\n'
        '• Чат\n'
        '• Голосования\n'
        '• Следующий турнир\n'
        '• Объявления',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16),
      ),
    );
  }
}
