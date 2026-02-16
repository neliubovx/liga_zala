import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:liga_zala/features/home/pages/matches_page.dart';
import 'package:liga_zala/hall/hall_admin_page.dart';
import 'package:liga_zala/hall/hall_me_tab.dart';
import 'package:liga_zala/hall/hall_players_tab.dart';
import 'package:liga_zala/hall/hall_rating_tab.dart';

class HallHomePage extends StatefulWidget {
  final String hallId;
  final String hallName;

  const HallHomePage({super.key, required this.hallId, required this.hallName});

  @override
  State<HallHomePage> createState() => _HallHomePageState();
}

class _HallHomePageState extends State<HallHomePage> {
  final supabase = Supabase.instance.client;

  int _currentIndex = 0;
  bool _loadingAccess = true;
  bool _canManageHall = false;

  @override
  void initState() {
    super.initState();
    _loadHallAccess();
  }

  List<Widget> get _pages => [
    const _HomeTab(),
    HallPlayersTab(hallId: widget.hallId, canManageHall: _canManageHall),
    MatchesPage(hallId: widget.hallId),
    HallRatingTab(hallId: widget.hallId),
    HallMeTab(hallId: widget.hallId),
  ];

  Future<void> _loadHallAccess() async {
    bool canManage = false;

    try {
      final data = await supabase
          .rpc('get_my_hall_membership', params: {'p_hall_id': widget.hallId})
          .timeout(const Duration(seconds: 12));
      final row = _firstRow(data);
      if (row != null) {
        canManage = _isAdminMembership(row);
      }
    } catch (e) {
      if (!_isMissingMembershipRpc(e)) {
        debugPrint('⚠️ get_my_hall_membership failed: $e');
      }

      // Fallback for old DB schema before RPC migration is applied.
      try {
        final row = await supabase
            .from('hall_members')
            .select('role, status')
            .eq('hall_id', widget.hallId)
            .eq('profile_id', supabase.auth.currentUser?.id ?? '')
            .maybeSingle()
            .timeout(const Duration(seconds: 12));
        if (row != null) {
          canManage = _isAdminMembership(row);
        }
      } catch (_) {
        canManage = false;
      }
    }

    if (!mounted) return;
    setState(() {
      _canManageHall = canManage;
      _loadingAccess = false;
    });
  }

  Map<String, dynamic>? _firstRow(dynamic value) {
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  bool _isAdminMembership(Map<String, dynamic> row) {
    final isAdmin = row['is_admin'] == true;
    if (isAdmin) return true;

    final status = (row['status'] ?? '').toString().toLowerCase();
    final role = (row['role'] ?? '').toString().toLowerCase();
    return status == 'approved' && (role == 'owner' || role == 'admin');
  }

  bool _isMissingMembershipRpc(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('get_my_hall_membership') &&
        (text.contains('function') ||
            text.contains('does not exist') ||
            text.contains('could not find'));
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.hallName),
        actions: [
          if (_canManageHall)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HallAdminPage(
                      hallId: widget.hallId,
                      hallName: widget.hallName,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_loadingAccess) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: pages[_currentIndex]),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Главная'),
          BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Игроки'),
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_soccer),
            label: 'Турниры',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard),
            label: 'Рейтинг',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'Вы',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Главная зала\n\n'
        'Здесь будет:\n'
        '• Чат\n'
        '• Голосования\n'
        '• Следующий турнир\n'
        '• Объявления',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16),
      ),
    );
  }
}
