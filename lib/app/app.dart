import 'package:flutter/material.dart';
import 'router.dart';
import 'app_state.dart';
import '../features/halls/ui/city_page.dart';
import '../features/home/home_page.dart';

class LigaZalaApp extends StatelessWidget {
  const LigaZalaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Лига Зала',
      home: AppState.instance.hasHall
          ? const HomePage()
          : CityPage(),
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
