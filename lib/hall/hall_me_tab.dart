import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:liga_zala/app/theme_controller.dart';
import 'package:liga_zala/auth/auth_page.dart';

class HallMeTab extends StatefulWidget {
  const HallMeTab({super.key, required this.hallId});

  final String hallId;

  @override
  State<HallMeTab> createState() => _HallMeTabState();
}

class _HallMeTabState extends State<HallMeTab> {
  final supabase = Supabase.instance.client;
  final _settingsService = _NotificationSettingsService();

  String _accountEmail = '';
  _NotificationSettings _settings = _NotificationSettings.defaults();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final user = supabase.auth.currentUser;
    final local = await _settingsService.readLocal();

    if (!mounted) return;
    setState(() {
      _accountEmail = (user?.email ?? '').trim();
      _settings = local;
      _loading = false;
    });

    final merged = await _settingsService.loadMerged();
    if (!mounted) return;
    setState(() {
      _settings = merged;
    });
  }

  Future<void> _openChangeEmailDialog() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final controller = TextEditingController(text: user.email ?? '');
    final email = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Изменить адрес эл. почты'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            hintText: 'you@example.com',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (!mounted || email == null || email.isEmpty) return;
    if (!email.contains('@')) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Введи корректный e-mail.')));
      return;
    }

    try {
      await supabase.auth.updateUser(UserAttributes(email: email));
      if (!mounted) return;
      setState(() => _accountEmail = email);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Запрос отправлен. Подтверди новый e-mail по письму.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось обновить e-mail: $e')));
    }
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text('Текущая сессия будет завершена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await supabase.auth.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthPage()),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не удалось выйти: $e')));
    }
  }

  String _modeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'По умолчанию';
      case ThemeMode.light:
        return 'Светлый';
      case ThemeMode.dark:
        return 'Тёмный';
    }
  }

  Future<void> _openPushSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PushSettingsPage(settingsService: _settingsService),
      ),
    );
    await _load();
  }

  Future<void> _openEmailSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EmailSettingsPage(settingsService: _settingsService),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            color: Colors.grey.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              _accountEmail.isEmpty
                  ? 'АККАУНТ'
                  : 'АККАУНТ: ${_accountEmail.toUpperCase()}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.fitness_center),
            title: const Text('Тренировки'),
            subtitle: const Text('Где и когда ты играл'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _MyTrainingsPage()),
              );
            },
          ),
          const SizedBox(height: 8),
          Container(
            color: Colors.grey.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: const Text(
              'НАСТРОЙКИ',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Вид'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: AppThemeController.instance.mode,
                  builder: (context, mode, child) => Text(
                    _modeLabel(mode),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _AppearancePage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Push-уведомления'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _settings.pushEnabled ? 'Вкл' : 'Выкл',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: _openPushSettings,
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email),
            title: const Text('Уведомления по эл. почте'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _settings.emailEnabled ? 'Вкл' : 'Выкл',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: _openEmailSettings,
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Изменить адрес эл. почты'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openChangeEmailDialog,
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Справка'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const _HelpPage()),
              );
            },
          ),
          const Divider(height: 20),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text(
              'Выйти из аккаунта',
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: _signOut,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _MyTrainingsPage extends StatefulWidget {
  const _MyTrainingsPage();

  @override
  State<_MyTrainingsPage> createState() => _MyTrainingsPageState();
}

class _MyTrainingsPageState extends State<_MyTrainingsPage> {
  final supabase = Supabase.instance.client;
  static const Duration _requestTimeout = Duration(seconds: 12);

  bool _loading = true;
  String? _error;
  List<_TrainingItem> _items = const <_TrainingItem>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<T> _withTimeout<T>(Future<T> future) {
    return future.timeout(_requestTimeout);
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Без даты';
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.'
        '${date.year} ${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  bool _isNetworkError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('timed out') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable');
  }

  String _friendlyError(Object error) {
    if (_isNetworkError(error)) {
      return 'Не удалось загрузить тренировки из-за сети. Проверь интернет/VPN и нажми "Повторить".';
    }
    return 'Не удалось загрузить тренировки: $error';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final profileId = supabase.auth.currentUser?.id;
      if (profileId == null) {
        if (!mounted) return;
        setState(() {
          _items = const <_TrainingItem>[];
          _loading = false;
        });
        return;
      }

      final linksRows = await _withTimeout(
        supabase
            .from('player_profile_links')
            .select('hall_id, player_id')
            .eq('profile_id', profileId),
      );

      final links = (linksRows as List).cast<Map<String, dynamic>>();
      if (links.isEmpty) {
        if (!mounted) return;
        setState(() {
          _items = const <_TrainingItem>[];
          _loading = false;
        });
        return;
      }

      final hallIdByPlayerId = <String, String>{};
      final hallIds = <String>{};
      final playerIds = <String>{};

      for (final row in links) {
        final hallId = row['hall_id']?.toString();
        final playerId = row['player_id']?.toString();
        if (hallId == null ||
            hallId.isEmpty ||
            playerId == null ||
            playerId.isEmpty) {
          continue;
        }
        hallIdByPlayerId[playerId] = hallId;
        hallIds.add(hallId);
        playerIds.add(playerId);
      }

      final hallNameById = <String, String>{};
      if (hallIds.isNotEmpty) {
        final hallRows = await _withTimeout(
          supabase
              .from('halls')
              .select('id, name')
              .inFilter('id', hallIds.toList()),
        );
        for (final row in (hallRows as List).cast<Map<String, dynamic>>()) {
          final id = row['id']?.toString();
          if (id == null || id.isEmpty) continue;
          hallNameById[id] = (row['name'] ?? 'Зал').toString();
        }
      }

      final tpRows = await _withTimeout(
        supabase
            .from('team_players')
            .select(
              'player_id, tournament_id, tournaments!inner(id, hall_id, date, completed)',
            )
            .inFilter('player_id', playerIds.toList()),
      );

      final items = <_TrainingItem>[];
      final seenTournamentIds = <String>{};
      for (final row in (tpRows as List).cast<Map<String, dynamic>>()) {
        final playerId = row['player_id']?.toString();
        if (playerId == null || playerId.isEmpty) continue;

        final t = row['tournaments'];
        if (t is! Map<String, dynamic>) continue;

        final tournamentId = t['id']?.toString();
        if (tournamentId == null || tournamentId.isEmpty) continue;
        if (seenTournamentIds.contains(tournamentId)) continue;

        final hallId = t['hall_id']?.toString() ?? '';
        final expectedHallId = hallIdByPlayerId[playerId];
        if (expectedHallId != null &&
            expectedHallId.isNotEmpty &&
            hallId != expectedHallId) {
          continue;
        }

        seenTournamentIds.add(tournamentId);
        items.add(
          _TrainingItem(
            tournamentId: tournamentId,
            hallName: hallNameById[hallId] ?? 'Зал',
            date: _parseDate(t['date']),
            completed: (t['completed'] as bool?) ?? false,
          ),
        );
      }

      items.sort((a, b) {
        final aDate = a.date ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.date ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Тренировки')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            )
          : _items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Тренировок пока нет.\n\n'
                  'Чтобы здесь появилась история, привяжи аккаунт к своему игроку и сыграй турнир.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (_, index) {
                final item = _items[index];
                return ListTile(
                  leading: Icon(
                    item.completed
                        ? Icons.check_circle_outline
                        : Icons.schedule,
                  ),
                  title: Text(item.hallName),
                  subtitle: Text(_formatDate(item.date)),
                );
              },
            ),
    );
  }
}

