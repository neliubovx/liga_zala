import 'package:flutter/material.dart';
import '../../../app/app_state.dart';
import '../data/halls_repository.dart';
import '../model/hall.dart';
import '../../home/home_page.dart';

class HallPage extends StatelessWidget {
  final String city;

  HallPage({super.key, required this.city});

  final _repo = HallsRepository.instance;

  @override
  Widget build(BuildContext context) {
    final halls = _repo.getByCity(city);

    return Scaffold(
      appBar: AppBar(title: Text(city)),
      body: ListView.builder(
        itemCount: halls.length,
        itemBuilder: (_, index) {
          final Hall hall = halls[index];
          return ListTile(
            title: Text(hall.name),
            onTap: () {
              AppState.instance.selectHall(hall);
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => const HomePage(),
                ),
                (_) => false,
              );
            },
          );
        },
      ),
    );
  }
}
