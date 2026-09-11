import 'dart:convert';

import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/core/sync/remote_transaction_api.dart';
import 'package:economy/core/sync/sync_service.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/db_test_helper.dart';

/// سرور جعلیِ باحالت: idهای ساخته‌شده را به‌خاطر می‌سپارد و برای تکراری‌ها
/// already_exists برمی‌گرداند — دقیقاً مثل idempotency واقعی سرور.
class StatefulFakeServer implements RemoteTransactionApi {
  final Set<String> _created = {};
  final Set<String> errorIds;
  bool online;
  int callCount = 0;

  StatefulFakeServer({this.online = true, this.errorIds = const {}});

  int get distinctCreated => _created.length;

  @override
  Future<List<Map<String, dynamic>>> syncBatch({
    required String deviceId,
    required List<Map<String, dynamic>> transactions,
  }) async {
    callCount++;
    if (!online) throw Exception('network down');
    final results = <Map<String, dynamic>>[];
    for (final t in transactions) {
      final id = t['id'].toString();
      if (errorIds.contains(id)) {
        results.add({'id': id, 'status': 'error', 'detail': 'invalid'});
      } else if (_created.contains(id)) {
        results.add({'id': id, 'status': 'already_exists'});
      } else {
        _created.add(id);
        results.add({'id': id, 'status': 'created'});
      }
    }
    return results;
  }

  @override
  Future<PullPage> pull({String? since, int limit = 500}) async {
    if (!online) throw Exception('network down');
    return PullPage.empty;
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

  Future<List<String>> saveN(int n) async {
    final ids = <String>[];
    for (var i = 1; i <= n; i++) {
      final outcome = await repo.saveParsed(
        parser.parse(
          sender: 'BankMellat',
          body: 'خرید مبلغ ${i}00000 ریال از کارت 1234',
        ),
        sender: 'BankMellat',
      );
      ids.add(outcome.id);
    }
    return ids;
  }

  Future<void> reenqueueAll() async {
    for (final t in await repo.getAll()) {
      await db.insert(
        'outbox',
        {
          'transaction_id': t.id,
          'payload': jsonEncode(t.toSyncPayload()),
          'status': 'pending',
          'retry_count': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  test('پاسخِ گم‌شده: sync قطع‌شده تراکنش تکراری نمی‌سازد', () async {
    await saveN(1);
    final server = StatefulFakeServer();

    // شبیه‌سازی: سرور تراکنش را ساخت ولی پاسخ قبل از رسیدن گم شد (اپ کرش کرد
    // پیش از markSynced) → پس outbox هنوز pending است.
    final payload = (await repo.getAll()).first.toSyncPayload();
    await server.syncBatch(deviceId: 'd', transactions: [payload]);
    expect(server.distinctCreated, 1);
    expect(await outboxCount(), 1);

    // راه‌اندازی مجدد → sync دوباره تلاش می‌کند
    final service = SyncService(db: db, api: server, deviceId: 'd', clock: () => fixedClock);
    final summary = await service.sync();

    expect(summary.synced, 1);
    expect(server.distinctCreated, 1); // نه ۲
    expect(await outboxCount(), 0);
  });

  test('«۱۰ نه ۲۰»: ارسال دوباره پس از کرش، رکورد تکراری نمی‌سازد', () async {
    await saveN(10);
    final server = StatefulFakeServer();
    final service = SyncService(db: db, api: server, deviceId: 'd', clock: () => fixedClock);

    await service.sync();
    expect(server.distinctCreated, 10);
    expect(await outboxCount(), 0);

    // شبیه‌سازی کرش که همان ۱۰ تراکنش را دوباره به صف انداخت
    await reenqueueAll();
    expect(await outboxCount(), 10);

    final summary = await service.sync();
    expect(summary.synced, 10);
    expect(server.distinctCreated, 10); // هنوز دقیقاً ۱۰، نه ۲۰
    expect(await outboxCount(), 0);
  });

  test('batch نیمه‌موفق: موفق‌ها synced، خطادار در صف می‌ماند', () async {
    final ids = await saveN(3);
    final server = StatefulFakeServer(errorIds: {ids[1]});
    final service = SyncService(db: db, api: server, deviceId: 'd', clock: () => fixedClock);

    final summary = await service.sync();

    expect(summary.synced, 2);
    expect(summary.failed, 1);
    expect(server.distinctCreated, 2);
    final rows = await db.query('outbox');
    expect(rows, hasLength(1));
    expect(rows.single['transaction_id'], ids[1]);
  });

  test('بازیابی پس از قطع شبکه: بعد از برگشت اینترنت همه می‌روند', () async {
    var now = DateTime.utc(2026, 1, 1, 12, 0, 0);
    final server = StatefulFakeServer(online: false);
    final service = SyncService(db: db, api: server, deviceId: 'd', clock: () => now);

    await saveN(2);
    final s1 = await service.sync(); // شبکه قطع است
    expect(s1.failed, 2);
    expect(await outboxCount(), 2); // گم نشده

    // زمان جلو می‌رود (از backoff عبور می‌کند) و شبکه برمی‌گردد
    now = now.add(const Duration(minutes: 5));
    server.online = true;
    final s2 = await service.sync();

    expect(s2.synced, 2);
    expect(server.distinctCreated, 2);
    expect(await outboxCount(), 0);
  });
}
