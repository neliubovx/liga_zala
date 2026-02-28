import 'dart:async';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushTokenService {
  PushTokenService._();

  static final PushTokenService instance = PushTokenService._();

  static const String _deviceIdKey = 'push_device_id_v1';
  static const String _lastTokenKey = 'push_last_token_v1';

  final supabase = Supabase.instance.client;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _messageSub;
  bool _started = false;
  bool _firebaseReady = false;
  bool _syncInFlight = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      _firebaseReady = await _tryInitFirebase();
      if (!_firebaseReady) return;

      _authSub = supabase.auth.onAuthStateChange.listen((event) {
        final type = event.event;
        if (type == AuthChangeEvent.signedOut) return;
        unawaited(syncNow());
      });

      try {
        _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(
          (token) => unawaited(_upsertToken(token)),
          onError: (error, stackTrace) {
            debugPrint('⚠️ Push token refresh failed: $error');
          },
        );
      } catch (error) {
        debugPrint('⚠️ Push token refresh subscribe failed: $error');
      }

      // iOS: show system banners while app is in foreground.
      try {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
              alert: true,
              badge: true,
              sound: true,
            );
      } catch (error) {
        debugPrint('⚠️ Push foreground presentation setup failed: $error');
      }

      _messageSub = FirebaseMessaging.onMessage.listen((message) {
        final title = message.notification?.title ?? '';
        final body = message.notification?.body ?? '';
        debugPrint('🔔 Push received in foreground: "$title" "$body"');
      });

      unawaited(syncNow());
    } catch (error) {
      debugPrint('⚠️ Push service start failed: $error');
    }
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenRefreshSub?.cancel();
    await _messageSub?.cancel();
    _authSub = null;
    _tokenRefreshSub = null;
    _messageSub = null;
  }

  Future<bool> _tryInitFirebase() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      return true;
    } catch (error) {
      debugPrint('⚠️ Firebase push disabled (init failed): $error');
      return false;
    }
  }

  Future<void> syncNow() async {
    if (!_firebaseReady) return;
    if (_syncInFlight) return;
    if (supabase.auth.currentUser == null) return;

    _syncInFlight = true;
    try {
      final permissionGranted = await _ensurePushPermission();
      if (!permissionGranted) return;

      final token = await _readCurrentTokenWithRetry();
      if (token == null || token.isEmpty) return;
      await _upsertToken(token);
    } catch (error) {
      debugPrint('⚠️ Push token sync failed: $error');
    } finally {
      _syncInFlight = false;
    }
  }

  Future<void> deactivateCurrentToken() async {
    if (!_firebaseReady) return;
    if (supabase.auth.currentUser == null) return;

    try {
      final token = await _readCurrentTokenOrCached();
      if (token == null || token.isEmpty) return;

      try {
        await supabase.rpc(
          'deactivate_my_fcm_token',
          params: {'p_fcm_token': token},
        );
      } catch (rpcError) {
        if (!_isMissingRpc(rpcError, 'deactivate_my_fcm_token')) {
          rethrow;
        }
        await supabase.rpc(
          'deactivate_my_push_token',
          params: {'p_expo_push_token': token},
        );
      }
    } catch (error) {
      debugPrint('⚠️ Push token deactivate failed: $error');
    }
  }

  Future<void> _upsertToken(String rawToken) async {
    final token = rawToken.trim();
    if (token.isEmpty) return;
    if (supabase.auth.currentUser == null) return;

    final deviceId = await _deviceId();
    final platform = _platformLabel();

    try {
      await supabase.rpc(
        'upsert_my_fcm_token',
        params: {
          'p_fcm_token': token,
          'p_device_id': deviceId,
          'p_platform': platform,
        },
      );
    } catch (rpcError) {
      if (!_isMissingRpc(rpcError, 'upsert_my_fcm_token')) {
        rethrow;
      }
      await supabase.rpc(
        'upsert_my_push_token',
        params: {
          'p_expo_push_token': token,
          'p_device_id': deviceId,
          'p_platform': platform,
        },
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastTokenKey, token);
  }

  bool _isMissingRpc(Object error, String rpcName) {
    final text = error.toString().toLowerCase();
    return text.contains(rpcName.toLowerCase()) &&
        (text.contains('function') ||
            text.contains('does not exist') ||
            text.contains('could not find'));
  }

  Future<bool> _ensurePushPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<String?> _readCurrentTokenWithRetry() async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      final token = await FirebaseMessaging.instance.getToken();
      final normalized = token?.trim();
      if (normalized != null && normalized.isNotEmpty) return normalized;
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }
    return null;
  }

  Future<String?> _readCurrentTokenOrCached() async {
    final current = await FirebaseMessaging.instance.getToken();
    final normalized = current?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastTokenKey)?.trim();
  }

  Future<String> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await prefs.setString(_deviceIdKey, id);
    return id;
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
