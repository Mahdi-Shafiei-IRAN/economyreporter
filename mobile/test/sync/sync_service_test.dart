import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/core/sync/remote_transaction_api.dart';
import 'package:economy/core/sync/sync_service.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/budgets/data/budget.dart';
import 'package:economy/features/wallets/data/wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/db_test_helper.dart';
import '../helpers/network_errors.dart';

/// API جعلی: نتیجه‌ی هر آیتم قابل‌تنظیم؛ می‌تواند خطای شبکه شبیه‌سازی کند.
class FakeRemoteTransactionApi implements RemoteTransactionApi {
  final List<List<Map<String, dynamic>>> sentBatches = [];
  bool throwNetwork;
  String status;
  final Map<String, Map<String, dynamic>> resultOverrides = {};
  final List<PullPage> pages = [];
  final List<String?> pullSinces = [];

  /// تراکنشی که سرور با آن کلِ درخواست را با ۵۰۰ رد می‌کند.
  String? poisonId;

  /// خطایی که دریافت (pull) می‌دهد.
  Object? pullError;

  FakeRemoteTransactionApi({this.throwNetwork = false, this.status = 'created'});

  @override
  Future<List<Map<String, dynamic>>> syncBatch({
    required String deviceId,
    required List<Map<String, dynamic>> transactions,
  }) async {
    sentBatches.add(transactions);
    if (throwNetwork) throw networkDown();
    if (transactions.any((t) => t['id'] == poisonId)) {
      throw httpError(500, '<h1>Server Error (500)</h1>');
    }
    return [
      for (final t in transactions)
        resultOverrides[t['id']] ?? {'id': t['id'], 'status': status},
    ];
  }

  @override
  Future<PullPage> pull({String? since, int limit = 500}) async {
    pullSinces.add(since);
    if (throwNetwork) throw networkDown();
    if (pullError != null) throw pullError!;
    return pages.isEmpty ? PullPage.empty : pages.removeAt(0);
  }

  final List<List<Map<String, dynamic>>> sentWallets = [];
  final List<PullPage> walletPages = [];

  /// پاسخِ دلخواه به آپلودِ کیف‌ها (برای شبیه‌سازیِ سرورِ قدیمی/خطای آیتم).
  Future<List<Map<String, dynamic>>> Function(List<Map<String, dynamic>>)? walletResponder;

  @override
  Future<List<Map<String, dynamic>>> syncWallets(
      {required List<Map<String, dynamic>> wallets}) async {
    if (throwNetwork) throw networkDown();
    sentWallets.add(wallets);
    final r = walletResponder;
    if (r != null) return r(wallets);
    return [for (final w in wallets) {'id': w['id'], 'status': 'created'}];
  }

  @override
  Future<PullPage> pullWallets({String? since}) async {
    if (throwNetwork) throw networkDown();
    return walletPages.isEmpty ? PullPage.empty : walletPages.removeAt(0);
  }

  final List<List<Map<String, dynamic>>> sentBudgets = [];
  final List<PullPage> budgetPages = [];

  @override
  Future<List<Map<String, dynamic>>> syncBudgets(
      {required List<Map<String, dynamic>> budgets}) async {
    if (throwNetwork) throw networkDown();
    sentBudgets.add(budgets);
    return [for (final b in budgets) {'id': b['id'], 'status': 'created'}];
  }

