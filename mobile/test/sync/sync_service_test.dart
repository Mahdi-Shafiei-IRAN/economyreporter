/// همگام‌سازیِ کیف‌ها (حساب‌ها) و بودجه‌ها — تنها چیزی که بعد از فاز ۵ غیر از دفتر به سرور می‌رود.
library;

import 'package:dio/dio.dart';
import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/store/app_store.dart';
import 'package:economy/core/sync/remote_sync_api.dart';
import 'package:economy/core/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

class _FakeRemote implements RemoteSyncApi {
  final List<Map<String, dynamic>> sentWallets = [];
  final List<Map<String, dynamic>> sentBudgets = [];
  List<Map<String, dynamic>> serverWallets = [];
  List<Map<String, dynamic>> serverBudgets = [];
  final List<String?> walletSince = [];

  /// شناسه‌هایی که روی سرور مالِ خانواده‌ی دیگری است.
  Set<String> conflicts = {};

  /// شناسه‌هایی که سرور با `error` رد می‌کند.
  Set<String> bad = {};
  bool offline = false;

  /// سرورِ قدیمی: یک آیتمِ خراب کلِ درخواست را با ۴۰۰ رد می‌کند.
  bool oldServer = false;

  void _check() {
    if (offline) {
      throw DioException(requestOptions: RequestOptions(path: '/'), type: DioExceptionType.connectionError);
    }
  }