class _AppearancePage extends StatelessWidget {
  const _AppearancePage();

  String _label(AppThemePreference pref) {
    switch (pref) {
      case AppThemePreference.system:
        return 'Вариант по умолчанию (Светлый/Тёмный)';
      case AppThemePreference.light:
        return 'Светлый режим';
      case AppThemePreference.dark:
        return 'Тёмный режим';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вид')),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: AppThemeController.instance.mode,
        builder: (context, mode, child) {
          final current = switch (mode) {
            ThemeMode.light => AppThemePreference.light,
            ThemeMode.dark => AppThemePreference.dark,
            ThemeMode.system => AppThemePreference.system,
          };
          return ListView(
            children: AppThemePreference.values
                .map(
                  (pref) => ListTile(
                    title: Text(_label(pref)),
                    trailing: pref == current
                        ? const Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () =>
                        AppThemeController.instance.setPreference(pref),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

class _NotificationSettings {
  const _NotificationSettings({
    required this.pushEnabled,
    required this.pushTournament,
    required this.pushMvp,
    required this.emailEnabled,
    required this.emailDigest,
    required this.emailImportant,
  });

  final bool pushEnabled;
  final bool pushTournament;
  final bool pushMvp;
  final bool emailEnabled;
  final bool emailDigest;
  final bool emailImportant;

  factory _NotificationSettings.defaults() {
    return const _NotificationSettings(
      pushEnabled: true,
      pushTournament: true,
      pushMvp: true,
      emailEnabled: true,
      emailDigest: true,
      emailImportant: true,
    );
  }

  factory _NotificationSettings.fromMap(Map<String, dynamic> map) {
    bool b(String key, bool fallback) {
      final value = map[key];
      if (value is bool) return value;
      return fallback;
    }

    return _NotificationSettings(
      pushEnabled: b('push_enabled', true),
      pushTournament: b('push_tournament', true),
      pushMvp: b('push_mvp', true),
      emailEnabled: b('email_enabled', true),
      emailDigest: b('email_digest', true),
      emailImportant: b('email_important', true),
    );
  }

  Map<String, dynamic> toRpcParams() {
    return {
      'p_push_enabled': pushEnabled,
      'p_push_tournament': pushTournament,
      'p_push_mvp': pushMvp,
      'p_email_enabled': emailEnabled,
      'p_email_digest': emailDigest,
      'p_email_important': emailImportant,
    };
  }

  _NotificationSettings copyWith({
    bool? pushEnabled,
    bool? pushTournament,
    bool? pushMvp,
    bool? emailEnabled,
    bool? emailDigest,
    bool? emailImportant,
  }) {
    return _NotificationSettings(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      pushTournament: pushTournament ?? this.pushTournament,
      pushMvp: pushMvp ?? this.pushMvp,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      emailDigest: emailDigest ?? this.emailDigest,
      emailImportant: emailImportant ?? this.emailImportant,
    );
  }
}

class _NotificationSettingsService {
  _NotificationSettingsService();

  final supabase = Supabase.instance.client;
  static const Duration _requestTimeout = Duration(seconds: 12);

  Future<T> _withTimeout<T>(Future<T> future) {
    return future.timeout(_requestTimeout);
  }

  bool isNetworkError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('timed out') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('timeout');
  }

  bool _isSchemaMissing(Object error) {
    final text = error.toString().toLowerCase();
    final mentionsSchema =
        text.contains('profile_notification_settings') ||
        text.contains('get_my_notification_settings') ||
        text.contains('upsert_my_notification_settings');
    return mentionsSchema &&
        (text.contains('does not exist') ||
            text.contains('could not find') ||
            text.contains('function') ||
            text.contains('relation') ||
            text.contains('column'));
  }

  Future<_NotificationSettings> readLocal() async {
    final prefs = await SharedPreferences.getInstance();
    return _NotificationSettings(
      pushEnabled: prefs.getBool(_MePrefs.pushEnabledKey) ?? true,
      pushTournament: prefs.getBool(_MePrefs.pushTournamentKey) ?? true,
      pushMvp: prefs.getBool(_MePrefs.pushMvpKey) ?? true,
      emailEnabled: prefs.getBool(_MePrefs.emailEnabledKey) ?? true,
      emailDigest: prefs.getBool(_MePrefs.emailDigestKey) ?? true,
      emailImportant: prefs.getBool(_MePrefs.emailImportantKey) ?? true,
    );
  }

  Future<void> writeLocal(_NotificationSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_MePrefs.pushEnabledKey, settings.pushEnabled);
    await prefs.setBool(_MePrefs.pushTournamentKey, settings.pushTournament);
    await prefs.setBool(_MePrefs.pushMvpKey, settings.pushMvp);
    await prefs.setBool(_MePrefs.emailEnabledKey, settings.emailEnabled);
    await prefs.setBool(_MePrefs.emailDigestKey, settings.emailDigest);
    await prefs.setBool(_MePrefs.emailImportantKey, settings.emailImportant);
  }

  Future<_NotificationSettings> _readRemote() async {
    final raw = await _withTimeout(
      supabase.rpc('get_my_notification_settings'),
    );
    if (raw is Map<String, dynamic>) {
      return _NotificationSettings.fromMap(raw);
    }
    if (raw is Map) {
      return _NotificationSettings.fromMap(Map<String, dynamic>.from(raw));
    }
    return _NotificationSettings.defaults();
  }

  Future<_NotificationSettings> loadMerged() async {
    final local = await readLocal();
    try {
      final remote = await _readRemote();
      await writeLocal(remote);
      return remote;
    } catch (e) {
      if (_isSchemaMissing(e) || isNetworkError(e)) {
        return local;
      }
      return local;
    }
  }

  Future<void> save(_NotificationSettings settings) async {
    await writeLocal(settings);
    try {
      await _withTimeout(
        supabase.rpc(
          'upsert_my_notification_settings',
          params: settings.toRpcParams(),
        ),
      );
    } catch (e) {
      if (_isSchemaMissing(e)) return;
      rethrow;
    }
  }
}

class _PushSettingsPage extends StatefulWidget {
  const _PushSettingsPage({required this.settingsService});

  final _NotificationSettingsService settingsService;

  @override
  State<_PushSettingsPage> createState() => _PushSettingsPageState();
}

class _PushSettingsPageState extends State<_PushSettingsPage> {
  _NotificationSettings _settings = _NotificationSettings.defaults();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final merged = await widget.settingsService.loadMerged();
    if (!mounted) return;
    setState(() {
      _settings = merged;
      _loading = false;
    });
  }

  Future<void> _save(_NotificationSettings next) async {
    setState(() => _settings = next);
    try {
      await widget.settingsService.save(next);
    } catch (e) {
      if (!mounted) return;
      final message = widget.settingsService.isNetworkError(e)
          ? 'Сохранили локально. Сервер сейчас недоступен.'
          : 'Не удалось сохранить настройки: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Push-уведомления')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Включить Push-уведомления'),
            value: _settings.pushEnabled,
            onChanged: (v) => _save(_settings.copyWith(pushEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Напоминания о турнирах'),
            value: _settings.pushTournament,
            onChanged: _settings.pushEnabled
                ? (v) => _save(_settings.copyWith(pushTournament: v))
                : null,
          ),
          SwitchListTile(
            title: const Text('Голосование MVP'),
            value: _settings.pushMvp,
            onChanged: _settings.pushEnabled
                ? (v) => _save(_settings.copyWith(pushMvp: v))
                : null,
          ),
        ],
      ),
    );
  }
}

class _EmailSettingsPage extends StatefulWidget {
  const _EmailSettingsPage({required this.settingsService});

  final _NotificationSettingsService settingsService;

  @override
  State<_EmailSettingsPage> createState() => _EmailSettingsPageState();
}

class _EmailSettingsPageState extends State<_EmailSettingsPage> {
  _NotificationSettings _settings = _NotificationSettings.defaults();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final merged = await widget.settingsService.loadMerged();
    if (!mounted) return;
    setState(() {
      _settings = merged;
      _loading = false;
    });
  }

  Future<void> _save(_NotificationSettings next) async {
    setState(() => _settings = next);
    try {
      await widget.settingsService.save(next);
    } catch (e) {
      if (!mounted) return;
      final message = widget.settingsService.isNetworkError(e)
          ? 'Сохранили локально. Сервер сейчас недоступен.'
          : 'Не удалось сохранить настройки: $e';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Уведомления по эл. почте')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Включить e-mail уведомления'),
            value: _settings.emailEnabled,
            onChanged: (v) => _save(_settings.copyWith(emailEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Сводка за день'),
            value: _settings.emailDigest,
            onChanged: _settings.emailEnabled
                ? (v) => _save(_settings.copyWith(emailDigest: v))
                : null,
          ),
          SwitchListTile(
            title: const Text('Важные события (MVP, турниры)'),
            value: _settings.emailImportant,
            onChanged: _settings.emailEnabled
                ? (v) => _save(_settings.copyWith(emailImportant: v))
                : null,
          ),
        ],
      ),
    );
  }
}

class _HelpPage extends StatelessWidget {
  const _HelpPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Справка')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Text(
            'Если что-то не работает:\n'
            '1. Проверь интернет/VPN.\n'
            '2. Обнови экран кнопкой "Повторить" или pull-to-refresh.\n'
            '3. Если ошибка повторяется, отправь скрин и время ошибки администратору.',
          ),
        ],
      ),
    );
  }
}

class _TrainingItem {
  const _TrainingItem({
    required this.tournamentId,
    required this.hallName,
    required this.date,
    required this.completed,
  });

  final String tournamentId;
  final String hallName;
  final DateTime? date;
  final bool completed;
}

class _MePrefs {
  static const String pushEnabledKey = 'me_push_enabled';
  static const String pushTournamentKey = 'me_push_tournament';
  static const String pushMvpKey = 'me_push_mvp';

  static const String emailEnabledKey = 'me_email_enabled';
  static const String emailDigestKey = 'me_email_digest';
  static const String emailImportantKey = 'me_email_important';
}
