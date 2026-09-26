/// جدول‌های دفترِ نسخه‌ی ۲ (schema نسخه‌ی ۱۱). نقطه‌ی مانده‌ی بانکی ذخیره نمی‌شود؛
/// از `ledger_entries.bank_balance_after` مشتق می‌شود.
library;

import 'package:sqflite/sqflite.dart';

Future<void> createLedgerTables(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ledger_entries (
      id TEXT PRIMARY KEY,
      account_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      is_transfer INTEGER NOT NULL DEFAULT 0,
      transfer_pair_id TEXT,
      amount_rial INTEGER NOT NULL,
      occurred_at TEXT NOT NULL,
      bank_balance_after INTEGER,
      source TEXT NOT NULL,
      sms_key TEXT,
      note TEXT,
      created_by_device TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      sync_status TEXT NOT NULL DEFAULT 'pending'
    )
  ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_le_account ON ledger_entries(account_id, occurred_at)');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ledger_checkpoints (
      id TEXT PRIMARY KEY,
      account_id TEXT NOT NULL,
      at TEXT NOT NULL,
      balance_rial INTEGER NOT NULL,
      note TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      sync_status TEXT NOT NULL DEFAULT 'pending'
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sms_items (
      key TEXT PRIMARY KEY,
      content_hash TEXT NOT NULL,
      sender TEXT NOT NULL,
      received_at TEXT NOT NULL,
      body TEXT,
      sugg_kind TEXT,
      sugg_amount INTEGER,
      sugg_balance INTEGER,
      sugg_occurred_at TEXT,
      sugg_account_id TEXT,
      sugg_account_reason TEXT,
      sugg_not_tx TEXT,
      sugg_duplicate INTEGER NOT NULL DEFAULT 0,
      sugg_new_account INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending',
      entry_id TEXT,
      reject_reason TEXT,
      decided_at TEXT,
      parser_version INTEGER NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'pending'
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_sms_hash ON sms_items(content_hash)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_sms_status ON sms_items(status)');
  // schema ۱۲: دسته‌های هر تراکنشِ دفتر (تقسیمِ مساوی؛ روی جدولِ categories نسخه‌ی ۱).
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ledger_entry_categories (
      entry_id TEXT NOT NULL,
      category_id TEXT NOT NULL,
      amount_rial INTEGER NOT NULL,
      PRIMARY KEY (entry_id, category_id)
    )
  ''');
  // schema ۱۳: تصمیم‌های پیامک که از سرور آمده‌اند (بعد از نصبِ دوباره)؛ هر وقت همان پیامک
  // از صندوق خوانده شود، همین تصمیم را می‌گیرد (I5). بدونِ متن و فرستنده.
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ledger_remote_decisions (
      key TEXT PRIMARY KEY,
      content_hash TEXT NOT NULL,
      received_at TEXT NOT NULL,
      status TEXT NOT NULL,
      reject_reason TEXT,
      entry_id TEXT,
      decided_at TEXT
    )
  ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_remote_dec_hash ON ledger_remote_decisions(content_hash)');
}
