/// باز کردن و ساخت پایگاه‌داده‌ی محلی (SQLite).
///
/// در اپ روی اندروید، `databaseFactory` را خود پلاگین sqflite تنظیم می‌کند.
/// در تست‌های دسکتاپ، با sqflite_common_ffi تنظیم می‌شود (test/helpers).
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

const String kDbName = 'economy.db';
const int kDbVersion = 6;

/// دسته‌های پیش‌فرض (قابل ویرایش توسط کاربر بعداً).
const List<String> kDefaultCategories = [
  'سبزیجات',
  'میوه',
  'گوشت',
  'مرغ',
  'نان',
  'لبنیات',
  'خواروبار',
  'حمل‌ونقل',
  'قبوض',
  'سلامت',
  'پوشاک',
  'سرگرمی',
  'رستوران',
  'حقوق و درآمد',
  'سایر',
];

/// پایگاه‌داده را باز می‌کند. اگر [path] داده نشود، مسیر پیش‌فرض دستگاه.
/// برای تست، `inMemoryDatabasePath` پاس داده می‌شود.
///
/// [singleInstance]=false برای ایزوله‌ی پس‌زمینه: اتصال جدا می‌سازد تا بستنش
/// اتصالِ اپِ اصلی (در همان پروسه) را نبندد.
Future<Database> openAppDatabase({String? path, bool singleInstance = true}) async {
  final dbPath = path ?? p.join(await databaseFactory.getDatabasesPath(), kDbName);
  return databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: kDbVersion,
      singleInstance: singleInstance,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        // اپ و ایزوله‌ی پس‌زمینه‌ی پیامک ممکن است هم‌زمان بنویسند.
        await db.rawQuery('PRAGMA busy_timeout = 5000');
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
  if (oldVersion < 3) {
    // نسخه ۳: دسته‌بندی (دسته‌ها + تخصیص چندتاییِ مبلغ به دسته‌ها).
    await _createCategoryTables(db);
    await _seedCategories(db);
  }
  if (oldVersion < 4) {
    // نسخه ۴: کیف‌ها (کارت/حساب اعضا).
    await _createWalletsTable(db);
  }
  if (oldVersion < 5) {
    // نسخه ۵: متن و زمان پیامک، حذف نرم، دلیل بازبینی، صاحب کارت، تنظیمات.
    for (final column in _v5TransactionColumns) {
      await db.execute('ALTER TABLE transactions ADD COLUMN $column');
    }
    await db.execute('ALTER TABLE wallets ADD COLUMN owner_user_id TEXT');
    await _createV5Indexes(db);
    await _createSettingsTable(db);
    await _dropUnknownBankReviews(db);
  }
  if (oldVersion < 6) {
    // نسخه ۶: فرستنده‌های مجاز پیامک (فقط پیامک این‌ها خودکار ثبت می‌شود).
    await _createAllowedSendersTable(db);
  }
}

/// «بانک ناشناخته» دیگر دلیل بازبینی نیست؛ فقط مبلغ/نوعِ نامشخص (مهاجرت نسخه ۵).
Future<void> _dropUnknownBankReviews(Database db) async {
  final columns = (await db.rawQuery('PRAGMA table_info(transactions)'))
      .map((r) => r['name'] as String)
      .toSet();
  if (!columns.contains('needs_review')) return;
  await db.execute('''
    UPDATE transactions SET needs_review = 0
    WHERE needs_review = 1 AND amount_rial IS NOT NULL AND kind != 'unknown'
  ''');
  await db.execute('''
    UPDATE transactions SET review_reason =
      CASE WHEN amount_rial IS NULL AND kind = 'unknown' THEN 'amount,kind'
           WHEN amount_rial IS NULL THEN 'amount'
           ELSE 'kind' END
    WHERE needs_review = 1
  ''');
}

