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
  final Map<String, Map<String, dynamic>> resultOverrides = {};
  final List<PullPage> pages = [];
  final List<String?> pullSinces = [];

  FakeRemoteTransactionApi({this.throwNetwork = false, this.status = 'created'});

  @override
  Future<List<Map<String, dynamic>>> syncBatch({
    required String deviceId,
    required List<Map<String, dynamic>> transactions,
  }) async {
    sentBatches.add(transactions);
    if (throwNetwork) throw Exception('network down');
    return [
      for (final t in transactions)
        resultOverrides[t['id']] ?? {'id': t['id'], 'status': status},
    ];
  }

  @override
  Future<PullPage> pull({String? since, int limit = 500}) async {
    pullSinces.add(since);
    if (throwNetwork) throw Exception('network down');
    return pages.isEmpty ? PullPage.empty : pages.removeAt(0);
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

  SyncService serviceWith(RemoteTransactionApi api) =>
      SyncService(db: db, api: api, deviceId: 'd', clock: () => fixedClock);

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
    final summary = await serviceWith(FakeRemoteTransactionApi()).sync();

    expect(summary.synced, 2);
    expect(summary.failed, 0);
    expect(await outboxCount(), 0);
    expect(await syncedCount(), 2);
  });

  test('already_exists هم synced محسوب می‌شود', () async {
    await seedTwo();
    final api = FakeRemoteTransactionApi(status: 'already_exists');
    final summary = await serviceWith(api).sync();
    expect(summary.synced, 2);
    expect(await outboxCount(), 0);
  });

  test('sync دوباره چیزی نمی‌فرستد (idempotent — «۲ نه ۴»)', () async {
    await seedTwo();
    final api = FakeRemoteTransactionApi();
    final service = serviceWith(api);

    await service.sync();
    await service.sync(); // بار دوم نباید چیزی بفرستد

    expect(api.sentBatches.length, 1); // فقط یک دسته در کل ارسال شد
    expect(await outboxCount(), 0);
  });

  test('خطای شبکه → آیتم‌ها گم نمی‌شوند و با backoff زمان‌بندی می‌شوند', () async {
    await seedTwo();
    final api = FakeRemoteTransactionApi(throwNetwork: true);
    final service = serviceWith(api);

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
    final summary = await serviceWith(FakeRemoteTransactionApi(status: 'error')).sync();
    expect(summary.failed, 2);
    expect(await outboxCount(), 2);
    expect(
      Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM transactions WHERE sync_status = 'failed'",
      )),
      2,
    );
  });

  test('payload از آخرین نسخه ساخته می‌شود و فیلد متنی null ندارد', () async {
    await seedTwo();
    final api = FakeRemoteTransactionApi();
    await serviceWith(api).sync();
    final sent = api.sentBatches.single;
    expect(sent, hasLength(2));
    for (final p in sent) {
      expect(p['counterparty'], isA<String>());
      expect(p['raw_amount'], isA<String>());
      expect(p['client_updated_at'], isNotNull);
    }
  });

  test('ویرایش بعد از sync دوباره ارسال می‌شود', () async {
    await seedTwo();
    final api = FakeRemoteTransactionApi();
    final service = serviceWith(api);
    await service.sync();

    final id = (await repo.getAll()).first.id;
    await repo.updateTransaction(id, description: 'نان');
    expect(await outboxCount(), 1);

    await service.sync();
    expect(api.sentBatches, hasLength(2));
    expect(api.sentBatches.last.single['description'], 'نان');
  });

  test('دریافت: تراکنش عضو دیگر اعمال و cursor نگه داشته می‌شود', () async {
    await repo.setSetting(SettingKeys.meUserId, 'u-me');
    final api = FakeRemoteTransactionApi()
      ..pages.add(PullPage(
        results: [
          {
            'id': 'r1',
            'kind': 'expense',
            'amount_rial': 5000,
            'owner': 'u-father',
            'owner_name': 'بابا',
            'captured_by': 'u-father',
            'is_deleted': false,
            'allocations': const [],
          },
        ],
        cursor: 'c1',
      ));
    final service = serviceWith(api);

    final s = await service.sync();
    expect(s.pulled, 1);
    expect((await repo.getById('r1'))!.ownerName, 'بابا');

    await service.sync();
    expect(api.pullSinces, [null, 'c1']);
  });

  test('تکراری با شناسه‌ی دیگر روی سرور → ردیف محلی یکی می‌شود', () async {
    await seedTwo();
    final ids = (await repo.getAll()).map((t) => t.id).toList();
    final api = FakeRemoteTransactionApi()
      ..resultOverrides[ids.first] = {'id': 'server-x', 'status': 'already_exists'};

    await serviceWith(api).sync();

    expect(await repo.getById('server-x'), isNotNull);
    expect(await repo.getById(ids.first), isNull);
    expect(await outboxCount(), 0);
  });

  test('همگام‌سازی دستی (force) منتظر backoff نمی‌ماند', () async {
    await seedTwo();
    final api = FakeRemoteTransactionApi(throwNetwork: true);
    final service = serviceWith(api);
    await service.sync();

    api.throwNetwork = false;
    await service.sync(); // هنوز در backoff
    expect(api.sentBatches, hasLength(1));

    final s = await service.sync(force: true);
    expect(s.synced, 2);
    expect(api.sentBatches, hasLength(2));
  });

  test('forbidden → از صف خارج و دریافت از اول انجام می‌شود', () async {
    await seedTwo();
    await repo.setSetting(SettingKeys.pullCursor, 'old-cursor');
    final api = FakeRemoteTransactionApi(status: 'forbidden');

    final s = await serviceWith(api).sync();

    expect(s.rejected, 2);
    expect(await outboxCount(), 0);
    expect(api.pullSinces, [null]);
  });

  test('وضعیت آخرین همگام‌سازی برای نمایش ذخیره می‌شود', () async {
    await seedTwo();
    final s = await serviceWith(FakeRemoteTransactionApi(throwNetwork: true)).sync();
    expect(s.offline, isTrue);
    expect(s.message, contains('سرور در دسترس نبود'));

    final info = await SyncStatusInfo.load(repo);
    expect(info.last!.offline, isTrue);
    expect(info.pendingCount, 2);
    expect(info.lastAt, fixedClock);
  });

  test('دو همگام‌سازی هم‌زمان فقط یک بار ارسال می‌کنند', () async {
    await seedTwo();
    final api = FakeRemoteTransactionApi();
    final service = serviceWith(api);
    await Future.wait([service.sync(), service.sync()]);
    expect(api.sentBatches, hasLength(1));
  });
}
