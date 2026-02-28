import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_page.dart';
import 'app/theme_controller.dart';
import 'notifications/push_token_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://svfiiceaadjuzdusxqek.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN2ZmlpY2VhYWRqdXpkdXN4cWVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4MDI5MDMsImV4cCI6MjA4NjM3ODkwM30.IkPmZ0nimPBoFKXEgSBd6--nWJu0EsYeS0CmBtekgRk',
  );
  await AppThemeController.instance.load();
  runApp(const MyApp());

  // Keep app startup resilient even if push init fails on device.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(PushTokenService.instance.start());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.instance.mode,
      builder: (context, mode, child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF6F4FB5),
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF6F4FB5),
          brightness: Brightness.dark,
        ),
        home: const AuthPage(),
      ),
    );
  }
}
