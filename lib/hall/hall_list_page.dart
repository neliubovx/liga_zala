import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/cities_halls_cache.dart';
import 'hall_home_page.dart';

class HallListPage extends StatefulWidget {
  final String cityId;
  final String cityName;

  const HallListPage({super.key, required this.cityId, required this.cityName});

  @override
  State<HallListPage> createState() => _HallListPageState();
}

class _HallListPageState extends State<HallListPage> {
  final supabase = Supabase.instance.client;
  final cache = CitiesHallsCache.instance;

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String? _cacheBanner;
  List<Map<String, dynamic>> _halls = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!mounted) return;

    if (_halls.isEmpty) {
      setState(() {
        _loading = true;
        _refreshing = false;
        _error = null;
        _cacheBanner = null;
      });
    } else {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    }

    if (!forceRefresh && _halls.isEmpty) {
      final cached = await cache.readHalls(widget.cityId);
      if (!mounted) return;
      if (cached.hasItems) {
        setState(() {
          _halls = cached.items;
          _loading = false;
          _refreshing = true;
          _cacheBanner = cached.isFresh(CitiesHallsCache.ttl)
              ? null
              : 'Показаны сохраненные данные. Нажми "Обновить", чтобы подтянуть свежие.';
        });
      }
    }

    try {
      final fresh = await _fetchHallsWithRetry();
      await cache.writeHalls(widget.cityId, fresh);

      if (!mounted) return;
      setState(() {
        _halls = fresh;
        _loading = false;
        _refreshing = false;
        _error = null;
        _cacheBanner = null;
      });
    } catch (e) {
      if (!mounted) return;

      if (_halls.isNotEmpty) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _error = null;
          _cacheBanner = _friendlyCachedBanner(e);
        });
        return;
      }

      setState(() {
        _halls = const [];
        _loading = false;
        _refreshing = false;
        _error = _friendlyLoadError(e);
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchHallsWithRetry() {
    return _runWithRetry<List<Map<String, dynamic>>>(() async {
      final res = await supabase
          .from('halls')
          .select('id, city_id, name')
          .eq('city_id', widget.cityId)
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 12));

      return (res as List).cast<Map<String, dynamic>>();
    });
  }

  Future<T> _runWithRetry<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
  }) async {
    Object? lastError;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } catch (e) {
        lastError = e;
        final canRetry = _isNetworkIssue(e) && attempt < maxAttempts;
        if (!canRetry) break;
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
    }

    throw lastError ?? Exception('Неизвестная ошибка загрузки');
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
          .insert({'city_id': widget.cityId, 'name': name})
          .timeout(const Duration(seconds: 12));

      await _load(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось создать зал. Проверь интернет/VPN и попробуй снова.',
          ),
        ),
      );
    }
  }

  String _s(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.cityName)),
      floatingActionButton: FloatingActionButton(
        onPressed: _createHall,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(forceRefresh: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _halls.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_error != null && _halls.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _load(forceRefresh: true),
            child: const Text('Повторить'),
          ),
        ],
      );
    }

    final children = <Widget>[
      if (_refreshing) const LinearProgressIndicator(minHeight: 2),
      if (_cacheBanner != null) _buildCacheBanner(_cacheBanner!),
    ];

    if (_halls.isEmpty) {
      children.addAll(const [
        SizedBox(height: 120),
        Center(
          child: Text(
            'Пока нет залов в этом городе.\nНажми "+" чтобы создать.',
            textAlign: TextAlign.center,
          ),
        ),
      ]);
    } else {
      children.addAll(
        _halls.map((h) {
          final hallId = _s(h['id']);
          final hallName = _s(h['name']).isEmpty
              ? 'Без названия'
              : _s(h['name']);

          return Card(
            margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
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
        }),
      );

      children.add(const SizedBox(height: 20));
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }

  Widget _buildCacheBanner(String text) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          TextButton(
            onPressed: () => _load(forceRefresh: true),
            child: const Text('Обновить'),
          ),
        ],
      ),
    );
  }

  String _friendlyCachedBanner(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('owner_id')) {
      return 'Показаны сохраненные данные. Проверь схему БД (owner_id) и нажми "Обновить".';
    }
    if (_isNetworkIssue(error)) {
      return 'Нет сети. Показаны сохраненные данные.';
    }
    return 'Обновить список сейчас не удалось. Показаны сохраненные данные.';
  }

  String _friendlyLoadError(Object error) {
    final text = error.toString().toLowerCase();

    if (text.contains('owner_id')) {
      return 'Не удалось загрузить залы: поле owner_id отсутствует в таблице halls. '
          'Проверь схему БД и нажми "Повторить".';
    }

    if (_isNetworkIssue(error)) {
      return 'Не удалось загрузить залы. Проверь интернет/VPN и нажми "Повторить".';
    }

    return 'Не удалось загрузить залы. Нажми "Повторить".';
  }

  bool _isNetworkIssue(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('failed host lookup') ||
        text.contains('socketexception') ||
        text.contains('network') ||
        text.contains('dns') ||
        text.contains('timed out') ||
        text.contains('timeout');
  }
}
