import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../city/city_list_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;

  Future<void> _signInOrSignUp() async {
    setState(() => _loading = true);

    final supabase = Supabase.instance.client;

    try {
      final response =
          await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      print("✅ Вход успешен: ${response.user?.email}");
    } catch (_) {
      // если вход не удался — пробуем регистрацию
      try {
        final response =
            await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        final userId = response.user?.id;

        if (userId != null) {
          await supabase
              .from('profiles')
              .update({
                'display_name': _nameController.text.trim(),
              })
              .eq('id', userId);
        }

        print("✅ Регистрация успешна");
      } catch (e) {
        print("❌ Ошибка регистрации: $e");
      }
    }

    setState(() => _loading = false);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const CityListPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Лига Зала',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),

                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _loading ? null : _signInOrSignUp,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text('Войти / Регистрация'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
