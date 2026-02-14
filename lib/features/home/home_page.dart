import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../halls/ui/city_page.dart';

import 'pages/dashboard_page.dart';
import 'pages/players_page.dart';
import 'pages/matches_page.dart';
import 'pages/rating_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  Future<void> _onChangeHall() async {
    await AppState.instance.clearHall();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => const CityPage(),
      ),
      (_) => false,
    );
  }

  List<Widget> get _pages {
    final hallId = AppState.instance.currentHallId;

    return [
      const DashboardPage(),
      const PlayersTab(),
      const MatchesPage(),
      // Если hallId пока null — RatingPage сам должен это обработать
      RatingPage(hallId: hallId),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Лига Зала'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Сменить зал',
            onPressed: _onChangeHall,
          ),
        ],
      ),
      body: pages[_currentIndex],
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
            label: 'Матчи',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Рейтинг',
          ),
        ],
      ),
    );
  }
}
