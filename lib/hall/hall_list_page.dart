import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'hall_home_page.dart';

class HallListPage extends StatefulWidget {
  final String cityId;
  final String cityName;

  const HallListPage({
    super.key,
    required this.cityId,
    required this.cityName,
  });

  @override
  State<HallListPage> createState() => _HallListPageState();
}

class _HallListPageState extends State<HallListPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _halls = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await supabase
          .from('halls')
          .select('id, city_id, name')
          .eq('city_id', widget.cityId)
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 12));

      _halls = (res as List).cast<Map<String, dynamic>>();
    } catch (e) {
      _error = _friendlyLoadError(e);
      _halls = const [];
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _createHall() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Новый зал'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Название зала',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      await supabase
          .from('halls')
          .insert({
            'city_id': widget.cityId,
            'name': name,
          })
          .timeout(const Duration(seconds: 12));

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось создать зал. Проверь интернет/VPN и попробуй снова.')),
      );
    }
  }

  String _s(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cityName),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createHall,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: const [
                  SizedBox(height: 180),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('Повторить'),
                      ),
                    ],
                  )
                : _halls.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(16),
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Text(
                              'Пока нет залов в этом городе.\nНажми "+" чтобы создать.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: _halls.length,
                        itemBuilder: (context, index) {
                          final h = _halls[index];
                          final hallId = _s(h['id']);
                          final hallName = _s(h['name']).isEmpty ? 'Без названия' : _s(h['name']);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(
                                hallName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => HallHomePage(
                                      hallId: hallId,
                                      hallName: hallName,
                                      isOwner: false, // пока владельца в БД нет
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
      ),
    );
  }

  String _friendlyLoadError(Object error) {
    final text = error.toString().toLowerCase();

    if (text.contains('owner_id')) {
      return 'Не удалось загрузить залы: поле owner_id отсутствует в таблице halls. '
          'Проверь схему БД и нажми "Повторить".';
    }

    final isNetworkIssue = text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('network') ||
        text.contains('dns') ||
        text.contains('timed out') ||
        text.contains('timeout');

    if (isNetworkIssue) {
      return 'Не удалось загрузить залы. Проверь интернет/VPN и нажми "Повторить".';
    }

    return 'Не удалось загрузить залы. Нажми "Повторить".';
  }
}
