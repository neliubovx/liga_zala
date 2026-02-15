import 'package:flutter/material.dart';

import '../../players/data/players_repository.dart';
import '../../players/model/player.dart';
import '../logic/team_builder.dart';
import 'teams_result_page.dart';

enum TeamSplitMethod { rating, baskets, random }

class SelectPlayersPage extends StatefulWidget {
  final String hallId;

  const SelectPlayersPage({
    super.key,
    required this.hallId,
    required this.teamsCount,
    required this.playersPerTeam,
    required this.rounds,
    required this.tournamentDate,
  });

  final int teamsCount;
  final int playersPerTeam;
  final int rounds;
  final DateTime tournamentDate;

  @override
  State<SelectPlayersPage> createState() => _SelectPlayersPageState();
}

class _SelectPlayersPageState extends State<SelectPlayersPage> {
  final _repo = PlayersRepository.instance;
  final Set<String> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
  final Map<String, int> _basketByPlayerId = {};

  TeamSplitMethod _method = TeamSplitMethod.rating;
  String _searchQuery = '';
  int _basketsCount = 3;

  int get _requiredPlayers => widget.teamsCount * widget.playersPerTeam;

  List<Player> get _players {
    final all = _repo.getAll();

    if (_searchQuery.isEmpty) return all;

    return all
        .where((p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        _basketByPlayerId.remove(id);
      } else {
        _selectedIds.add(id);
        if (_method == TeamSplitMethod.baskets) {
          _ensureBasketAssignments();
        }
      }
    });
  }

  void _addPlayerDialog() {
    final nameController = TextEditingController();
    final surnameController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Добавить игрока'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Имя *'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: surnameController,
              decoration: const InputDecoration(
                labelText: 'Фамилия',
                hintText: 'Необязательно',
                // важно: чтобы hint реально был ВНУТРИ поля
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              final surname = surnameController.text.trim();
              final fullName = surname.isEmpty ? name : '$name $surname';

              final player = Player(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: fullName,
                rating: 0,
              );

              _repo.add(player);

              setState(() {
                _selectedIds.add(player.id);
                if (_method == TeamSplitMethod.baskets) {
                  _ensureBasketAssignments();
                }
              });

              Navigator.pop(context);
            },
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
  }

  void _onBuildTeamsPressed() {
    final selectedPlayers = _repo
        .getAll()
        .where((p) => _selectedIds.contains(p.id))
        .toList();

    _repo.clearTeams();

    final teams = TeamBuilder.buildTeams(
      players: selectedPlayers,
      teamsCount: widget.teamsCount,
      method: _method,
      basketByPlayerId: _method == TeamSplitMethod.baskets
          ? _basketByPlayerId
          : null,
    );

    for (int i = 0; i < teams.length; i++) {
      for (final player in teams[i]) {
        _repo.assignTeam(player.id, i);
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeamsResultPage(
          hallId: widget.hallId,
          teams: teams,
          rounds: widget.rounds,
          tournamentDate: widget.tournamentDate,
          splitMethod: _method,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enough = _selectedIds.length == _requiredPlayers;

    return Scaffold(
      appBar: AppBar(title: const Text('Выбор игроков')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addPlayerDialog,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // ФОРМАТ ТУРНИРА
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Формат турнира',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                RadioListTile<TeamSplitMethod>(
                  title: const Text('По рейтингу'),
                  value: TeamSplitMethod.rating,
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                ),
                RadioListTile<TeamSplitMethod>(
                  title: const Text('По корзинам'),
                  value: TeamSplitMethod.baskets,
                  groupValue: _method,
                  onChanged: (v) {
                    setState(() {
                      _method = v!;
                      _ensureBasketAssignments();
                    });
                  },
                ),
                RadioListTile<TeamSplitMethod>(
                  title: const Text('Случайно'),
                  value: TeamSplitMethod.random,
                  groupValue: _method,
                  onChanged: (v) => setState(() => _method = v!),
                ),
                if (_method == TeamSplitMethod.baskets) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Корзин:'),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('2'),
                        selected: _basketsCount == 2,
                        onSelected: (_) {
                          setState(() {
                            _basketsCount = 2;
                            _ensureBasketAssignments(forceRebuild: true);
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('3'),
                        selected: _basketsCount == 3,
                        onSelected: (_) {
                          setState(() {
                            _basketsCount = 3;
                            _ensureBasketAssignments(forceRebuild: true);
                          });
                        },
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(
                            () => _ensureBasketAssignments(forceRebuild: true),
                          );
                        },
                        child: const Text('Автораскидка'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _basketPreview(),
                ],
              ],
            ),
          ),

          const Divider(),

          // ПОИСК
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: const InputDecoration(
                hintText: 'Поиск игрока...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // СПИСОК ИГРОКОВ
          Expanded(
            child: ListView.builder(
              itemCount: _players.length,
              itemBuilder: (_, i) {
                final p = _players[i];
                final selected = _selectedIds.contains(p.id);

                return ListTile(
                  title: Text(p.name),
                  subtitle: Text('Рейтинг: ${p.rating}'),
                  leading:
                      _method == TeamSplitMethod.baskets &&
                          _selectedIds.contains(p.id)
                      ? _basketChip(p.id)
                      : null,
                  trailing: Checkbox(
                    value: selected,
                    onChanged: (_) => _toggle(p.id),
                  ),
                  onTap: () => _toggle(p.id),
                );
              },
            ),
          ),

          // КНОПКА
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Выбрано ${_selectedIds.length} / $_requiredPlayers',
                  style: TextStyle(
                    color: enough ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: enough ? _onBuildTeamsPressed : null,
                    child: const Text('Сформировать команды'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _basketChip(String playerId) {
    final basket = _basketByPlayerId[playerId] ?? 1;
    return PopupMenuButton<int>(
      tooltip: 'Корзина',
      initialValue: basket,
      onSelected: (value) {
        setState(() {
          _basketByPlayerId[playerId] = value;
        });
      },
      itemBuilder: (context) => List.generate(
        _basketsCount,
        (index) => PopupMenuItem<int>(
          value: index + 1,
          child: Text('Корзина ${index + 1}'),
        ),
      ),
      child: Chip(
        label: Text('К$basket'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _basketPreview() {
    final selectedPlayers =
        _repo.getAll().where((p) => _selectedIds.contains(p.id)).toList()
          ..sort((a, b) => b.rating.compareTo(a.rating));

    if (selectedPlayers.isEmpty) {
      return const Text(
        'Выбери игроков, чтобы распределить по корзинам.',
        style: TextStyle(color: Colors.grey),
      );
    }

    final counts = List<int>.filled(_basketsCount, 0);
    for (final p in selectedPlayers) {
      final basket = (_basketByPlayerId[p.id] ?? 1).clamp(1, _basketsCount);
      counts[basket - 1]++;
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(_basketsCount, (i) {
        return Chip(label: Text('Корзина ${i + 1}: ${counts[i]}'));
      }),
    );
  }

  void _ensureBasketAssignments({bool forceRebuild = false}) {
    final selectedPlayers =
        _repo.getAll().where((p) => _selectedIds.contains(p.id)).toList()
          ..sort((a, b) => b.rating.compareTo(a.rating));

    if (selectedPlayers.isEmpty) {
      _basketByPlayerId.clear();
      return;
    }

    for (int i = 0; i < selectedPlayers.length; i++) {
      final player = selectedPlayers[i];
      if (!forceRebuild && _basketByPlayerId.containsKey(player.id)) {
        continue;
      }
      _basketByPlayerId[player.id] = _autoBasketForIndex(
        i,
        selectedPlayers.length,
      );
    }

    final stale = _basketByPlayerId.keys
        .where((id) => !_selectedIds.contains(id))
        .toList();
    for (final id in stale) {
      _basketByPlayerId.remove(id);
    }
  }

  int _autoBasketForIndex(int index, int total) {
    final raw = ((index * _basketsCount) ~/ total) + 1;
    if (raw < 1) return 1;
    if (raw > _basketsCount) return _basketsCount;
    return raw;
  }
}
