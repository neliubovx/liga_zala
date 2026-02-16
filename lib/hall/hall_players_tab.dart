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
  static const Duration _requestTimeout = Duration(seconds: 12);

  List<Map<String, dynamic>> _players = [];
  final Map<String, String?> _linkedProfileIdByPlayerId = {};
  final Map<String, String> _profileLabelById = {};

  bool _loading = true;
  String? _error;
  String? _linkingPlayerId;

  String? _myProfileId;
  String? _myLinkedPlayerId;
  bool _isApprovedMember = false;

  @override
  void initState() {
    super.initState();
    _loadPlayers();
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

  String _friendlyLoadError(Object error) {
    if (_isNetworkError(error)) {
      return 'Не удалось загрузить игроков из-за сети. '
          'Проверь интернет/VPN и нажми "Повторить".';
    }
    return 'Не удалось загрузить игроков: $error';
  }

  Future<Set<String>> _fetchLegacyPlayerIdsFromTournamentRows() async {
    final ids = <String>{};

    try {
      final joinedRows = await _withTimeout(
        supabase
            .from('team_players')
            .select('player_id, tournaments!inner(hall_id)')
            .eq('tournaments.hall_id', widget.hallId),
      );

      for (final row in (joinedRows as List).cast<Map<String, dynamic>>()) {
        final playerId = row['player_id']?.toString();
        if (playerId != null && playerId.isNotEmpty) {
          ids.add(playerId);
        }
      }
      return ids;
    } catch (_) {
      // Fallback ниже, если join-filter недоступен.
    }

    final tRows = await _withTimeout(
      supabase.from('tournaments').select('id').eq('hall_id', widget.hallId),
    );
    final tournamentIds = <String>[];
    for (final row in (tRows as List).cast<Map<String, dynamic>>()) {
      final id = row['id']?.toString();
      if (id != null && id.isNotEmpty) {
        tournamentIds.add(id);
      }
    }

    if (tournamentIds.isEmpty) return ids;

    final tpRows = await _withTimeout(
      supabase
          .from('team_players')
          .select('player_id')
          .inFilter('tournament_id', tournamentIds),
    );
    for (final row in (tpRows as List).cast<Map<String, dynamic>>()) {
      final playerId = row['player_id']?.toString();
      if (playerId != null && playerId.isNotEmpty) {
        ids.add(playerId);
      }
    }

    return ids;
  }

  Future<void> _loadMembership() async {
    _myProfileId = supabase.auth.currentUser?.id;
    _isApprovedMember = false;

    if (_myProfileId == null) return;

    try {
      final row = await _withTimeout(
        supabase
            .from('hall_members')
            .select('status')
            .eq('hall_id', widget.hallId)
            .eq('profile_id', _myProfileId!)
            .maybeSingle(),
      );

      _isApprovedMember =
          (row?['status'] ?? '').toString().toLowerCase() == 'approved';
    } catch (_) {
      // Membership only controls link button state; it must not block players list.
      _isApprovedMember = false;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchHallPlayers() async {
    final mergedById = <String, Map<String, dynamic>>{};

    final directRows = await _withTimeout(
      supabase
          .from('players')
          .select('id, name, hall_id')
          .eq('hall_id', widget.hallId),
    );

    for (final row in (directRows as List).cast<Map<String, dynamic>>()) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      mergedById[id] = row;
    }

    final legacyPlayerIds = await _fetchLegacyPlayerIdsFromTournamentRows();
    final missingIds = legacyPlayerIds
        .where((id) => !mergedById.containsKey(id))
        .toList();

    if (missingIds.isNotEmpty) {
      final legacyRows = await _withTimeout(
        supabase
            .from('players')
            .select('id, name, hall_id')
            .inFilter('id', missingIds),
      );

      for (final row in (legacyRows as List).cast<Map<String, dynamic>>()) {
        final id = row['id']?.toString();
        if (id == null || id.isEmpty) continue;
        mergedById[id] = row;
      }
    }

    final items = mergedById.values.toList();
    items.sort((a, b) {
      final aName = (a['name'] ?? '').toString().toLowerCase();
      final bName = (b['name'] ?? '').toString().toLowerCase();
      return aName.compareTo(bName);
    });
    return items;
  }

  String _friendlyLinkError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('not authenticated') || text.contains('401')) {
      return 'Нужно войти в аккаунт заново.';
    }
    if (text.contains('not an approved hall member')) {
      return 'Голосовать и привязываться могут только одобренные участники зала.';
    }
    if (text.contains('player does not belong to hall')) {
      return 'Этого игрока нельзя привязать к текущему залу.';
    }
    if (text.contains('duplicate key') && text.contains('hall_id, player_id')) {
      return 'Этот игрок уже привязан к другому аккаунту.';
    }
    if (text.contains('link_my_profile_to_hall_player') &&
        (text.contains('does not exist') || text.contains('function'))) {
      return 'Нужно применить новый SQL-скрипт из проекта для привязки.';
    }
    return 'Не удалось привязать аккаунт: $error';
  }

  Future<void> _linkMeToPlayer({
    required String playerId,
    required String playerName,
  }) async {
    if (_linkingPlayerId != null) return;

    final profileId = _myProfileId;
    if (profileId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Нужно войти в аккаунт.')));
      return;
    }
    if (!_isApprovedMember) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала нужно быть одобренным участником этого зала.'),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Привязать аккаунт?'),
        content: Text('Привязать твой аккаунт к игроку "$playerName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Привязать'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _linkingPlayerId = playerId);
    try {
      await _withTimeout(
        supabase.rpc(
          'link_my_profile_to_hall_player',
          params: {'p_hall_id': widget.hallId, 'p_player_id': playerId},
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Аккаунт привязан к "$playerName" ✅')),
      );
      await _loadPlayers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyLinkError(e))));
    } finally {
      if (mounted) {
        setState(() => _linkingPlayerId = null);
      }
    }
  }

  Future<void> _loadPlayers() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      await _loadMembership();
      final players = await _fetchHallPlayers();
      _linkedProfileIdByPlayerId.clear();
      _profileLabelById.clear();
      _myLinkedPlayerId = null;
      try {
        final linksRows = await _withTimeout(
          supabase
              .from('player_profile_links')
              .select('player_id, profile_id')
              .eq('hall_id', widget.hallId),
        );

        final profileIds = <String>{};
        for (final row in (linksRows as List).cast<Map<String, dynamic>>()) {
          final playerId = row['player_id']?.toString();
          final profileId = row['profile_id']?.toString();
          if (playerId == null || playerId.isEmpty) continue;
          _linkedProfileIdByPlayerId[playerId] = profileId;
          if (profileId != null && profileId.isNotEmpty) {
            profileIds.add(profileId);
          }
          if (profileId != null &&
              profileId == _myProfileId &&
              _myLinkedPlayerId == null) {
            _myLinkedPlayerId = playerId;
          }
        }

        if (profileIds.isNotEmpty) {
          final profileRows = await _withTimeout(
            supabase
                .from('profiles')
                .select('id, display_name, email')
                .inFilter('id', profileIds.toList()),
          );
          for (final row
              in (profileRows as List).cast<Map<String, dynamic>>()) {
            final profileId = row['id']?.toString();
            if (profileId == null || profileId.isEmpty) continue;
            final displayName = (row['display_name'] ?? '').toString().trim();
            final email = (row['email'] ?? '').toString().trim();
            final label = displayName.isNotEmpty
                ? displayName
                : (email.isNotEmpty ? email : 'Аккаунт');
            _profileLabelById[profileId] = label;
          }
        }
      } catch (_) {
        // Links are optional for rendering the players list.
      }

      setState(() {
        _players = players;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = _friendlyLoadError(e);
      });
    }
  }

  Widget _buildPlayerCard(Map<String, dynamic> player) {
    final playerId = player['id']?.toString() ?? '';
    final name = (player['name'] ?? 'Игрок').toString().trim();
    final firstLetter = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();

    final linkedProfileId = _linkedProfileIdByPlayerId[playerId];
    final linkedProfileLabel = linkedProfileId == null
        ? null
        : _profileLabelById[linkedProfileId];
    final isMyPlayer = _myLinkedPlayerId == playerId;
    final canLinkThisPlayer =
        _isApprovedMember &&
        _myProfileId != null &&
        (linkedProfileId == null || linkedProfileId == _myProfileId) &&
        !isMyPlayer;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFE3F2FD),
          child: Text(
            firstLetter,
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          name.isEmpty ? 'Игрок' : name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text(
              linkedProfileId == null
                  ? 'Без привязанного аккаунта'
                  : 'Аккаунт: ${linkedProfileLabel ?? linkedProfileId}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        trailing: isMyPlayer
            ? const Text(
                'Это я',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              )
            : canLinkThisPlayer
            ? OutlinedButton(
                onPressed: _linkingPlayerId == playerId
                    ? null
                    : () => _linkMeToPlayer(
                        playerId: playerId,
                        playerName: name.isEmpty ? 'Игрок' : name,
                      ),
                child: Text(
                  _linkingPlayerId == playerId ? '...' : 'Это мой аккаунт',
                ),
              )
            : linkedProfileId != null && linkedProfileId != _myProfileId
            ? const Icon(Icons.lock_outline, color: Colors.grey)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _loadPlayers,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    if (_players.isEmpty) {
      return const Center(child: Text('Игроков пока нет'));
    }

    return RefreshIndicator(
      onRefresh: _loadPlayers,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _players.length,
        itemBuilder: (_, index) => _buildPlayerCard(_players[index]),
      ),
    );
  }
}
