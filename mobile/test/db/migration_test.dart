import 'dart:io';

import 'package:economy/core/database/app_database.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
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

    // بازکردن با نسخه‌ی فعلی → onUpgrade اجرا می‌شود
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

  test('ارتقای نسخه ۴ → ۵: ستون‌های جدید، تنظیمات، و حذف بازبینیِ «بانک ناشناخته»',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('econ_mig5');
    final path = '${tmpDir.path}/v4.db';

    final v4 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE transactions (
              id TEXT PRIMARY KEY, bank_id TEXT, kind TEXT NOT NULL,
              amount_rial INTEGER, balance_after_rial INTEGER, raw_amount TEXT,
              raw_unit TEXT NOT NULL DEFAULT 'rial', card_last4 TEXT, account_ref TEXT,
              counterparty TEXT, description TEXT, transaction_date TEXT,
              client_created_at TEXT, source TEXT NOT NULL DEFAULT 'sms',
              source_message_hash TEXT, device_id TEXT,
              needs_review INTEGER NOT NULL DEFAULT 0,
              sync_status TEXT NOT NULL DEFAULT 'pending',
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE outbox (
              transaction_id TEXT PRIMARY KEY, payload TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'pending',
              retry_count INTEGER NOT NULL DEFAULT 0, last_attempt_at TEXT,
              next_retry_at TEXT, last_error TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE categories (
              id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE,
              is_system INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE transaction_categories (
              id TEXT PRIMARY KEY, transaction_id TEXT NOT NULL,
              category_id TEXT NOT NULL, amount_rial INTEGER NOT NULL,
              UNIQUE(transaction_id, category_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE wallets (
              id TEXT PRIMARY KEY, owner_name TEXT NOT NULL, label TEXT NOT NULL,
              bank_id TEXT, card_last4 TEXT, account_ref TEXT, created_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    final now = DateTime.utc(2026, 9, 1).toIso8601String();
    Map<String, Object?> row(String id, {int? amount, String kind = 'expense'}) => {
          'id': id,
          'kind': kind,
          'amount_rial': amount,
          'needs_review': 1,
          'created_at': now,
          'updated_at': now,
        };
    // قبلاً فقط به‌خاطر «بانک ناشناخته» در صف بازبینی بود
    await v4.insert('transactions', row('bank-unknown', amount: 1000));
    // واقعاً مبهم: مبلغ و نوع نامعلوم
    await v4.insert('transactions', row('no-amount', kind: 'unknown'));
    await v4.close();

    final v5 = await openAppDatabase(path: path);
    final cols = (await v5.rawQuery('PRAGMA table_info(transactions)'))
        .map((r) => r['name'] as String)
        .toSet();
    expect(
        cols,
        containsAll([
          'sms_body',
          'sms_received_at',
          'sms_content_hash',
          'deleted_at',
          'owner_user_id',
          'owner_name',
          'origin',
          'review_reason',
        ]));
    final walletCols = (await v5.rawQuery('PRAGMA table_info(wallets)'))
        .map((r) => r['name'] as String)
        .toSet();
    expect(walletCols, contains('owner_user_id'));

    final repo = TransactionRepository(v5);
    await repo.setSetting('k', 'v');
    expect(await repo.getSetting('k'), 'v');

    final a = await repo.getById('bank-unknown');
    expect(a!.needsReview, isFalse);
    expect(a.origin, 'local');
    final b = await repo.getById('no-amount');
    expect(b!.needsReview, isTrue);
    expect(b.reviewReasons, ['amount', 'kind']);

    await v5.close();
    await tmpDir.delete(recursive: true);
  });

  test('ارتقای نسخه ۵ → ۶: جدول فرستنده‌های مجاز ساخته می‌شود و داده حفظ می‌شود',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('econ_mig6');
    final path = '${tmpDir.path}/v5.db';
    final v5 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, _) async {
          await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
        },
      ),
    );
    await v5.insert('settings', {'key': 'me_user_id', 'value': 'u1'});
    await v5.close();

    final v6 = await openAppDatabase(path: path);
    final repo = TransactionRepository(v6);
    expect(await repo.getSetting('me_user_id'), 'u1');
    expect(await repo.allowedSenders(), isEmpty);
    await repo.addAllowedSender('BankMellat', bankId: 'mellat');
    expect((await repo.allowedSenders()).single.bankId, 'mellat');

    await v6.close();
    await tmpDir.delete(recursive: true);
  });

  test('از نسخه ۱ تا آخر: مهاجرت ۵ مهاجرت‌های بعدی را جا نمی‌اندازد', () async {
    final tmpDir = await Directory.systemTemp.createTemp('econ_mig_all');
    final path = '${tmpDir.path}/v1.db';
    final v1 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          // بدون needs_review — همان حالتی که مهاجرت ۵ زودتر برمی‌گشت
          await db.execute('''
            CREATE TABLE transactions (
              id TEXT PRIMARY KEY, kind TEXT NOT NULL, amount_rial INTEGER,
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    await v1.close();

    final db = await openAppDatabase(path: path);
    final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
        .map((r) => r['name'] as String)
        .toSet();
    expect(tables, containsAll(['allowed_senders', 'settings', 'wallets', 'categories']));

    await db.close();
    await tmpDir.delete(recursive: true);
  });
}