  @override
  Future<PullPage> pullBudgets({String? since}) async {
    if (throwNetwork) throw networkDown();
    return budgetPages.isEmpty ? PullPage.empty : budgetPages.removeAt(0);
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
      ..pages.add(const PullPage(
        results: [
          {
            'id': 'r1',
            'kind': 'expense',
            'amount_rial': 5000,
            'owner': 'u-father',
            'owner_name': 'بابا',
            'captured_by': 'u-father',
            'is_deleted': false,
            'allocations': [],
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

  test('کیف‌ها هم‌گام می‌شوند: pending آپلود و کیفِ سرور محلی می‌شود', () async {
    await repo.addWallet(const Wallet(
        id: '', ownerName: 'من', label: 'کارت حقوق', bankId: 'mellat', cardLast4: '1234'));
    final api = FakeRemoteTransactionApi()
      ..walletPages.add(const PullPage(results: [
        {
          'id': 'srv-1',
          'owner_user_id': 'u-father',
          'owner_name': 'بابا',
          'label': 'کارت بابا',
          'bank_id': 'melli',
          'card_last4': '5678',
          'account_ref': '',
          'is_deleted': false,
          'updated_at': '2026-09-10T08:00:00Z',
        },
      ]));

    await serviceWith(api).sync();

    // کیفِ محلی آپلود شد
    expect(api.sentWallets.single.single['label'], 'کارت حقوق');
    // دیگر pending نمانده
    expect(await repo.pendingWallets(), isEmpty);
    // کیفِ سرور در محلی درج شد
    final labels = (await repo.wallets()).map((w) => w.label).toSet();
    expect(labels, containsAll(['کارت حقوق', 'کارت بابا']));
  });

  test('کیفِ حذف‌شده‌ی سرور از محلی پاک می‌شود', () async {
    final api = FakeRemoteTransactionApi()
      ..walletPages.add(const PullPage(results: [
        {
          'id': 'srv-2',
          'owner_name': 'بابا',
          'label': 'کارت حذفی',
          'is_deleted': true,
          'updated_at': '2026-09-10T08:00:00Z',
        },
      ]));
    await serviceWith(api).sync();
    expect((await repo.wallets()).where((w) => w.id == 'srv-2'), isEmpty);
  });

  test('بودجه‌ها هم‌گام می‌شوند: pending آپلود و بودجه‌ی سرور محلی می‌شود', () async {
    await repo.addBudget(const Budget(id: '', categoryName: 'میوه', limitRial: 500000));
    final api = FakeRemoteTransactionApi()
      ..budgetPages.add(const PullPage(results: [
        {
          'id': 'srv-b1',
          'category_name': 'قبوض',
          'period': 'monthly',
          'limit_rial': 800000,
          'is_deleted': false,
          'updated_at': '2026-09-10T08:00:00Z',
        },
      ]));

    await serviceWith(api).sync();

    expect(api.sentBudgets.single.single['category_name'], 'میوه');
    expect(await repo.pendingBudgets(), isEmpty);
    final names = (await repo.budgets()).map((b) => b.categoryName).toSet();
    expect(names, containsAll(['میوه', 'قبوض']));
  });

  test('عضوِ عادی: تراکنشِ بقیه از سرور اعمال نمی‌شود (حریم مدیر)', () async {
    await repo.setSetting(SettingKeys.meUserId, 'u-me');
    await repo.setSetting(SettingKeys.myRole, 'member');
    final api = FakeRemoteTransactionApi()
      ..pages.add(const PullPage(
        results: [
          {
            'id': 'mine',
            'kind': 'income',
            'amount_rial': 1000,
            'owner': 'u-me',
            'captured_by': 'u-me',
            'is_deleted': false,
            'allocations': [],
          },
          {
            'id': 'managers',
            'kind': 'expense',
            'amount_rial': 9000,
            'owner': 'u-father',
            'captured_by': 'u-father',
            'is_deleted': false,
            'allocations': [],
          },
        ],
        cursor: 'c1',
      ));

    await serviceWith(api).sync();

    expect(await repo.getById('mine'), isNotNull);
    expect(await repo.getById('managers'), isNull); // مالِ مدیر نباید بیاید
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
    expect(s.message, contains('به سرور وصل نشد'));

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

  group('خطاها دقیق و ایزوله', () {
    test('یک تراکنشِ خراب (۵۰۰) بقیه را گیر نمی‌اندازد', () async {
      await seedTwo();
      final bad = (await repo.getAll()).first.id;
      final api = FakeRemoteTransactionApi()..poisonId = bad;
      final s = await serviceWith(api).sync(force: true);

      expect(s.synced, 1);
      expect(s.failed, 1);
      expect(s.offline, isFalse);
      expect(s.error, 'http');
      expect(s.failure!.status, 500);
      expect(s.message, contains('خطای ۵۰۰'));
      expect(s.message, contains('ارسال تراکنش‌ها'));
      expect(await outboxCount(), 1); // فقط خودش در صف ماند
    });

    test('خطای سرور در دریافت «شبکه» نیست و مرحله‌ی کارت‌ها باز هم انجام می‌شود', () async {
      await repo.addWallet(const Wallet(id: '', ownerName: 'من', label: 'ملت', bankId: 'mellat'));
      final api = FakeRemoteTransactionApi()..pullError = httpError(502, 'Bad Gateway');
      final s = await serviceWith(api).sync(force: true);

      expect(s.offline, isFalse);
      expect(s.failure!.stage, 'pull');
      expect(s.failure!.status, 502);
      expect(s.message, contains('دریافت تراکنش‌ها'));
      expect(api.sentWallets, hasLength(1));
      expect(await repo.pendingWallets(), isEmpty);
    });

    test('باگِ برنامه «خطای برنامه» گزارش می‌شود، نه «وصل نشد»', () async {
      final api = FakeRemoteTransactionApi()..pullError = const FormatException('bad json');
      final s = await serviceWith(api).sync(force: true);
      expect(s.error, 'app');
      expect(s.message, contains('خطای برنامه'));
      expect(s.message, isNot(contains('وصل نشد')));
    });

    test('سرورِ قدیمی: کارتِ مالِ خانواده‌ی دیگر (۴۰۴) شناسه‌ی تازه می‌گیرد و بقیه می‌روند',
        () async {
      await repo.addWallet(const Wallet(id: '', ownerName: 'من', label: 'قدیمی', bankId: 'mellat'));
      await repo.addWallet(const Wallet(id: '', ownerName: 'من', label: 'تازه', bankId: 'tejarat'));
      final old = (await repo.wallets()).firstWhere((w) => w.label == 'قدیمی').id;
      final api = FakeRemoteTransactionApi()
        ..walletResponder = (items) async {
          if (items.any((w) => w['id'] == old)) throw httpError(404, {'detail': 'Not found.'});
          return [for (final w in items) {...w}]; // سرورِ قدیمی: خودِ کیف، بی‌status
        };
      final s = await serviceWith(api).sync(force: true);

      expect(s.error, isNull);
      final wallets = await repo.wallets();
      expect(wallets.map((w) => w.id), isNot(contains(old)));
      // کیفِ «قدیمی» با شناسه‌ی تازه pending ماند تا دفعه‌ی بعد برود؛ «تازه» رفت.
      final pending = await repo.pendingWallets();
      expect(pending.single['label'], 'قدیمی');

      await serviceWith(api).sync(force: true);
      expect(await repo.pendingWallets(), isEmpty);
    });

    test('کارتِ نامعتبر (خطای آیتم) «ناموفق» می‌شود و همگام‌سازی را قفل نمی‌کند', () async {
      await repo.addWallet(const Wallet(id: '', ownerName: 'من', label: 'بد', bankId: 'mellat'));
      await repo.addWallet(const Wallet(id: '', ownerName: 'من', label: 'خوب', bankId: 'tejarat'));
      final api = FakeRemoteTransactionApi()
        ..walletResponder = (items) async => [
              for (final w in items)
                w['label'] == 'بد'
                    ? {'id': w['id'], 'status': 'error', 'detail': {'label': ['too long']}}
                    : {'id': w['id'], 'status': 'created'},
            ];
      final s = await serviceWith(api).sync(force: true);
      expect(s.failure!.stage, 'wallets');
      expect(s.message, contains('کارت‌ها'));
      expect(await repo.pendingWallets(), isEmpty);

      // دفعه‌ی بعد دیگر همان کیفِ بد فرستاده نمی‌شود و خطایی نیست.
      final again = await serviceWith(api).sync(force: true);
      expect(again.error, isNull);
    });
  });
}
