import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../hall/hall_list_page.dart';

class CityListPage extends StatefulWidget {
  const CityListPage({super.key});

  @override
  State<CityListPage> createState() => _CityListPageState();
}

class _CityListPageState extends State<CityListPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _cities = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  Future<void> _loadCities() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await supabase
          .from('cities')
          .select('id, name')
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 12));

      _cities = (data as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _cities = const [];
      _error = _friendlyLoadError(e);
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _createCity() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Создать город'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Название города',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              final cityName = controller.text.trim();
              if (cityName.isEmpty) return;

              try {
                await supabase
                    .from('cities')
                    .insert({'name': cityName})
                    .timeout(const Duration(seconds: 12));

                if (!mounted) return;
                Navigator.pop(context);
                await _loadCities();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Не удалось создать город. $_friendlyCreateHint')),
                );
              }
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Выберите город'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createCity,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _loadCities,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadCities,
                        child: const Text('Повторить'),
                      ),
                    ],
                  )
                : _cities.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text(
                              'Пока нет городов.\nНажми "+" чтобы создать.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _cities.length,
                        itemBuilder: (_, index) {
                          final city = _cities[index];
                          final cityId = (city['id'] ?? '').toString();
                          final cityName = (city['name'] ?? 'Без названия').toString();

                          return ListTile(
                            title: Text(cityName),
                            onTap: cityId.isEmpty
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => HallListPage(
                                          cityId: cityId,
                                          cityName: cityName,
                                        ),
                                      ),
                                    );
                                  },
                          );
                        },
                      ),
      ),
    );
  }

  static const String _friendlyCreateHint =
      'Проверь интернет/VPN и попробуй снова.';

  String _friendlyLoadError(Object error) {
    final text = error.toString().toLowerCase();
    final isNetworkIssue = text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('network') ||
        text.contains('dns') ||
        text.contains('timed out') ||
        text.contains('timeout');

    if (isNetworkIssue) {
      return 'Не удалось загрузить города. Проверь интернет/VPN и нажми "Повторить".';
    }

    return 'Не удалось загрузить города. Нажми "Повторить".';
  }
}
