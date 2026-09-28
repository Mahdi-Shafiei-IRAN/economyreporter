import 'dart:io';

import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/store/app_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/db_test_helper.dart';

void main() {
  setUpAll(initSqfliteFfiForTests);

  Future<Set<String>> tables(Database db) async =>
      (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'] as String)
          .toSet();

  test('۱۳ → ۱۴: جدول‌های نسخه‌ی ۱ و تنظیم‌هایش پاک می‌شوند؛ دسته‌ی پیامک‌ها و دفترِ نسخه‌ی ۲ می‌مانند',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('econ_mig14');
    final path = '${tmpDir.path}/v13.db';
    final at = DateTime.utc(2026, 9, 20).toIso8601String();

    // نسخه‌ی ۱۳ = اسکیمای فعلی + جدول‌های نسخه‌ی ۱.
    final v13 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 13,
        onCreate: (db, _) async {
          await createSchema(db);
          await db.execute('''
            CREATE TABLE transactions (
              id TEXT PRIMARY KEY, kind TEXT NOT NULL, amount_rial INTEGER,
              sms_sender TEXT, sms_body TEXT, sms_content_hash TEXT, deleted_at TEXT,
              created_at TEXT NOT NULL, updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE transaction_categories (
              id TEXT PRIMARY KEY, transaction_id TEXT NOT NULL,
              category_id TEXT NOT NULL, amount_rial INTEGER NOT NULL
            )
          ''');
          await db.execute(
              'CREATE TABLE outbox (transaction_id TEXT PRIMARY KEY, payload TEXT NOT NULL)');
        },
      ),
    );
    final cat = {for (final r in await v13.query('categories')) r['name'] as String: r['id'] as String};
    Future<void> tx(String id, String? hash, List<String> cats, {bool deleted = false}) async {
      await v13.insert('transactions', {
        'id': id,
        'kind': 'expense',
        'amount_rial': 1000,
        'sms_sender': 'Bank Mellat',
        'sms_body': 'متنِ خامِ پیامک $id',
        'sms_content_hash': hash,
        'deleted_at': deleted ? at : null,
        'created_at': at,
        'updated_at': at,
      });
      for (final c in cats) {
        await v13.insert('transaction_categories',
            {'id': '$id-$c', 'transaction_id': id, 'category_id': cat[c], 'amount_rial': 500});
      }
      await v13.insert('outbox', {'transaction_id': id, 'payload': '{}'});
    }

    await tx('bread', 'h1', ['نان', 'لبنیات']);
    await tx('same-sms-again', 'h1', ['نان']);
    await tx('deleted', 'h2', ['سلامت'], deleted: true);
    await tx('manual', null, ['قبوض']);
    for (final k in ['auto_removed', 'inbox_watermark', 'pull_cursor', 'last_sync', 'kept_transactions']) {
      await v13.insert('settings', {'key': k, 'value': 'x'});
    }
    await v13.insert('settings', {'key': 'me_user_id', 'value': 'u1'});
    await v13.insert('settings', {'key': 'ledger_start_date', 'value': at});
    await v13.insert('wallets', {'id': 'm1', 'owner_name': 'مهدی', 'label': 'ملت', 'created_at': at});
    await v13.close();

    final db = await openAppDatabase(path: path);
    final names = await tables(db);
    expect(names, isNot(contains('transactions')));
    expect(names, isNot(contains('transaction_categories')));
    expect(names, isNot(contains('outbox')));
    final kept = await db.query('legacy_sms_categories', orderBy: 'category_id');
    expect({for (final r in kept) (r['content_hash'], r['category_id'])},
        {('h1', cat['نان']), ('h1', cat['لبنیات'])}); // حذف‌شده و بی‌اثرانگشت نه
    final settings = {for (final r in await db.query('settings')) r['key']: r['value']};
    expect(settings.keys, containsAll(['me_user_id', 'ledger_start_date']));
    for (final k in kV1SettingKeys) {
      expect(settings.containsKey(k), isFalse, reason: k);
    }
    expect((await db.query('wallets')).single['id'], 'm1');
    expect(await db.query('categories'), hasLength(kDefaultCategories.length));

    await db.close();
    await tmpDir.delete(recursive: true);
  });

  test('نصبِ تازه: جدول‌های نسخه‌ی ۱ ساخته نمی‌شوند', () async {
    final db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    final names = await tables(db);
    expect(names, containsAll(['categories', 'wallets', 'budgets', 'settings', 'allowed_senders',
      'ledger_entries', 'ledger_checkpoints', 'sms_items', 'legacy_sms_categories']));
    expect(names.intersection({'transactions', 'transaction_categories', 'outbox'}), isEmpty);
    await db.close();
  });

  test('ارتقای نسخه ۵ → ۶: جدول فرستنده‌های مجاز ساخته می‌شود و داده حفظ می‌شود',
      () async {
    final tmpDir = await Directory.systemTemp.createTemp('econ_mig6');
    final path = '${tmpDir.path}/v5.db';
    // نسخه‌ی ۵ی ساختگی: اسکیمای فعلی بدون جدول فرستنده‌های مجاز (مهاجرت‌ها جدولِ نبوده را نادیده می‌گیرند).
    final v5 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (db, _) async {
          await createSchema(db);
          await db.execute('DROP TABLE allowed_senders');
        },
      ),
    );
    await v5.insert('settings', {'key': 'me_user_id', 'value': 'u1'});
    await v5.close();

    final v6 = await openAppDatabase(path: path);
    final repo = AppStore(v6);
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
    final names = await tables(db);
    expect(names, containsAll(['allowed_senders', 'settings', 'wallets', 'categories', 'ledger_entries']));
    expect(names, isNot(contains('transactions')));

    await db.close();
    await tmpDir.delete(recursive: true);
  });
}
