import 'package:economy/core/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('پیش‌فرض system و چرخه‌ی روشن/تیره/سیستم', () async {
    final c = ThemeController();
    await c.load();
    expect(c.mode, ThemeMode.system);
    await c.cycle();
    expect(c.mode, ThemeMode.light);
    await c.cycle();
    expect(c.mode, ThemeMode.dark);
    await c.cycle();
    expect(c.mode, ThemeMode.system);
  });

  test('انتخاب کاربر ذخیره و بازخوانی می‌شود', () async {
    final c = ThemeController();
    await c.setMode(ThemeMode.dark);
    final c2 = ThemeController();
    await c2.load();
    expect(c2.mode, ThemeMode.dark);
  });
}
