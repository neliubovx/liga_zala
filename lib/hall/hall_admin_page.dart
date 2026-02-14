import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HallAdminPage extends StatefulWidget {
  final String hallId;
  final String hallName;

  const HallAdminPage({
    super.key,
    required this.hallId,
    required this.hallName,
  });

  @override
  State<HallAdminPage> createState() => _HallAdminPageState();
}

class _HallAdminPageState extends State<HallAdminPage> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    try {
      final pendingMembers = await supabase
          .from('hall_members')
          .select()
          .eq('hall_id', widget.hallId)
          .eq('status', 'pending');

      List<Map<String, dynamic>> result = [];

      for (var member in pendingMembers) {
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
        });
      }

      setState(() {
        _requests = result;
        _loading = false;
      });
    } catch (e) {
      print("Ошибка загрузки заявок: $e");
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _approve(String profileId) async {
    await supabase
        .from('hall_members')
        .update({'status': 'approved'})
        .eq('hall_id', widget.hallId)
        .eq('profile_id', profileId);

    _loadRequests();
  }

  Future<void> _reject(String profileId) async {
    await supabase
        .from('hall_members')
        .delete()
        .eq('hall_id', widget.hallId)
        .eq('profile_id', profileId);

    _loadRequests();
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFEDE7F6),
          child: Text(
            request['name']
                .toString()
                .substring(0, 1)
                .toUpperCase(),
            style: const TextStyle(
              color: Colors.deepPurple,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          request['name'],
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (request['email'] != null)
              Text(
                request['email'],
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            const SizedBox(height: 4),
            const Text(
              'Запрос на вступление',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              onPressed: () => _approve(request['profile_id']),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: () => _reject(request['profile_id']),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Заявки: ${widget.hallName}'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(
                  child: Text(
                    'Нет заявок',
                    style: TextStyle(fontSize: 16),
                  ),
                )
              : ListView.builder(
                  itemCount: _requests.length,
                  itemBuilder: (_, index) =>
                      _buildRequestCard(_requests[index]),
                ),
    );
  }
}
