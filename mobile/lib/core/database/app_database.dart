/// باز کردن و ساخت پایگاه‌داده‌ی محلی (SQLite).
///
/// در اپ روی اندروید، `databaseFactory` را خود پلاگین sqflite تنظیم می‌کند.
/// در تست‌های دسکتاپ، با sqflite_common_ffi تنظیم می‌شود (test/helpers).
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const String kDbName = 'economy.db';
const int kDbVersion = 2;

/// پایگاه‌داده را باز می‌کند. اگر [path] داده نشود، مسیر پیش‌فرض دستگاه.
/// برای تست، `inMemoryDatabasePath` پاس داده می‌شود.
Future<Database> openAppDatabase({String? path}) async {
  final dbPath = path ?? p.join(await databaseFactory.getDatabasesPath(), kDbName);
  return databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: kDbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await migrateSchema(db, oldVersion, newVersion);
      },
    ),
  );
}

/// مهاجرت‌های نسخه‌به‌نسخه (داده‌ی موجود حفظ می‌شود).
Future<void> migrateSchema(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    // نسخه ۲: افزودن شماره‌ی حساب برای تطبیق مانده‌ی بانک‌های حساب‌محور.
    await db.execute('ALTER TABLE transactions ADD COLUMN account_ref TEXT');
  }
}

/// ساخت جداول نسخه‌ی ۱.
Future<void> createSchema(Database db) async {
  await db.execute('''
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      bank_id TEXT,
      kind TEXT NOT NULL,
      amount_rial INTEGER,
      balance_after_rial INTEGER,
      raw_amount TEXT,
      raw_unit TEXT NOT NULL DEFAULT 'rial',
      card_last4 TEXT,
      account_ref TEXT,
      counterparty TEXT,
      description TEXT,
      transaction_date TEXT,
      client_created_at TEXT,
      source TEXT NOT NULL DEFAULT 'sms',
      source_message_hash TEXT,
      device_id TEXT,
      needs_review INTEGER NOT NULL DEFAULT 0,
      sync_status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  await db.execute(
    'CREATE INDEX idx_tx_date ON transactions(transaction_date)',
  );
  await db.execute('CREATE INDEX idx_tx_kind ON transactions(kind)');
  await db.execute('CREATE INDEX idx_tx_sync ON transactions(sync_status)');

  // ضدتکرارِ پیامک در سطح دیتابیس (ایندکس یکتای جزئی؛ رکوردهای دستی hash ندارند).
  await db.execute('''
    CREATE UNIQUE INDEX idx_tx_source_hash
    ON transactions(source_message_hash)
    WHERE source_message_hash IS NOT NULL
  ''');

  // صف خروجی برای همگام‌سازی (فاز Sync پر می‌شود؛ اسکیمای آماده).
  await db.execute('''
    CREATE TABLE outbox (
      transaction_id TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      retry_count INTEGER NOT NULL DEFAULT 0,
      last_attempt_at TEXT,
      next_retry_at TEXT,
      last_error TEXT
    )
  ''');
}
