import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference { system, light, dark }

class AppThemeController {
  AppThemeController._();

  static final AppThemeController instance = AppThemeController._();

  static const String _prefKey = 'app_theme_preference';
  final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    final pref = AppThemePreference.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => AppThemePreference.system,
    );
    mode.value = _toThemeMode(pref);
  }

  AppThemePreference get preference {
    switch (mode.value) {
      case ThemeMode.light:
        return AppThemePreference.light;
      case ThemeMode.dark:
        return AppThemePreference.dark;
      case ThemeMode.system:
        return AppThemePreference.system;
    }
  }

  Future<void> setPreference(AppThemePreference pref) async {
    mode.value = _toThemeMode(pref);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, pref.name);
  }

  ThemeMode _toThemeMode(AppThemePreference pref) {
    switch (pref) {
      case AppThemePreference.light:
        return ThemeMode.light;
      case AppThemePreference.dark:
        return ThemeMode.dark;
      case AppThemePreference.system:
        return ThemeMode.system;
    }
  }
}
