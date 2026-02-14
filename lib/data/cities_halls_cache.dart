import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CachedListSnapshot {
  final List<Map<String, dynamic>> items;
  final DateTime? storedAt;

  const CachedListSnapshot({required this.items, required this.storedAt});

  bool get hasItems => items.isNotEmpty;

  bool isFresh(Duration ttl) {
    final at = storedAt;
    if (at == null) return false;
    return DateTime.now().difference(at) <= ttl;
  }
}

class CitiesHallsCache {
  CitiesHallsCache._();

  static final CitiesHallsCache instance = CitiesHallsCache._();
  static const Duration ttl = Duration(minutes: 10);

  static const String _citiesDataKey = 'cache_v1_cities_data';
  static const String _citiesTsKey = 'cache_v1_cities_ts';

  List<Map<String, dynamic>>? _citiesMemory;
  DateTime? _citiesMemoryTs;

  final Map<String, List<Map<String, dynamic>>> _hallsMemory = {};
  final Map<String, DateTime?> _hallsMemoryTs = {};

  Future<CachedListSnapshot> readCities() async {
    if (_citiesMemory != null) {
      return CachedListSnapshot(
        items: _cloneRows(_citiesMemory!),
        storedAt: _citiesMemoryTs,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final rows = _decodeRows(prefs.getString(_citiesDataKey));
    final ts = _decodeTs(prefs.getInt(_citiesTsKey));

    _citiesMemory = rows;
    _citiesMemoryTs = ts;

    return CachedListSnapshot(items: _cloneRows(rows), storedAt: ts);
  }

  Future<void> writeCities(List<Map<String, dynamic>> rows) async {
    final normalized = _cloneRows(rows);
    final now = DateTime.now();

    _citiesMemory = normalized;
    _citiesMemoryTs = now;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_citiesDataKey, jsonEncode(normalized));
    await prefs.setInt(_citiesTsKey, now.millisecondsSinceEpoch);
  }

  Future<CachedListSnapshot> readHalls(String cityId) async {
    final memoryRows = _hallsMemory[cityId];
    if (memoryRows != null) {
      return CachedListSnapshot(
        items: _cloneRows(memoryRows),
        storedAt: _hallsMemoryTs[cityId],
      );
    }

    final prefs = await SharedPreferences.getInstance();
    final rows = _decodeRows(prefs.getString(_hallsDataKey(cityId)));
    final ts = _decodeTs(prefs.getInt(_hallsTsKey(cityId)));

    _hallsMemory[cityId] = rows;
    _hallsMemoryTs[cityId] = ts;

    return CachedListSnapshot(items: _cloneRows(rows), storedAt: ts);
  }

  Future<void> writeHalls(
    String cityId,
    List<Map<String, dynamic>> rows,
  ) async {
    final normalized = _cloneRows(rows);
    final now = DateTime.now();

    _hallsMemory[cityId] = normalized;
    _hallsMemoryTs[cityId] = now;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hallsDataKey(cityId), jsonEncode(normalized));
    await prefs.setInt(_hallsTsKey(cityId), now.millisecondsSinceEpoch);
  }

  Future<void> clearAll() async {
    _citiesMemory = null;
    _citiesMemoryTs = null;
    _hallsMemory.clear();
    _hallsMemoryTs.clear();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_citiesDataKey);
    await prefs.remove(_citiesTsKey);

    final hallKeys = prefs
        .getKeys()
        .where((k) => k.startsWith('cache_v1_halls_'))
        .toList(growable: false);

    for (final key in hallKeys) {
      await prefs.remove(key);
    }
  }

  static String _hallsDataKey(String cityId) => 'cache_v1_halls_${cityId}_data';
  static String _hallsTsKey(String cityId) => 'cache_v1_halls_${cityId}_ts';

  static List<Map<String, dynamic>> _cloneRows(
    List<Map<String, dynamic>> rows,
  ) {
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _decodeRows(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const [];

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];

      final rows = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is Map) {
          rows.add(Map<String, dynamic>.from(item));
        }
      }
      return rows;
    } catch (_) {
      return const [];
    }
  }

  static DateTime? _decodeTs(int? millis) {
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
