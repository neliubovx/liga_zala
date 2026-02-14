import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HallPlayersTab extends StatefulWidget {
  final String hallId;
  final bool isOwner;

  const HallPlayersTab({
    super.key,
    required this.hallId,
    required this.isOwner,
  });

  @override
  State<HallPlayersTab> createState() => _HallPlayersTabState();
}

class _HallPlayersTabState extends State<HallPlayersTab> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _players = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlayers();
  }

  Future<void> _loadPlayers() async {
    try {
      final members = await supabase
          .from('hall_members')
          .select()
          .eq('hall_id', widget.hallId)
          .eq('status', 'approved');

      List<Map<String, dynamic>> result = [];

      for (var member in members) {
        final profile = await supabase
            .from('profiles')
            .select()
            .eq('id', member['profile_id'])
            .maybeSingle();

        result.add({
          'profile_id': member['profile_id'],
          'name': profile?['display_name'] ??
              profile?['email'] ??
              'Пользователь',
          'email': profile?['email'],
          'role': member['role'],
        });
      }

      setState(() {
        _players = result;
        _loading = false;
      });
    } catch (e) {
      print("Ошибка загрузки игроков: $e");
      setState(() => _loading = false);
    }
  }

  Future<void> _removePlayer(String profileId) async {
    await supabase
        .from('hall_members')
        .delete()
        .eq('hall_id', widget.hallId)
        .eq('profile_id', profileId);

    _loadPlayers();
  }

  Widget _buildPlayerCard(Map<String, dynamic> player) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE3F2FD),
          child: Text(
            player['name']
                .toString()
                .substring(0, 1)
                .toUpperCase(),
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          player['name'],
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: player['email'] != null
            ? Text(
                player['email'],
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              )
            : null,
        trailing: widget.isOwner && player['role'] != 'owner'
            ? IconButton(
                icon: const Icon(Icons.remove_circle, color: Colors.red),
                onPressed: () =>
                    _removePlayer(player['profile_id']),
              )
            : player['role'] == 'owner'
                ? const Text(
                    'Owner',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  )
                : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_players.isEmpty) {
      return const Center(
        child: Text('Нет игроков'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPlayers,
      child: ListView.builder(
        itemCount: _players.length,
        itemBuilder: (_, index) =>
            _buildPlayerCard(_players[index]),
      ),
    );
  }
}
