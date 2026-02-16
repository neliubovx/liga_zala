import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:liga_zala/city/city_list_page.dart';
import 'package:liga_zala/data/cities_halls_cache.dart';
import 'package:liga_zala/features/tournaments/ui/tournaments_history_page.dart';
import 'package:liga_zala/hall/hall_list_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PlannedHttpClient httpClient;

  setUpAll(() async {
    httpClient = _PlannedHttpClient();
    SharedPreferences.setMockInitialValues({});

    await Supabase.initialize(
      url: 'http://localhost:54321',
      anonKey: 'test-anon-key',
      httpClient: httpClient,
      debug: false,
      authOptions: FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
      ),
    );
  });

  setUp(() async {
    await CitiesHallsCache.instance.clearAll();
  });

  tearDown(() {
    httpClient.clear();
  });

  tearDownAll(() async {
    await Supabase.instance.dispose();
  });

  testWidgets('CityListPage handles error and reloads after retry', (
    WidgetTester tester,
  ) async {
    httpClient.setPlan('GET', '/rest/v1/cities', [
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.json([
        {'id': 'city-1', 'name': 'Красноярск'},
      ], delay: const Duration(milliseconds: 120)),
    ]);

    await tester.pumpWidget(const MaterialApp(home: CityListPage()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));

    expect(find.textContaining('Не удалось загрузить города'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));

    expect(httpClient.callCount('GET', '/rest/v1/cities'), 4);
    expect(find.text('Красноярск'), findsOneWidget);
  });

  testWidgets('CityListPage keeps cached data and shows offline banner', (
    WidgetTester tester,
  ) async {
    await CitiesHallsCache.instance.writeCities([
      {'id': 'city-1', 'name': 'Красноярск'},
    ]);

    httpClient.setPlan('GET', '/rest/v1/cities', [
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.error(const SocketException('Failed host lookup')),
    ]);

    await tester.pumpWidget(const MaterialApp(home: CityListPage()));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Красноярск'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Нет сети. Показаны сохраненные данные.'), findsOneWidget);
    expect(find.text('Обновить'), findsOneWidget);
    expect(httpClient.callCount('GET', '/rest/v1/cities'), 3);
  });

  testWidgets('HallListPage handles network failure and retry', (
    WidgetTester tester,
  ) async {
    httpClient.setPlan('GET', '/rest/v1/halls', [
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.json([
        {'id': 'hall-1', 'city_id': 'city-1', 'name': 'Арена Север'},
      ], delay: const Duration(milliseconds: 120)),
    ]);

    await tester.pumpWidget(
      const MaterialApp(
        home: HallListPage(cityId: 'city-1', cityName: 'Красноярск'),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));

    expect(find.textContaining('Не удалось загрузить залы'), findsOneWidget);
    expect(find.text('Повторить'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));

    expect(httpClient.callCount('GET', '/rest/v1/halls'), 4);
    expect(find.text('Арена Север'), findsOneWidget);
    expect(find.textContaining('owner_id'), findsNothing);
  });

  testWidgets('HallListPage keeps cached data and shows offline banner', (
    WidgetTester tester,
  ) async {
    await CitiesHallsCache.instance.writeHalls('city-1', [
      {'id': 'hall-1', 'city_id': 'city-1', 'name': 'Арена Север'},
    ]);

    httpClient.setPlan('GET', '/rest/v1/halls', [
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.error(const SocketException('Failed host lookup')),
    ]);

    await tester.pumpWidget(
      const MaterialApp(
        home: HallListPage(cityId: 'city-1', cityName: 'Красноярск'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('Арена Север'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Нет сети. Показаны сохраненные данные.'), findsOneWidget);
    expect(find.text('Обновить'), findsOneWidget);
    expect(httpClient.callCount('GET', '/rest/v1/halls'), 3);
  });

  testWidgets('TournamentsHistoryPage handles network failure and retry', (
    WidgetTester tester,
  ) async {
    httpClient.setPlan('GET', '/rest/v1/tournaments', [
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.error(const SocketException('Failed host lookup')),
      _ResponseStep.json([
        {
          'id': 't-1',
          'date': '2026-03-01T10:00:00Z',
          'teams_count': 4,
          'rounds': 3,
          'completed': true,
        },
      ], delay: const Duration(milliseconds: 120)),
    ]);
    httpClient.setPlan('GET', '/rest/v1/matches', [
      _ResponseStep.json([
        {
          'tournament_id': 't-1',
          'home_team': 0,
          'away_team': 1,
          'home_score': 2,
          'away_score': 1,
          'finished': true,
        },
      ]),
    ]);

    await tester.pumpWidget(
      const MaterialApp(home: TournamentsHistoryPage(hallId: 'hall-1')),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));

    expect(
      find.textContaining('Не удалось загрузить историю турниров'),
      findsOneWidget,
    );
    expect(find.text('Повторить'), findsOneWidget);

    await tester.tap(find.text('Повторить'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(httpClient.callCount('GET', '/rest/v1/tournaments'), 4);
    expect(httpClient.callCount('GET', '/rest/v1/matches'), 1);
    expect(find.textContaining('01.03.2026'), findsOneWidget);
    expect(
      find.textContaining('Победитель: Команда A (3 оч.)'),
      findsOneWidget,
    );
  });

  testWidgets(
    'TournamentsHistoryPage keeps cached data and shows offline banner',
    (WidgetTester tester) async {
      await CitiesHallsCache.instance.writeTournamentHistory('hall-1', [
        {
          'id': 't-1',
          'date': '2026-03-01T10:00:00Z',
          'teams_count': 4,
          'rounds': 3,
          'completed': true,
          '_played': 1,
          '_total': 1,
          '_leader_name': 'Команда A',
          '_leader_code': 'A',
          '_leader_pts': 3,
          '_top3': [
            {
              'rank': 1,
              'team_name': 'Команда A',
              'team_code': 'A',
              'points': 3,
            },
            {
              'rank': 2,
              'team_name': 'Команда B',
              'team_code': 'B',
              'points': 0,
            },
            {
              'rank': 3,
              'team_name': 'Команда C',
              'team_code': 'C',
              'points': 0,
            },
          ],
        },
      ]);

      httpClient.setPlan('GET', '/rest/v1/tournaments', [
        _ResponseStep.error(const SocketException('Failed host lookup')),
        _ResponseStep.error(const SocketException('Failed host lookup')),
        _ResponseStep.error(const SocketException('Failed host lookup')),
      ]);

      await tester.pumpWidget(
        const MaterialApp(home: TournamentsHistoryPage(hallId: 'hall-1')),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.textContaining('01.03.2026'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));

      expect(
        find.text('Нет сети. Показаны сохраненные данные.'),
        findsOneWidget,
      );
      expect(find.text('Обновить'), findsOneWidget);
      expect(httpClient.callCount('GET', '/rest/v1/tournaments'), 3);
      expect(httpClient.callCount('GET', '/rest/v1/matches'), 0);
    },
  );
}

class _PlannedHttpClient extends http.BaseClient {
  final Map<String, List<_ResponseStep>> _plans = {};
  final List<String> _requestLog = [];

  void setPlan(String method, String path, List<_ResponseStep> steps) {
    _plans['$method $path'] = List<_ResponseStep>.from(steps);
  }

  int callCount(String method, String path) {
    final key = '${method.toUpperCase()} $path';
    return _requestLog.where((entry) => entry == key).length;
  }

  void clear() {
    _plans.clear();
    _requestLog.clear();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final key = '${request.method.toUpperCase()} ${request.url.path}';
    _requestLog.add(key);
    final queue = _plans[key];

    if (queue == null || queue.isEmpty) {
      return _jsonResponse({'ok': true}, request: request);
    }

    final step = queue.removeAt(0);
    if (step.delay != null) {
      await Future<void>.delayed(step.delay!);
    }

    if (step.error != null) {
      throw step.error!;
    }

    return _jsonResponse(step.body, request: request);
  }

  http.StreamedResponse _jsonResponse(
    Object? body, {
    int statusCode = 200,
    required http.BaseRequest request,
  }) {
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      statusCode,
      request: request,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

class _ResponseStep {
  final Object? body;
  final Object? error;
  final Duration? delay;

  const _ResponseStep.json(this.body, {this.delay}) : error = null;

  const _ResponseStep.error(this.error) : body = null, delay = null;
}

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> getItem({required String key}) async {
    return _values[key];
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }
}
