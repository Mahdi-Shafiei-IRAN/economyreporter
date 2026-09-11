/// کنترل تم روشن/تیره/سیستم + ذخیره‌سازی انتخاب کاربر.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// نمونه‌ی سراسری (مثل navigatorKey) تا از هرجا در دسترس باشد.
final ThemeController themeController = ThemeController();

class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = _fromString(prefs.getString(_key));
    } catch (_) {
      _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, _toString(m));
    } catch (_) {
      // نادیده — ذخیره‌سازی حیاتی نیست
    }
  }

  /// چرخه: سیستم → روشن → تیره → سیستم
  Future<void> cycle() async {
    final next = switch (_mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setMode(next);
  }

  static ThemeMode _fromString(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _toString(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}