/// ستون‌های افزوده‌ی نسخه‌ی ۵ به جدول تراکنش‌ها.
const List<String> _v5TransactionColumns = [
  // متن و فرستنده‌ی خام پیامک — فقط روی همین گوشی؛ هرگز sync یا لاگ نمی‌شود.
  'sms_sender TEXT',
  'sms_body TEXT',
  // زمان رسیدن پیامک (برای ترتیب درست وقتی تاریخ داخل متن نیست).
  'sms_received_at TEXT',
  // اثرانگشتِ محتوا بدون زمان؛ ضدتکرار بین دریافت زنده و خواندن صندوق.
  'sms_content_hash TEXT',
  // حذف نرم: ردیف می‌ماند تا همان پیامک دوباره وارد نشود.
  'deleted_at TEXT',
  // دلیل بازبینی: amount | kind | failed (با ویرگول).
  'review_reason TEXT',
  // صاحب تراکنش (عضو خانواده‌ای که کارت مال اوست) + برچسب کارت.
  'owner_user_id TEXT',
  'owner_name TEXT',
  'wallet_label TEXT',
  // local = پیامکش روی همین گوشی آمده؛ remote = از سرور (گوشی عضو دیگر).
  "origin TEXT NOT NULL DEFAULT 'local'",
];

/// ساخت جداول نسخه‌ی فعلی.
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
      updated_at TEXT NOT NULL,
      ${_v5TransactionColumns.join(',\n      ')}
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
  await _createV5Indexes(db);

  // صف خروجی همگام‌سازی: هر ردیف یعنی «این تراکنش باید به سرور برود».
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

  await _createCategoryTables(db);
  await _seedCategories(db);
  await _createWalletsTable(db);
  await db.execute('ALTER TABLE wallets ADD COLUMN owner_user_id TEXT');
  await _createSettingsTable(db);
  await _createAllowedSendersTable(db);
}

Future<void> _createV5Indexes(Database db) async {
  await db.execute(
    'CREATE INDEX idx_tx_content ON transactions(sms_content_hash)',
  );
  await db.execute('CREATE INDEX idx_tx_owner ON transactions(owner_user_id)');
}

/// تنظیمات کلید-مقدار (در ایزوله‌ی پس‌زمینه هم در دسترس است).
Future<void> _createSettingsTable(Database db) async {
  await db.execute('''
    CREATE TABLE settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )
  ''');
}

/// فرستنده‌های مجاز پیامک بانکی (سرشماره یا نام) که خود کاربر تعیین می‌کند.
Future<void> _createAllowedSendersTable(Database db) async {
  await db.execute('''
    CREATE TABLE allowed_senders (
      id TEXT PRIMARY KEY,
      address TEXT NOT NULL,
      bank_id TEXT,
      created_at TEXT NOT NULL
    )
  ''');
}

/// جدول کیف‌ها: کارت/حساب هر عضو خانواده.
Future<void> _createWalletsTable(Database db) async {
  await db.execute('''
    CREATE TABLE wallets (
      id TEXT PRIMARY KEY,
      owner_name TEXT NOT NULL,
      label TEXT NOT NULL,
      bank_id TEXT,
      card_last4 TEXT,
      account_ref TEXT,
      created_at TEXT NOT NULL
    )
  ''');
}

/// جدول‌های دسته‌بندی: دسته‌ها + تخصیص مبلغ هر تراکنش به چند دسته.
Future<void> _createCategoryTables(Database db) async {
  await db.execute('''
    CREATE TABLE categories (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      is_system INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE transaction_categories (
      id TEXT PRIMARY KEY,
      transaction_id TEXT NOT NULL,
      category_id TEXT NOT NULL,
      amount_rial INTEGER NOT NULL,
      UNIQUE(transaction_id, category_id)
    )
  ''');
  await db.execute(
    'CREATE INDEX idx_txcat_tx ON transaction_categories(transaction_id)',
  );
  await db.execute(
    'CREATE INDEX idx_txcat_cat ON transaction_categories(category_id)',
  );
}

Future<void> _seedCategories(Database db) async {
  const uuid = Uuid();
  final now = DateTime.now().toUtc().toIso8601String();
  final batch = db.batch();
  for (final name in kDefaultCategories) {
    batch.insert(
      'categories',
      {'id': uuid.v4(), 'name': name, 'is_system': 1, 'created_at': now},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
  await batch.commit(noResult: true);
}
