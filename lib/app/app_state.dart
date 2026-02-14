import 'package:shared_preferences/shared_preferences.dart';
import '../features/halls/model/hall.dart';

class AppState {
  AppState._internal();

  static final AppState instance = AppState._internal();

  Hall? selectedHall;

  static const _hallIdKey = 'hall_id';
  static const _hallCityKey = 'hall_city';
  static const _hallNameKey = 'hall_name';

  bool get hasHall => selectedHall != null;

  /// ✅ Совместимость со старым кодом
  /// Во многих экранах используется AppState.instance.currentHallId
  String? get currentHallId => selectedHall?.id;

  /// Загружаем сохранённый зал при старте приложения
  Future<void> loadHall() async {
    final prefs = await SharedPreferences.getInstance();

    final id = prefs.getString(_hallIdKey);
    final city = prefs.getString(_hallCityKey);
    final name = prefs.getString(_hallNameKey);

    if (id != null && city != null && name != null) {
      selectedHall = Hall(
        id: id,
        city: city,
        name: name,
      );
    }
  }

  /// Выбор и сохранение зала
  Future<void> selectHall(Hall hall) async {
    selectedHall = hall;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hallIdKey, hall.id);
    await prefs.setString(_hallCityKey, hall.city);
    await prefs.setString(_hallNameKey, hall.name);
  }

  /// Очистка выбранного зала (на будущее — «Сменить зал»)
  Future<void> clearHall() async {
    selectedHall = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hallIdKey);
    await prefs.remove(_hallCityKey);
    await prefs.remove(_hallNameKey);
  }
}
