import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth/auth_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://svfiiceaadjuzdusxqek.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN2ZmlpY2VhYWRqdXpkdXN4cWVrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA4MDI5MDMsImV4cCI6MjA4NjM3ODkwM30.IkPmZ0nimPBoFKXEgSBd6--nWJu0EsYeS0CmBtekgRk',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AuthPage(),
    );
  }
}
