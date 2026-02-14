import 'package:flutter/material.dart';
import '../features/auth/auth_page.dart';
import '../features/auth/code_page.dart';
import '../features/home/home_page.dart';

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/':
        return MaterialPageRoute(
          builder: (_) => const AuthPage(),
        );

      case '/code':
        final phone = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => CodePage(phone: phone),
        );

      case '/home':
        return MaterialPageRoute(
          builder: (_) => const HomePage(),
        );

      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Страница не найдена')),
          ),
        );
    }
  }
}
