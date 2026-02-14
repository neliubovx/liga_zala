import 'package:flutter/material.dart';
import '../data/halls_repository.dart';
import 'hall_page.dart';

class CityPage extends StatelessWidget {
  CityPage({super.key});

  final _repo = HallsRepository.instance;

  @override
  Widget build(BuildContext context) {
    final cities = _repo.getCities();

    return Scaffold(
      appBar: AppBar(title: const Text('Выбор города')),
      body: ListView.builder(
        itemCount: cities.length,
        itemBuilder: (_, index) {
          final city = cities[index];
          return ListTile(
            title: Text(city),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HallPage(city: city),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
