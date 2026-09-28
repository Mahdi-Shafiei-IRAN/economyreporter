/// باز کردن و ساخت پایگاه‌داده‌ی محلی (SQLite).
///
/// در اپ روی اندروید، `databaseFactory` را خود پلاگین sqflite تنظیم می‌کند.
/// در تست‌های دسکتاپ، با sqflite_common_ffi تنظیم می‌شود (test/helpers).
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../ledger/ledger_schema.dart';

const String kDbName = 'economy.db';
const int kDbVersion = 14;

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
  if (oldVersion < 7) {
    // نسخه ۷: صاحبِ هر فرستنده (تا پیامک‌های بی‌شماره مثل دیجی‌پی هم نسبت داده شوند).
    // idempotent: اگر جدول در مهاجرت ۶ با شکلِ جدید ساخته شده باشد، ستون‌ها از قبل هستند.
    await _ensureColumn(db, 'allowed_senders', 'owner_name', 'TEXT');
    await _ensureColumn(db, 'allowed_senders', 'owner_user_id', 'TEXT');
  }
  if (oldVersion < 8) {
    // نسخه ۸: هم‌گام‌سازی کیف‌ها (کارت/حساب) با سرور تا اعضای خانواده هم ببینند.
    await _addWalletSyncColumns(db);
  }
  if (oldVersion < 9) {
    // نسخه ۹: بودجه‌ها (سقفِ ماهانه‌ی هر دسته) + هم‌گام‌سازی.
    await _createBudgetsTable(db);
  }
  if (oldVersion < 10) {
    // نسخه ۱۰: انتسابِ دستیِ تراکنش به یک کارتِ مشخص (وقتی پیامک شماره ندارد و
    // شخص چند حساب در یک بانک دارد). این انتساب پایدار می‌ماند.
    await _ensureColumn(db, 'transactions', 'pinned_wallet_id', 'TEXT');
  }
  if (oldVersion < 11) {
    // نسخه ۱۱: دفترِ نسخه‌ی ۲ (پشتِ پرچمِ ledger_v2؛ docs/v2-design.md). هیچ تراکنشی نمی‌سازد.
    await _ensureColumn(db, 'wallets', 'archived', 'INTEGER NOT NULL DEFAULT 0');
    await createLedgerTables(db);
  }
  if (oldVersion < 12) {
    // نسخه ۱۲: دسته‌های تراکنشِ دفترِ نسخه‌ی ۲ (جدول‌ها «IF NOT EXISTS» ساخته می‌شوند).
    await createLedgerTables(db);
  }
  if (oldVersion < 13) {
    // نسخه ۱۳: تصمیم‌های پیامکِ دریافتی از سرور (همگام‌سازیِ نسخه‌ی ۲).
    await createLedgerTables(db);
  }
  if (oldVersion < 14) {
    // نسخه ۱۴ (طرح ۹.۴ و ۱۲.۸): جدول‌های نسخه‌ی ۱ (با متنِ خامِ پیامک‌ها) پاک می‌شوند؛ فقط «دسته‌های هر
    // پیامک» (اثرانگشتِ محتوا ← دسته) برای پیش‌پرِ برگه‌ی ثبت می‌ماند (۹.۳).
    await _dropV1Tables(db);
  }
}

/// تنظیم‌های نسخه‌ی ۱ که دیگر خوانده نمی‌شوند.
const List<String> kV1SettingKeys = [
  'categorize_from',
  'pull_cursor',
  'last_sync',
  'dismissed_gaps',
  'dismissed_dups',
  'dismissed_transfers',
  'show_sms_text',
  'account_aliases',
  'kept_transactions',
  'repair_result',
  'auto_removed',
  'user_deleted',
  'health_reported',
  'inbox_watermark',
  'parser_version',
];

Future<bool> _hasTable(Database db, String table) async => (await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [table]))
    .isNotEmpty;

/// اثرانگشتِ محتوای پیامک (فرستنده + متنِ پاک‌شده، بی‌زمان) ← دسته‌ای که در نسخه‌ی ۱ خورده بود.
Future<void> _createLegacyCategoriesTable(Database db) => db.execute('''
      CREATE TABLE IF NOT EXISTS legacy_sms_categories (
        content_hash TEXT NOT NULL,
        category_id TEXT NOT NULL,
        PRIMARY KEY (content_hash, category_id)
      )
    ''');