  List<Map<String, dynamic>> _results(List<Map<String, dynamic>> items, List<Map<String, dynamic>> log) {
    if (oldServer && items.length > 1 && items.any((i) => bad.contains(i['id']))) {
      throw DioException(
        requestOptions: RequestOptions(path: '/'),
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: RequestOptions(path: '/'), statusCode: 400, data: {'detail': 'bad'}),
      );
    }
    log.addAll(items);
    return [
      for (final i in items)
        {
          'id': i['id'],
          'status': conflicts.contains(i['id'])
              ? 'conflict'
              : bad.contains(i['id'])
                  ? 'error'
                  : 'created',
          if (bad.contains(i['id'])) 'detail': 'label: نامعتبر',
        },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> syncWallets({required List<Map<String, dynamic>> wallets}) async {
    _check();
    return _results(wallets, sentWallets);
  }

  @override
  Future<PullPage> pullWallets({String? since}) async {
    _check();
    walletSince.add(since);
    return PullPage(results: serverWallets, cursor: serverWallets.isEmpty ? since : 'w-cursor');
  }

  @override
  Future<List<Map<String, dynamic>>> syncBudgets({required List<Map<String, dynamic>> budgets}) async {
    _check();
    return _results(budgets, sentBudgets);
  }

  @override
  Future<PullPage> pullBudgets({String? since}) async {
    _check();
    return PullPage(results: serverBudgets, cursor: serverBudgets.isEmpty ? since : 'b-cursor');
  }
}

void main() {
  final now = DateTime.utc(2026, 9, 24, 10);
  late Database db;
  late AppStore store;
  late LedgerRepository ledger;
  late _FakeRemote remote;
  late SyncService sync;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    store = AppStore(db, clock: () => now);
    ledger = LedgerRepository(db, deviceId: 'dev', clock: () => now);
    remote = _FakeRemote();
    sync = SyncService(store: store, api: remote);
  });

  tearDown(() => db.close());

  Future<Map<String, Object?>?> walletRow(String id) async =>
      (await db.query('wallets', where: 'id = ?', whereArgs: [id])).firstOrNull;

  test('a new account is sent once, marked synced; family wallets and budgets come back', () async {
    final a = await ledger.createAccount(ownerName: 'مهدی', label: 'ملت', bankId: 'mellat', accountRef: '1000005596');
    await ledger.setBudget('نان', 5000000);
    remote.serverWallets = [
      {'id': 'z1', 'owner_user_id': 'u2', 'owner_name': 'زهرا', 'label': 'سامان', 'bank_id': 'saman', 'archived': false},
    ];
    remote.serverBudgets = [
      {'id': 'b9', 'category_name': 'قبوض', 'period': 'monthly', 'limit_rial': 900000},
    ];

    final r = await sync.sync();
    expect(r.failure, isNull);
    expect(remote.sentWallets.single['id'], a.id);
    expect(remote.sentWallets.single['label'], 'ملت');
    expect(remote.sentBudgets.single['category_name'], 'نان');
    expect((await walletRow(a.id))!['sync_status'], 'synced');
    expect((await walletRow('z1'))!['owner_name'], 'زهرا');
    expect((await ledger.budgets()).map((b) => b.categoryName), containsAll(['نان', 'قبوض']));
    expect(await store.getSetting(SettingKeys.walletCursor), 'w-cursor');

    remote.sentWallets.clear();
    await sync.sync();
    expect(remote.sentWallets, isEmpty); // چیزی دوباره فرستاده نمی‌شود
    expect(remote.walletSince.last, 'w-cursor');
  });

  test('archiving on this phone survives a server copy that is older', () async {
    final a = await ledger.createAccount(ownerName: 'مهدی', label: 'ملت');
    await sync.sync();
    await ledger.setArchived(a.id, true);
    remote.serverWallets = [
      {'id': a.id, 'owner_name': 'مهدی', 'label': 'ملت', 'archived': false},
    ];
    // ویرایشِ محلیِ ارسال‌نشده با نسخه‌ی سرور خراب نمی‌شود.
    await store.applyRemoteWallet(remote.serverWallets.single);
    expect((await walletRow(a.id))!['archived'], 1);
    await sync.sync();
    expect(remote.sentWallets.last['archived'], isTrue);
  });

  test("an id that belongs to another family gets a new one; the account's ledger moves with it", () async {
    final a = await ledger.createAccount(ownerName: 'مهدی', label: 'ملت');
    final e = await ledger.addEntry(
        accountId: a.id, kind: EntryKind.expense, amountRial: 1000, occurredAt: now);
    await ledger.addCheckpoint(accountId: a.id, balanceRial: 5000, at: now);
    await ledger.markEntrySent(e);
    remote.conflicts = {a.id};

    await sync.sync();
    final rows = await db.query('wallets');
    expect(rows.single['id'], isNot(a.id));
    final newId = rows.single['id'] as String;
    expect(rows.single['sync_status'], 'pending');
    expect((await ledger.entries()).single.accountId, newId);
    expect((await ledger.checkpoints()).single.accountId, newId);
    expect(await ledger.pendingEntries(), hasLength(1)); // دوباره با حسابِ تازه فرستاده می‌شود

    remote.conflicts = {};
    await sync.sync();
    expect((await walletRow(newId))!['sync_status'], 'synced');
  });

  test('one bad account does not block the others (new and old server)', () async {
    for (final old in [false, true]) {
      await db.delete('wallets');
      remote
        ..oldServer = old
        ..sentWallets.clear();
      final good = await ledger.createAccount(ownerName: 'مهدی', label: 'ملت');
      final broken = await ledger.createAccount(ownerName: 'مهدی', label: 'x');
      remote.bad = {broken.id};

      final r = await sync.sync();
      expect(r.failure?.stage, 'wallets', reason: 'old=$old');
      expect((await walletRow(good.id))!['sync_status'], 'synced', reason: 'old=$old');
      expect((await walletRow(broken.id))!['sync_status'], 'failed', reason: 'old=$old');
    }
  });

  test('offline: nothing lost, reported as network', () async {
    final a = await ledger.createAccount(ownerName: 'مهدی', label: 'ملت');
    remote.offline = true;
    final r = await sync.sync();
    expect(r.offline, isTrue);
    expect((await walletRow(a.id))!['sync_status'], 'pending');

    remote.offline = false;
    expect((await sync.sync()).failure, isNull);
    expect((await walletRow(a.id))!['sync_status'], 'synced');
  });

  test('v1 transactions are no longer sent or pulled', () async {
    await db.insert('transactions', {
      'id': 'old-v1',
      'kind': 'expense',
      'amount_rial': 1000,
      'source': 'sms',
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'sync_status': 'pending',
    });
    await db.insert('outbox', {'transaction_id': 'old-v1', 'payload': '{}', 'status': 'pending', 'retry_count': 0});
    final r = await sync.sync();
    expect(r.failure, isNull);
    expect(remote.sentWallets, isEmpty);
    expect(remote.sentBudgets, isEmpty);
  });
}
