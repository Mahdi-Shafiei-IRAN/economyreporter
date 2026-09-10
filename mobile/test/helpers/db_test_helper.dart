/// راه‌اندازی sqflite برای تست‌های دسکتاپ (بدون گوشی).
///
/// روی ویندوز اگر `sqlite3.dll` پیدا نشد، به `winsqlite3.dll` (همراه ویندوز)
/// برمی‌گردیم تا تست‌ها بدون نصب دستی کتابخانه اجرا شوند.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

bool _initialized = false;

void initSqfliteFfiForTests() {
  if (_initialized) return;
  if (Platform.isWindows) {
    open.overrideFor(OperatingSystem.windows, _openSqliteOnWindows);
  }
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _initialized = true;
}

DynamicLibrary _openSqliteOnWindows() {
  for (final name in ['sqlite3.dll', 'winsqlite3.dll']) {
    try {
      return DynamicLibrary.open(name);
    } catch (_) {
      // امتحان نام بعدی
    }
  }
  // اگر هیچ‌کدام نبود، این خط خطای واضح تولید می‌کند.
  return DynamicLibrary.open('sqlite3.dll');
}
