import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/cities_halls_cache.dart';
import '../hall/hall_list_page.dart';

class CityListPage extends StatefulWidget {
  const CityListPage({super.key});

  @override
  State<CityListPage> createState() => _CityListPageState();
}

class _CityListPageState extends State<CityListPage> {
  final supabase = Supabase.instance.client;
  final cache = CitiesHallsCache.instance;

  List<Map<String, dynamic>> _cities = const [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String? _cacheBanner;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  Future<void> _loadCities({bool forceRefresh = false}) async {
    if (!mounted) return;

    if (_cities.isEmpty) {
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

    if (!forceRefresh && _cities.isEmpty) {
      final cached = await cache.readCities();
      if (!mounted) return;
      if (cached.hasItems) {
        setState(() {
          _cities = cached.items;
          _loading = false;
          _refreshing = true;
          _cacheBanner = cached.isFresh(CitiesHallsCache.ttl)
              ? null
              : 'Показаны сохраненные данные. Нажми "Обновить", чтобы подтянуть свежие.';
        });
      }
    }

    try {
      final fresh = await _fetchCitiesWithRetry();
      await cache.writeCities(fresh);

      if (!mounted) return;
      setState(() {
        _cities = fresh;
        _loading = false;
        _refreshing = false;
        _error = null;
        _cacheBanner = null;
      });
    } catch (e) {
      if (!mounted) return;

      if (_cities.isNotEmpty) {
        setState(() {
          _loading = false;
          _refreshing = false;
          _error = null;
          _cacheBanner = _friendlyCachedBanner(e);
        });
        return;
      }

      setState(() {
        _cities = const [];
        _loading = false;
        _refreshing = false;
        _error = _friendlyLoadError(e);
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCitiesWithRetry() {
    return _runWithRetry<List<Map<String, dynamic>>>(() async {
      final data = await supabase
          .from('cities')
          .select('id, name')
          .order('name', ascending: true)
          .timeout(const Duration(seconds: 12));

      return (data as List).cast<Map<String, dynamic>>();
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

  Future<void> _createCity() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Создать город'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Название города'),
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
                await _loadCities(forceRefresh: true);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Не удалось создать город. $_friendlyCreateHint',
                    ),
                  ),
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
      appBar: AppBar(title: const Text('Выберите город')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createCity,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadCities(forceRefresh: true),
        child: _buildBody(),
      ),
    );
  }

  static const String _friendlyCreateHint =
      'Проверь интернет/VPN и попробуй снова.';

  Widget _buildBody() {
    if (_loading && _cities.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    if (_error != null && _cities.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => _loadCities(forceRefresh: true),
            child: const Text('Повторить'),
          ),
        ],
      );
    }

    final children = <Widget>[
      if (_refreshing) const LinearProgressIndicator(minHeight: 2),
      if (_cacheBanner != null) _buildCacheBanner(_cacheBanner!),
    ];

    if (_cities.isEmpty) {
      children.addAll(const [
        SizedBox(height: 120),
        Center(
          child: Text(
            'Пока нет городов.\nНажми "+" чтобы создать.',
            textAlign: TextAlign.center,
          ),
        ),
      ]);
    } else {
      children.addAll(
        _cities.map((city) {
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
                        builder: (_) =>
                            HallListPage(cityId: cityId, cityName: cityName),
                      ),
                    );
                  },
          );
        }),
      );
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
            onPressed: () => _loadCities(forceRefresh: true),
            child: const Text('Обновить'),
          ),
        ],
      ),
    );
  }

  String _friendlyCachedBanner(Object error) {
    if (_isNetworkIssue(error)) {
      return 'Нет сети. Показаны сохраненные данные.';
    }
    return 'Обновить список сейчас не удалось. Показаны сохраненные данные.';
  }

  String _friendlyLoadError(Object error) {
    if (_isNetworkIssue(error)) {
      return 'Не удалось загрузить города. Проверь интернет/VPN и нажми "Повторить".';
    }

    return 'Не удалось загрузить города. Нажми "Повторить".';
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
