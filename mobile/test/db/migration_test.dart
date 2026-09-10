import 'dart:io';

import 'package:economy/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/db_test_helper.dart';

void main() {
  setUpAll(initSqfliteFfiForTests);

  test('ارتقای نسخه ۱ → ۲ ستون account_ref را اضافه می‌کند و داده حفظ می‌شود',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('econ_mig');
    final path = '${tmpDir.path}/v1.db';

    // ساخت یک دیتابیس نسخه ۱ (بدون account_ref) و درج یک رکورد
    final v1 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE transactions (
              id TEXT PRIMARY KEY,
              kind TEXT NOT NULL,
              amount_rial INTEGER,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    final now = DateTime.utc(2026).toIso8601String();
    await v1.insert('transactions', {
      'id': 'old-1',
      'kind': 'expense',
      'amount_rial': 1000,
      'created_at': now,
      'updated_at': now,
    });
    await v1.close();

    // بازکردن با نسخه ۲ → onUpgrade اجرا می‌شود
    final v2 = await openAppDatabase(path: path);

    final columns = (await v2.rawQuery('PRAGMA table_info(transactions)'))
        .map((r) => r['name'] as String)
        .toSet();
    expect(columns, contains('account_ref'));

    // داده‌ی قدیمی حفظ شده است
    final rows = await v2.query('transactions');
    expect(rows, hasLength(1));
    expect(rows.first['id'], 'old-1');

    await v2.close();
    await tmpDir.delete(recursive: true);
  });
}
