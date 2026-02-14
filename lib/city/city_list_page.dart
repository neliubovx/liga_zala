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

  List<dynamic> _cities = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  Future<void> _loadCities() async {
    final data = await supabase.from('cities').select();
    setState(() {
      _cities = data;
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
              await supabase.from('cities').insert({
                'name': controller.text.trim(),
              });
              Navigator.pop(context);
              _loadCities();
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _cities.length,
              itemBuilder: (_, index) {
                final city = _cities[index];

                return ListTile(
                  title: Text(city['name']),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HallListPage(
                          cityId: city['id'],
                          cityName: city['name'],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
