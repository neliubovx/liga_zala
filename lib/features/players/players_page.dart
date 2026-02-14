import 'package:flutter/material.dart';
import 'data/players_repository.dart';
import 'model/player.dart';

class PlayersPage extends StatefulWidget {
  const PlayersPage({super.key});

  @override
  State<PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends State<PlayersPage> {
  final PlayersRepository _repository = PlayersRepository.instance;

  void _addPlayer() async {
    final result = await showDialog<Player>(
      context: context,
      builder: (_) => const _AddPlayerDialog(),
    );

    if (result != null) {
      setState(() {
        _repository.add(result);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final players = _repository.getAll();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Игроки'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addPlayer,
          ),
        ],
      ),
      body: ListView.separated(
        itemCount: players.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final Player player = players[index];
          return ListTile(
            title: Text(player.name),
            trailing: Text(player.rating.toString()),
          );
        },
      ),
    );
  }
}

class _AddPlayerDialog extends StatefulWidget {
  const _AddPlayerDialog();

  @override
  State<_AddPlayerDialog> createState() => _AddPlayerDialogState();
}

class _AddPlayerDialogState extends State<_AddPlayerDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ratingController =
      TextEditingController(text: '1000');

  @override
  void dispose() {
    _nameController.dispose();
    _ratingController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    final rating = int.tryParse(_ratingController.text);

    if (name.isEmpty || rating == null) return;

    Navigator.of(context).pop(
      Player(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        rating: rating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый игрок'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          TextField(
            controller: _ratingController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Рейтинг'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}