Future<void> _dropV1Tables(Database db) async {
  await _createLegacyCategoriesTable(db);
  if (await _hasTable(db, 'transactions') && await _hasTable(db, 'transaction_categories')) {
    await db.execute('''
      INSERT OR IGNORE INTO legacy_sms_categories (content_hash, category_id)
      SELECT DISTINCT t.sms_content_hash, tc.category_id
      FROM transaction_categories tc JOIN transactions t ON t.id = tc.transaction_id
      WHERE t.sms_content_hash IS NOT NULL AND t.deleted_at IS NULL
    ''');
  }
  for (final t in const ['transaction_categories', 'outbox', 'transactions']) {
    await db.execute('DROP TABLE IF EXISTS $t');
  }
  if (await _hasTable(db, 'settings')) {
    await db.delete('settings',
        where: 'key IN (${List.filled(kV1SettingKeys.length, '?').join(',')})', whereArgs: kV1SettingKeys);
  }
}

/// بودجه‌ها: سقفِ خرجِ هر دسته (بر اساسِ نامِ دسته) + ستون‌های هم‌گام‌سازی.
Future<void> _createBudgetsTable(Database db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS budgets (
      id TEXT PRIMARY KEY,
      category_name TEXT NOT NULL,
      period TEXT NOT NULL DEFAULT 'monthly',
      limit_rial INTEGER NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT,
      client_updated_at TEXT,
      sync_status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL
    )
  ''');
}

/// ستون‌های هم‌گام‌سازی برای جدول wallets (idempotent).
Future<void> _addWalletSyncColumns(Database db) async {
  await _ensureColumn(db, 'wallets', 'is_deleted', 'INTEGER NOT NULL DEFAULT 0');
  await _ensureColumn(db, 'wallets', 'updated_at', 'TEXT');
  await _ensureColumn(db, 'wallets', 'client_updated_at', 'TEXT');
  // کیف‌های موجود هنوز روی سرور نیستند؛ 'pending' تا در اولین sync آپلود شوند.
  await _ensureColumn(db, 'wallets', 'sync_status', "TEXT NOT NULL DEFAULT 'pending'");
}

/// اگر ستون نبود، اضافه‌اش می‌کند (تا ALTER تکراری خطا ندهد). جدولی که نیست (مثلاً جدول‌های نسخه‌ی ۱ بعد از
/// نسخه‌ی ۱۴) نادیده گرفته می‌شود.
Future<void> _ensureColumn(Database db, String table, String col, String type) async {
  final cols = (await db.rawQuery('PRAGMA table_info($table)'))
      .map((r) => r['name'] as String)
      .toSet();
  if (cols.isEmpty) return;
  if (!cols.contains(col)) {
    await db.execute('ALTER TABLE $table ADD COLUMN $col $type');
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

/// ساخت جداول نسخه‌ی فعلی (نصبِ تازه). جدول‌های نسخه‌ی ۱ دیگر ساخته نمی‌شوند.
Future<void> createSchema(Database db) async {
  await _createCategoriesTable(db);
  await _seedCategories(db);
  await _createWalletsTable(db);
  await db.execute('ALTER TABLE wallets ADD COLUMN owner_user_id TEXT');
  await _addWalletSyncColumns(db);
  await _ensureColumn(db, 'wallets', 'archived', 'INTEGER NOT NULL DEFAULT 0');
  await _createBudgetsTable(db);
  await _createSettingsTable(db);
  await _createAllowedSendersTable(db);
  await createLedgerTables(db);
  await _createLegacyCategoriesTable(db);
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
      owner_name TEXT,
      owner_user_id TEXT,
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

/// دسته‌ها (نسخه‌ی ۲ هم همین را دارد؛ تخصیصِ تراکنش‌هایش در `ledger_entry_categories`).
Future<void> _createCategoriesTable(Database db) => db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        is_system INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

/// مهاجرتِ ۳ (نسخه‌ی ۱): دسته‌ها + تخصیص مبلغ هر تراکنش به چند دسته.
Future<void> _createCategoryTables(Database db) async {
  await _createCategoriesTable(db);
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
