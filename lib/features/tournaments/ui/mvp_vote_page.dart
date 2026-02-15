import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TournamentMvpVotePage extends StatefulWidget {
  const TournamentMvpVotePage({super.key, required this.hallId});

  final String hallId;

  @override
  State<TournamentMvpVotePage> createState() => _TournamentMvpVotePageState();
}

class _TournamentMvpVotePageState extends State<TournamentMvpVotePage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  bool _submitting = false;
  bool _schemaMissing = false;
  bool _canOpenVotingWindow = false;
  String? _error;

  String? _tournamentId;
  DateTime? _tournamentDate;
  DateTime? _votingEndsAtUtc;
  bool _votesFinalized = false;
  String? _winnerPlayerId;
  String? _myLinkedPlayerId;
  String? _myLinkedPlayerName;

  String? _myVoteCandidateId;
  final List<_Participant> _participants = <_Participant>[];
  final Map<String, int> _votesByCandidateId = <String, int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _schemaMissing = false;
    });

    try {
      await _loadVotingPermissions();
      await _tryFinalizeDueVotes();
      final tournament = await _loadLatestCompletedTournament();
      if (tournament == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _tournamentId = null;
          _myLinkedPlayerId = null;
          _myLinkedPlayerName = null;
          _participants.clear();
          _votesByCandidateId.clear();
          _myVoteCandidateId = null;
        });
        return;
      }

      _tournamentId = tournament['id'].toString();
      _tournamentDate = _parseDateTimeOrNull(tournament['date'])?.toLocal();
      _votingEndsAtUtc = _parseDateTimeOrNull(tournament['mvp_voting_ends_at']);
      _votesFinalized = (tournament['mvp_votes_finalized'] as bool?) ?? false;
      _winnerPlayerId = tournament['mvp_winner_player_id']?.toString();

      await _loadParticipants(_tournamentId!);
      await _loadProfileLink();
      await _loadVotes(_tournamentId!);
    } catch (e) {
      final missingSchema = _isMissingVotingSchemaError(e);
      if (!mounted) return;
      setState(() {
        _schemaMissing = missingSchema;
        _error = missingSchema
            ? 'MVP-голосование пока не настроено в БД. Примени SQL-скрипт из проекта.'
            : 'Не удалось загрузить MVP-голосование: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _tryFinalizeDueVotes() async {
    try {
      await supabase.rpc(
        'finalize_due_mvp_votes',
        params: {'p_hall_id': widget.hallId},
      );
    } catch (e) {
      if (!_isMissingVotingSchemaError(e)) {
        debugPrint('⚠️ finalize_due_mvp_votes failed: $e');
      }
    }
  }

  Future<void> _loadVotingPermissions() async {
    final profileId = supabase.auth.currentUser?.id;
    if (profileId == null) {
      _canOpenVotingWindow = false;
      return;
    }

    try {
      final row = await supabase
          .from('hall_members')
          .select('role, status')
          .eq('hall_id', widget.hallId)
          .eq('profile_id', profileId)
          .maybeSingle();

      final role = (row?['role'] ?? '').toString().toLowerCase();
      final status = (row?['status'] ?? '').toString().toLowerCase();
      _canOpenVotingWindow =
          status == 'approved' && (role == 'owner' || role == 'admin');
    } catch (_) {
      _canOpenVotingWindow = false;
    }
  }

  Future<Map<String, dynamic>?> _loadLatestCompletedTournament() async {
    final rows = await supabase
        .from('tournaments')
        .select(
          'id, date, mvp_voting_ends_at, mvp_votes_finalized, mvp_winner_player_id',
        )
        .eq('hall_id', widget.hallId)
        .eq('completed', true)
        .order('date', ascending: false)
        .limit(1);

    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    return list.first;
  }

  Future<void> _loadParticipants(String tournamentId) async {
    final tpRows = await supabase
        .from('team_players')
        .select('player_id')
        .eq('tournament_id', tournamentId);

    final playerIds = <String>{};
    for (final row in (tpRows as List).cast<Map<String, dynamic>>()) {
      final playerId = row['player_id']?.toString();
      if (playerId != null && playerId.isNotEmpty) {
        playerIds.add(playerId);
      }
    }

    _participants.clear();
    if (playerIds.isEmpty) return;

    final playerRows = await supabase
        .from('players')
        .select('id, name')
        .inFilter('id', playerIds.toList());

    for (final row in (playerRows as List).cast<Map<String, dynamic>>()) {
      final id = row['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final name = (row['name'] ?? 'Игрок').toString();
      _participants.add(_Participant(id: id, name: name));
    }

    _participants.sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _loadProfileLink() async {
    final profileId = supabase.auth.currentUser?.id;
    if (profileId == null) {
      _myLinkedPlayerId = null;
      _myLinkedPlayerName = null;
      return;
    }

    final row = await supabase
        .from('player_profile_links')
        .select('player_id')
        .eq('hall_id', widget.hallId)
        .eq('profile_id', profileId)
        .maybeSingle();

    final linkedPlayerId = row?['player_id']?.toString();
    _myLinkedPlayerId = linkedPlayerId;
    if (linkedPlayerId == null || linkedPlayerId.isEmpty) {
      _myLinkedPlayerName = null;
      return;
    }

    for (final participant in _participants) {
      if (participant.id == linkedPlayerId) {
        _myLinkedPlayerName = participant.name;
        return;
      }
    }

    try {
      final player = await supabase
          .from('players')
          .select('name')
          .eq('id', linkedPlayerId)
          .maybeSingle();
      _myLinkedPlayerName = (player?['name'] ?? 'Игрок').toString();
    } catch (_) {
      _myLinkedPlayerName = null;
    }
  }

  Future<void> _loadVotes(String tournamentId) async {
    final currentUserId = supabase.auth.currentUser?.id;

    final rows = await supabase
        .from('tournament_mvp_votes')
        .select('candidate_player_id, voter_profile_id')
        .eq('tournament_id', tournamentId);

    _votesByCandidateId.clear();
    _myVoteCandidateId = null;

    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final candidateId = row['candidate_player_id']?.toString();
      if (candidateId == null || candidateId.isEmpty) continue;

      _votesByCandidateId[candidateId] =
          (_votesByCandidateId[candidateId] ?? 0) + 1;

      final voterProfileId = row['voter_profile_id']?.toString();
      if (currentUserId != null && voterProfileId == currentUserId) {
        _myVoteCandidateId = candidateId;
      }
    }
  }

  Future<void> _submitVote(String candidatePlayerId) async {
    final tournamentId = _tournamentId;
    if (tournamentId == null) return;

    setState(() => _submitting = true);
    try {
      await supabase.rpc(
        'cast_tournament_mvp_vote',
        params: {
          'p_tournament_id': tournamentId,
          'p_candidate_player_id': candidatePlayerId,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Голос принят ✅')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyVoteError(e))));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _bindProfileToParticipant(String playerId) async {
    final tournamentId = _tournamentId;
    if (tournamentId == null) return;

    setState(() => _submitting = true);
    try {
      await supabase.rpc(
        'link_my_profile_to_tournament_player',
        params: {'p_tournament_id': tournamentId, 'p_player_id': playerId},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аккаунт привязан к игроку турнира ✅')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyBindError(e))));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickAndBindProfile() async {
    if (_participants.isEmpty || _submitting) return;

    final selectedPlayerId = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Выбери себя в списке'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _participants.length,
            itemBuilder: (context, index) {
              final player = _participants[index];
              return ListTile(
                title: Text(player.name),
                onTap: () => Navigator.pop(context, player.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );

    if (selectedPlayerId == null) return;
    await _bindProfileToParticipant(selectedPlayerId);
  }

  Future<void> _openVotingWindowNow() async {
    final tournamentId = _tournamentId;
    if (tournamentId == null) return;

    setState(() => _submitting = true);
    try {
      final endsAtUtc = DateTime.now().toUtc().add(const Duration(hours: 12));

      await supabase
          .from('tournaments')
          .update({
            'mvp_voting_ends_at': endsAtUtc.toIso8601String(),
            'mvp_votes_finalized': false,
            'mvp_finalized_at': null,
            'mvp_winner_player_id': null,
          })
          .eq('id', tournamentId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Окно голосования открыто до ${_formatDateTime(endsAtUtc)}',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось открыть окно: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _friendlyVoteError(Object error) {
    final text = error.toString().toLowerCase();
    if (_isMissingVotingSchemaError(error)) {
      return 'MVP-голосование пока не настроено в БД. Примени SQL-скрипт.';
    }
    if (text.contains('profile is not linked')) {
      return 'Сначала привяжи аккаунт к своему игроку в этом турнире.';
    }
    if (text.contains('participants')) {
      return 'Голосовать могут только участники этого турнира.';
    }
    if (text.contains('voting closed') ||
        text.contains('голосование закрыто')) {
      return 'Голосование уже закрыто.';
    }
    if (text.contains('not authenticated') || text.contains('401')) {
      return 'Нужно заново войти в аккаунт, чтобы голосовать.';
    }
    return 'Не удалось отправить голос: $error';
  }

  String _friendlyBindError(Object error) {
    final text = error.toString().toLowerCase();
    if (_isMissingVotingSchemaError(error)) {
      return 'Схема MVP-голосования не обновлена. Примени новый SQL-скрипт.';
    }
    if (text.contains('player is not a participant')) {
      return 'Можно привязать только игрока из списка участников этого турнира.';
    }
    if (text.contains('duplicate key') && text.contains('hall_id, player_id')) {
      return 'Этот игрок уже привязан к другому аккаунту.';
    }
    return 'Не удалось привязать аккаунт: $error';
  }

  bool _isMissingVotingSchemaError(Object error) {
    final text = error.toString().toLowerCase();
    final mentionsMvpSchema =
        text.contains('mvp_voting_ends_at') ||
        text.contains('mvp_votes_finalized') ||
        text.contains('mvp_finalized_at') ||
        text.contains('mvp_winner_player_id') ||
        text.contains('tournament_mvp_votes') ||
        text.contains('player_profile_links') ||
        text.contains('link_my_profile_to_tournament_player') ||
        text.contains('cast_tournament_mvp_vote') ||
        text.contains('finalize_due_mvp_votes') ||
        text.contains('finalize_tournament_mvp');
    return mentionsMvpSchema &&
        (text.contains('does not exist') ||
            text.contains('could not find') ||
            text.contains('function') ||
            text.contains('column') ||
            text.contains('relation'));
  }

  DateTime? _parseDateTimeOrNull(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.'
        '${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  bool get _votingOpen {
    if (_votesFinalized) return false;
    final endsAt = _votingEndsAtUtc;
    if (endsAt == null) return false;
    return DateTime.now().toUtc().isBefore(endsAt);
  }

  bool get _canOpenWindowNow {
    return !_votesFinalized &&
        _votingEndsAtUtc == null &&
        _canOpenVotingWindow &&
        _tournamentId != null;
  }

  bool get _canVoteNow {
    return _votingOpen && !_submitting && _myLinkedPlayerId != null;
  }

  String _statusText() {
    if (_votesFinalized) {
      return _winnerPlayerId == null || _winnerPlayerId!.isEmpty
          ? 'Голосование завершено. Победитель не выбран.'
          : 'Голосование завершено. MVP начислен в рейтинг.';
    }

    final endsAt = _votingEndsAtUtc;
    if (endsAt == null) {
      return 'Окно голосования не открыто.';
    }
    if (_votingOpen) {
      return 'Голосование открыто до ${_formatDateTime(endsAt)}';
    }
    return 'Окно голосования закрыто. Итоги будут применены автоматически.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MVP голосование'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_schemaMissing) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'MVP-голосование не настроено.\n\n'
          'Примените SQL-скрипт из проекта и обновите экран.',
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Повторить')),
          ],
        ),
      );
    }

    if (_tournamentId == null) {
      return const Center(child: Text('Пока нет завершённых турниров'));
    }

    _Participant? winner;
    for (final participant in _participants) {
      if (participant.id == _winnerPlayerId) {
        winner = participant;
        break;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tournamentDate == null
                      ? 'Последний завершённый турнир'
                      : 'Турнир: ${_formatDateTime(_tournamentDate!)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(_statusText()),
                if (_myLinkedPlayerId != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Твой игрок: ${_myLinkedPlayerName ?? _myLinkedPlayerId}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
                if (_votingOpen && _myLinkedPlayerId == null) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Чтобы проголосовать, сначала привяжи аккаунт к себе в составе турнира.',
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _pickAndBindProfile,
                    icon: const Icon(Icons.link),
                    label: const Text('Привязать себя к участнику'),
                  ),
                ],
                if (_canOpenWindowNow) ...[
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _submitting ? null : _openVotingWindowNow,
                    icon: const Icon(Icons.how_to_vote),
                    label: const Text('Открыть голосование на 12 часов'),
                  ),
                ],
                if (winner != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Победитель MVP: ${winner.name}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Кандидаты (участники турнира)',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_participants.isEmpty)
          const Text('Не найден список участников турнира')
        else
          ..._participants.map((player) {
            final votes = _votesByCandidateId[player.id] ?? 0;
            final selectedByMe = _myVoteCandidateId == player.id;
            final isWinner = _votesFinalized && _winnerPlayerId == player.id;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(player.name),
                subtitle: Text('Голосов: $votes'),
                leading: selectedByMe
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : const Icon(Icons.circle_outlined),
                trailing: isWinner
                    ? const Icon(Icons.emoji_events, color: Colors.amber)
                    : null,
                onTap: _canVoteNow ? () => _submitVote(player.id) : null,
              ),
            );
          }),
        if (_myVoteCandidateId != null) ...[
          const SizedBox(height: 8),
          const Text(
            'Твой голос сохранён. До закрытия окна его можно поменять.',
          ),
        ],
      ],
    );
  }
}

class _Participant {
  const _Participant({required this.id, required this.name});

  final String id;
  final String name;
}
