import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HallAdminPage extends StatefulWidget {
  const HallAdminPage({
    super.key,
    required this.hallId,
    required this.hallName,
  });

  final String hallId;
  final String hallName;

  @override
  State<HallAdminPage> createState() => _HallAdminPageState();
}

class _HallAdminPageState extends State<HallAdminPage> {
  final supabase = Supabase.instance.client;
  static const Duration _requestTimeout = Duration(seconds: 12);

  List<Map<String, dynamic>> _requests = const [];
  bool _loading = true;
  String? _error;
  String? _actionProfileId;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<T> _withTimeout<T>(Future<T> future) {
    return future.timeout(_requestTimeout);
  }

  bool _isNetworkError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('timed out') ||
        text.contains('failed host lookup') ||
        text.contains('errno = 60') ||
        text.contains('connection closed') ||
        text.contains('network is unreachable');
  }

  bool _isMissingAdminRpcError(Object error) {
    final text = error.toString().toLowerCase();
    final mentionsRpc =
        text.contains('get_hall_pending_requests') ||
        text.contains('approve_hall_member_request') ||
        text.contains('reject_hall_member_request') ||
        text.contains('assert_hall_admin');
    final missingSignature =
        text.contains('function') ||
        text.contains('does not exist') ||
        text.contains('could not find');
    return mentionsRpc && missingSignature;
  }

  String _friendlyLoadError(Object error) {
    final text = error.toString().toLowerCase();

    if (_isNetworkError(error)) {
      return 'Не удалось загрузить заявки из-за сети. Проверь интернет/VPN и нажми "Повторить".';
    }
    if (_isMissingAdminRpcError(error)) {
      return 'Нужно применить SQL: docs/sql/2026-02-17-hall-roles-rls.sql';
    }
    if (text.contains('only hall admins')) {
      return 'Доступ к заявкам есть только у owner/admin этого зала.';
    }
    if (text.contains('permission denied') ||
        text.contains('row-level security')) {
      return 'Нет доступа к заявкам. Проверь роль owner/admin и RLS.';
    }

    return 'Не удалось загрузить заявки: $error';
  }

  String _friendlyActionError(Object error) {
    final text = error.toString().toLowerCase();
    if (_isNetworkError(error)) {
      return 'Сеть недоступна. Попробуй ещё раз.';
    }
    if (_isMissingAdminRpcError(error)) {
      return 'Нужно применить SQL: docs/sql/2026-02-17-hall-roles-rls.sql';
    }
    if (text.contains('only hall admins')) {
      return 'Доступно только owner/admin.';
    }
    if (text.contains('request not found')) {
      return 'Заявка уже обработана.';
    }
    if (text.contains('permission denied') ||
        text.contains('row-level security')) {
      return 'Нет прав на это действие.';
    }
    return 'Не удалось обработать заявку: $error';
  }

  List<Map<String, dynamic>> _asRows(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _loadRequestsViaRpc() async {
    final raw = await _withTimeout(
      supabase.rpc(
        'get_hall_pending_requests',
        params: {'p_hall_id': widget.hallId},
      ),
    );
    final rows = _asRows(raw);
    return rows
        .map(
          (row) => <String, dynamic>{
            'profile_id': (row['profile_id'] ?? '').toString(),
            'name': (row['display_name'] ?? 'Пользователь').toString(),
            'email': row['email']?.toString(),
          },
        )
        .where((row) => (row['profile_id'] as String).isNotEmpty)
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _loadRequestsLegacy() async {
    final pendingRows = await _withTimeout(
      supabase
          .from('hall_members')
          .select('profile_id')
          .eq('hall_id', widget.hallId)
          .eq('status', 'pending'),
    );

    final pending = _asRows(pendingRows);
    if (pending.isEmpty) return const [];

    final profileIds = pending
        .map((row) => row['profile_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    if (profileIds.isEmpty) return const [];

    final profileRows = await _withTimeout(
      supabase
          .from('profiles')
          .select('id, display_name, email')
          .inFilter('id', profileIds),
    );

    final byProfileId = <String, Map<String, dynamic>>{};
    for (final row in _asRows(profileRows)) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      byProfileId[id] = row;
    }

    final result = <Map<String, dynamic>>[];
    for (final row in pending) {
      final profileId = row['profile_id']?.toString() ?? '';
      if (profileId.isEmpty) continue;
      final profile = byProfileId[profileId];
      final displayName = (profile?['display_name'] ?? '').toString().trim();
      final email = (profile?['email'] ?? '').toString().trim();

      result.add({
        'profile_id': profileId,
        'name': displayName.isNotEmpty
            ? displayName
            : (email.isNotEmpty ? email : 'Пользователь'),
        'email': email.isEmpty ? null : email,
      });
    }

    result.sort((a, b) {
      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });

    return result;
  }

  Future<void> _loadRequests() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      var requests = await _loadRequestsViaRpc();
      if (!mounted) return;
      setState(() {
        _requests = requests;
        _loading = false;
      });
    } catch (e) {
      if (_isMissingAdminRpcError(e)) {
        try {
          final requests = await _loadRequestsLegacy();
          if (!mounted) return;
          setState(() {
            _requests = requests;
            _loading = false;
          });
          return;
        } catch (_) {
          // fallthrough to error message below
        }
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyLoadError(e);
      });
    }
  }

  Future<void> _approve(String profileId) async {
    if (_actionProfileId != null) return;

    setState(() => _actionProfileId = profileId);
    try {
      await _withTimeout(
        supabase.rpc(
          'approve_hall_member_request',
          params: {'p_hall_id': widget.hallId, 'p_profile_id': profileId},
        ),
      );
      await _loadRequests();
    } catch (e) {
      if (_isMissingAdminRpcError(e)) {
        try {
          await _withTimeout(
            supabase
                .from('hall_members')
                .update({'status': 'approved'})
                .eq('hall_id', widget.hallId)
                .eq('profile_id', profileId),
          );
          await _loadRequests();
          return;
        } catch (_) {
          // show RPC-driven error below
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyActionError(e))));
    } finally {
      if (mounted) setState(() => _actionProfileId = null);
    }
  }

  Future<void> _reject(String profileId) async {
    if (_actionProfileId != null) return;

    setState(() => _actionProfileId = profileId);
    try {
      await _withTimeout(
        supabase.rpc(
          'reject_hall_member_request',
          params: {'p_hall_id': widget.hallId, 'p_profile_id': profileId},
        ),
      );
      await _loadRequests();
    } catch (e) {
      if (_isMissingAdminRpcError(e)) {
        try {
          await _withTimeout(
            supabase
                .from('hall_members')
                .delete()
                .eq('hall_id', widget.hallId)
                .eq('profile_id', profileId),
          );
          await _loadRequests();
          return;
        } catch (_) {
          // show RPC-driven error below
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyActionError(e))));
    } finally {
      if (mounted) setState(() => _actionProfileId = null);
    }
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final profileId = (request['profile_id'] ?? '').toString();
    final name = (request['name'] ?? 'Пользователь').toString();
    final email = request['email']?.toString();
    final isBusy = _actionProfileId == profileId;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFEDE7F6),
          child: Text(
            name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: Colors.deepPurple,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (email != null && email.isNotEmpty)
              Text(
                email,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            const SizedBox(height: 4),
            const Text('Запрос на вступление', style: TextStyle(fontSize: 13)),
          ],
        ),
        trailing: isBusy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    tooltip: 'Одобрить',
                    onPressed: () => _approve(profileId),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    tooltip: 'Отклонить',
                    onPressed: () => _reject(profileId),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadRequests,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    if (_requests.isEmpty) {
      return const Center(child: Text('Нет заявок'));
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _requests.length,
        itemBuilder: (_, index) => _buildRequestCard(_requests[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Заявки: ${widget.hallName}')),
      body: _buildBody(),
    );
  }
}
