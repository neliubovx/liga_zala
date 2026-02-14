import '../model/hall.dart';

class HallsRepository {
  HallsRepository._internal();

  static final HallsRepository instance = HallsRepository._internal();

  final List<Hall> _halls = [
    Hall(id: '1', city: 'Москва', name: 'Зал Арена'),
    Hall(id: '2', city: 'Москва', name: 'Футбол Холл'),
    Hall(id: '3', city: 'Санкт-Петербург', name: 'Питер Зал'),
    Hall(id: '4', city: 'Новосибирск', name: 'Сибирь Арена'),
  ];

  List<String> getCities() {
    return _halls.map((h) => h.city).toSet().toList();
  }

  List<Hall> getByCity(String city) {
    return _halls.where((h) => h.city == city).toList();
  }
}
