import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/core/sync/remote_transaction_api.dart';
import 'package:economy/core/sync/sync_service.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/db_test_helper.dart';

/// API جعلی: نتیجه‌ی هر آیتم قابل‌تنظیم؛ می‌تواند خطای شبکه شبیه‌سازی کند.
class FakeRemoteTransactionApi implements RemoteTransactionApi {
  final List<List<Map<String, dynamic>>> sentBatches = [];
  bool throwNetwork;
  String status;

  FakeRemoteTransactionApi({this.throwNetwork = false, this.status = 'created'});

  @override
  Future<List<Map<String, dynamic>>> syncBatch({
    required String deviceId,
    required List<Map<String, dynamic>> transactions,
  }) async {
    sentBatches.add(transactions);
    if (throwNetwork) throw Exception('network down');
    return [
      for (final t in transactions) {'id': t['id'], 'status': status},
    ];
  }
}

void main() {
  const parser = SmsParser();
  final fixedClock = DateTime.utc(2026, 1, 1, 12, 0, 0);

  late Database db;
  late TransactionRepository repo;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = TransactionRepository(db);
  });

  tearDown(() async => db.close());

  Future<int> outboxCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  Future<int> syncedCount() async =>
      Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM transactions WHERE sync_status = 'synced'",
      )) ??
      0;

  Future<void> seedTwo() async {
    await repo.saveParsed(
      parser.parse(sender: 'ملی', body: 'واریز مبلغ 10,000,000 ریال'),
      sender: 'ملی',
    );
    await repo.saveParsed(
      parser.parse(sender: 'BankMellat', body: 'خرید مبلغ 3,000,000 ریال از کارت 1234'),
      sender: 'BankMellat',
    );
  }

  test('ذخیره‌ی تراکنش معتبر آن را به outbox صف می‌کند', () async {
    await seedTwo();
    expect(await outboxCount(), 2);
  });

  test('تراکنش با نوع نامشخص به outbox نمی‌رود', () async {
    await repo.saveParsed(
      parser.parse(sender: 'BankMellat', body: 'سلام دوست عزیز'),
      sender: 'BankMellat',
    );
    expect(await outboxCount(), 0);
    expect(
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM transactions')),
      1,
    );
  });

  test('created → همه synced و outbox خالی می‌شود', () async {
    await seedTwo();
    final api = FakeRemoteTransactionApi(status: 'created');
    final service = SyncService(db: db, api: api, deviceId: 'd', clock: () => fixedClock);

    final summary = await service.sync();

    expect(summary.synced, 2);
    expect(summary.failed, 0);
    expect(await outboxCount(), 0);
    expect(await syncedCount(), 2);
  });

  test('already_exists هم synced محسوب می‌شود', () async {
    await seedTwo();
    final api = FakeRemoteTransactionApi(status: 'already_exists');
    final service = SyncService(db: db, api: api, deviceId: 'd', clock: () => fixedClock);

    final summary = await service.sync();
    expect(summary.synced, 2);
    expect(await outboxCount(), 0);
  });

  test('sync دوباره چیزی نمی‌فرستد (idempotent — «۲ نه ۴»)', () async {
    await seedTwo();
    final api = FakeRemoteTransactionApi(status: 'created');
    final service = SyncService(db: db, api: api, deviceId: 'd', clock: () => fixedClock);

    await service.sync();
    await service.sync(); // بار دوم نباید چیزی بفرستد

    expect(api.sentBatches.length, 1); // فقط یک دسته در کل ارسال شد
    expect(await outboxCount(), 0);
  });

  test('خطای شبکه → آیتم‌ها گم نمی‌شوند و با backoff زمان‌بندی می‌شوند', () async {
    await seedTwo();
    final api = FakeRemoteTransactionApi(throwNetwork: true);
    final service = SyncService(db: db, api: api, deviceId: 'd', clock: () => fixedClock);

    final summary = await service.sync();

    expect(summary.failed, 2);
    expect(await outboxCount(), 2); // هنوز در صف
    final rows = await db.query('outbox');
    expect(rows.every((r) => (r['retry_count'] as int) == 1), isTrue);
    expect(rows.every((r) => r['next_retry_at'] != null), isTrue);

    // اجرای دوباره در همان لحظه چیزی نمی‌فرستد (backoff هنوز نگذشته)
    await service.sync();
    expect(api.sentBatches.length, 1);
  });

  test('error سرور → آیتم برای retry می‌ماند و تراکنش failed می‌شود', () async {
    await seedTwo();
    final api = FakeRemoteTransactionApi(status: 'error');
    final service = SyncService(db: db, api: api, deviceId: 'd', clock: () => fixedClock);

    final summary = await service.sync();
    expect(summary.failed, 2);
    expect(await outboxCount(), 2);
    expect(
      Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM transactions WHERE sync_status = 'failed'",
      )),
      2,
    );
  });
}
