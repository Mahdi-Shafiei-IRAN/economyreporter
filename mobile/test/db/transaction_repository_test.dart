import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/sms/models.dart';
import 'package:economy/core/sms/sms_fingerprint.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/wallets/data/wallet.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_test_helper.dart';

void main() {
  const parser = SmsParser();

  late Database db;
  late TransactionRepository repo;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = TransactionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('اسکیما ساخته می‌شود و جدول‌ها وجود دارند', () async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final names = tables.map((e) => e['name'] as String).toSet();
    expect(names, containsAll(['transactions', 'outbox']));
  });

  test('ذخیره‌ی خروجی پارسر و بازخوانی', () async {
    final parsed = parser.parse(
      sender: 'BankMellat',
      body: 'برداشت مبلغ 2,500,000 ریال از کارت 1234 مانده 43,000,000 ریال',
    );
    final outcome = await repo.saveParsed(parsed, sender: 'BankMellat');

    expect(outcome.isCreated, isTrue);
    expect(await repo.count(), 1);

    final all = await repo.getAll();
    expect(all, hasLength(1));
    final rec = all.first;
    expect(rec.bankId, 'mellat');
    expect(rec.kind, 'expense');
    expect(rec.amountRial, 2500000);
    expect(rec.balanceAfterRial, 43000000);
    expect(rec.cardLast4, '1234');
    expect(rec.needsReview, isFalse);
    expect(rec.syncStatus, 'pending');
  });

  test('ضدتکرار: پیامک یکسان دوبار → فقط یک رکورد', () async {
    const sender = 'BankMellat';
    const body = 'برداشت مبلغ 500,000 ریال از کارت 1234';
    final at = DateTime.utc(2026, 9, 10, 12, 20);

    final first = await repo.saveParsed(parser.parse(sender: sender, body: body),
        sender: sender, receivedAt: at);
    final second = await repo.saveParsed(parser.parse(sender: sender, body: body),
        sender: sender, receivedAt: at);

    expect(first.isCreated, isTrue);
    expect(second.isDuplicate, isTrue);
    expect(second.id, first.id);
    expect(await repo.count(), 1);
  });

  test('summary: درآمد، هزینه و مانده درست محاسبه می‌شوند', () async {
    await repo.saveParsed(
      parser.parse(sender: 'ملی', body: 'واریز مبلغ 10,000,000 ریال به حساب شما'),
      sender: 'ملی',
    );
    await repo.saveParsed(
      parser.parse(sender: 'BankMellat', body: 'خرید مبلغ 3,000,000 ریال از کارت 1234'),
      sender: 'BankMellat',
    );
    await repo.saveParsed(
      parser.parse(sender: 'BankMellat', body: 'خرید مبلغ 1,000,000 ریال از کارت 1234'),
      sender: 'BankMellat',
    );

    final s = await repo.summary();
    expect(s.incomeRial, 10000000);
    expect(s.expenseRial, 4000000);
    expect(s.balanceRial, 6000000);
  });

  test('summary: transfer در جمع درآمد/هزینه شمرده نمی‌شود', () async {
    await repo.saveParsed(
      parser.parse(sender: 'ملی', body: 'واریز مبلغ 5,000,000 ریال'),
      sender: 'ملی',
    );
    await repo.saveParsed(
      parser.parse(
          sender: 'BankMellat',
          body: 'انتقال کارت به کارت مبلغ 2,000,000 ریال از کارت 1234'),
      sender: 'BankMellat',
    );

    final s = await repo.summary();
    expect(s.incomeRial, 5000000);
    expect(s.expenseRial, 0);
    expect(await repo.count(), 2); // هر دو ذخیره می‌شوند، ولی transfer در جمع نیست
  });

  test('درج مستقیم رکورد دستی', () async {
    final now = DateTime.utc(2026, 9, 10);
    await repo.insert(TransactionRecord(
      id: 'manual-1',
      kind: 'expense',
      amountRial: 750000,
      source: 'manual',
      createdAt: now,
      updatedAt: now,
      clientCreatedAt: now,
    ));
    final s = await repo.summary();
    expect(s.expenseRial, 750000);
    expect(await repo.count(), 1);
  });

  Future<int> outboxCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  test('needsReviewCount و فیلترهای getAll', () async {
    // یک تراکنش نیازمند بازبینی (بانک ناشناخته) و یک عادی
    await repo.saveParsed(
      parser.parse(sender: 'Digikala', body: 'خرید ناموفق مبلغ 100,000 ریال'),
      sender: 'Digikala',
    );
    await repo.saveParsed(
      parser.parse(sender: 'ملی', body: 'واریز مبلغ 5,000,000 ریال'),
      sender: 'ملی',
    );

    expect(await repo.needsReviewCount(), 1);
    expect((await repo.getAll(needsReview: true)), hasLength(1));
    expect((await repo.getAll(kind: 'income')), hasLength(1));
    expect((await repo.getAll(kind: 'expense')), hasLength(1));
  });

  test('updateTransaction فیلدها را تغییر و بازبینی را پاک می‌کند', () async {
    final outcome = await repo.saveParsed(
      parser.parse(sender: 'Digikala', body: 'خرید ناموفق مبلغ 100,000 ریال'),
      sender: 'Digikala',
    );
    expect(await repo.needsReviewCount(), 1);

    await repo.updateTransaction(
      outcome.id,
      counterparty: 'دیجی‌کالا',
      needsReview: false,
    );

    final rec = (await repo.getAll()).first;
    expect(rec.counterparty, 'دیجی‌کالا');
    expect(rec.needsReview, isFalse);
    expect(await repo.needsReviewCount(), 0);
  });

  test('update نوع نامشخص به معتبر → به outbox صف می‌شود', () async {
    // پیامک نامرتبط → نوع unknown → به outbox نمی‌رود
    final outcome = await repo.saveParsed(
      parser.parse(sender: 'BankMellat', body: 'سلام دوست عزیز'),
      sender: 'BankMellat',
    );
    expect(await outboxCount(), 0);

    // کاربر در بازبینی نوع را تعیین می‌کند
    await repo.updateTransaction(outcome.id, kind: 'expense', amountRial: 50000);
    expect(await outboxCount(), 1);
  });

  test('deleteTransaction حذف نرم است و حذف را برای sync صف می‌کند', () async {
    final outcome = await repo.saveParsed(
      parser.parse(sender: 'ملی', body: 'واریز مبلغ 5,000,000 ریال'),
      sender: 'ملی',
    );
    expect(await repo.count(), 1);

    await repo.deleteTransaction(outcome.id);
    expect(await repo.count(), 0);
    expect(await repo.getAll(), isEmpty);
    expect((await repo.summary()).incomeRial, 0);
    // حذف باید به سرور هم برسد تا گوشی‌های دیگر نشانش ندهند
    expect(await outboxCount(), 1);
    final rec = await repo.getById(outcome.id);
    expect(rec!.toSyncPayload()['is_deleted'], isTrue);
  });

  group('ذخیره‌ی پیامک و ضدتکرار', () {
    const sender = 'BankMellat';
    const body = 'خرید مبلغ 750,000 ریال از کارت 1234 مانده 9,000,000 ریال';

    test('تراکنشِ حذف‌شده با خواندن دوباره‌ی صندوق برنمی‌گردد', () async {
      final at = DateTime.utc(2026, 9, 10, 8, 0);
      final first = await repo.saveParsed(parser.parse(sender: sender, body: body),
          sender: sender, receivedAt: at);
      await repo.deleteTransaction(first.id);

      final again = await repo.saveParsed(parser.parse(sender: sender, body: body),
          sender: sender, receivedAt: at);
      expect(again.isDuplicate, isTrue);
      expect(await repo.count(), 0);
    });

    test('دریافت زنده و صندوق با زمان کمی متفاوت → یک تراکنش', () async {
      // دو طرف مرز بازه‌ی ۵ دقیقه‌ای اثرانگشت
      final live = DateTime.utc(2026, 9, 10, 12, 4, 50);
      final inbox = DateTime.utc(2026, 9, 10, 12, 5, 10);
      await repo.saveParsed(parser.parse(sender: sender, body: body),
          sender: sender, receivedAt: live);
      final second = await repo.saveParsed(parser.parse(sender: sender, body: body),
          sender: sender, receivedAt: inbox);
      expect(second.isDuplicate, isTrue);
      expect(await repo.count(), 1);

      // همان متن، خیلی بعدتر از پنجرهٔ ادغام (۱۰ دقیقه) = یک خریدِ واقعیِ جدا.
      // (بعضی بانک‌ها مانده نمی‌نویسند و دو خریدِ هم‌مبلغ متنِ یکسان دارند؛ نباید
      // اشتباهی یکی شوند. «حقوقِ دوباره‌شمرده» را صفحهٔ «احتمال تکراری» می‌گیرد.)
      final later = await repo.saveParsed(parser.parse(sender: sender, body: body),
          sender: sender, receivedAt: live.add(const Duration(minutes: 30)));
      expect(later.isCreated, isTrue);
      expect(await repo.count(), 2);
    });

    test('متن و زمان پیامک ذخیره می‌شود و ترتیب بر اساس زمان پیامک است', () async {
      Future<String> save(String amount, DateTime at) async => (await repo.saveParsed(
            parser.parse(sender: sender, body: 'خرید مبلغ $amount ریال از کارت 1234'),
            sender: sender,
            receivedAt: at,
          ))
              .id;
      final a = await save('100,000', DateTime.utc(2026, 9, 10, 10));
      final b = await save('200,000', DateTime.utc(2026, 9, 10, 9));
      final c = await save('300,000', DateTime.utc(2026, 9, 10, 11));

      final all = await repo.getAll();
      expect(all.map((t) => t.id).toList(), [c, a, b]);
      expect(all.first.smsBody, contains('300,000'));
      expect(all.first.smsSender, sender);
      expect(all.first.smsReceivedAt, DateTime.utc(2026, 9, 10, 11));
    });

    test('ردیف قدیمی (بدون متن پیامک) با خواندن دوباره‌ی صندوق تکمیل می‌شود', () async {
      final at = DateTime.utc(2026, 9, 1, 7, 0);
      final now = DateTime.utc(2026, 9, 11);
      await repo.insert(TransactionRecord(
        id: 'old',
        kind: 'expense',
        amountRial: 750000,
        cardLast4: '1234',
        sourceMessageHash: smsFingerprint(sender: sender, body: body, receivedAt: at),
        clientCreatedAt: now,
        createdAt: now,
        updatedAt: now,
      ));

      final again = await repo.saveParsed(parser.parse(sender: sender, body: body),
          sender: sender, receivedAt: at);
      expect(again.isDuplicate, isTrue);
      final rec = await repo.getById('old');
      expect(rec!.smsBody, body);
      expect(rec.effectiveTime, at); // دیگر زمانِ واردشدن نیست
    });

    test('فقط مبلغ/نوعِ نامشخص یا ناموفق به بازبینی می‌رود و در جمع نمی‌آید', () async {
      await repo.saveParsed(parser.parse(sender: 'Unknown', body: 'خرید مبلغ 1,000 ریال'),
          sender: 'Unknown');
      await repo.saveParsed(
          parser.parse(sender: sender, body: 'خرید ناموفق مبلغ 5,000 ریال'),
          sender: sender);

      expect(await repo.needsReviewCount(), 1);
      final failed = (await repo.getAll(needsReview: true)).single;
      expect(failed.reviewReasons, [ReviewReason.failed]);
      expect((await repo.summary()).expenseRial, 1000);
    });
  });

  group('صاحب کارت (کیف) و صف دسته‌بندی', () {
    Future<String> saveCard(String card, {DateTime? at}) async => (await repo.saveParsed(
          parser.parse(
              sender: 'BankMellat', body: 'خرید مبلغ 90,000 ریال از کارت $card'),
          sender: 'BankMellat',
          receivedAt: at,
        ))
            .id;

    setUp(() async {
      await repo.setSetting(SettingKeys.meUserId, 'u-me');
      await repo.setSetting(
          SettingKeys.categorizeFrom, DateTime.utc(2000).toIso8601String());
    });

    test('تراکنش به صاحب کارت و برچسبش وصل می‌شود', () async {
      await repo.addWallet(const Wallet(
        id: '',
        ownerName: 'بابا',
        ownerUserId: 'u-father',
        label: 'کارت حقوق',
        cardLast4: '1234',
      ));
      final fathers = await repo.getById(await saveCard('1234'));
      expect(fathers!.ownerName, 'بابا');
      expect(fathers.ownerUserId, 'u-father');
      expect(fathers.walletLabel, 'کارت حقوق');

      final unknown = await repo.getById(await saveCard('9999'));
      expect(unknown!.ownerName, isNull);
      expect(unknown.ownerUserId, 'u-me'); // گوشیِ دریافت‌کننده ویرایشش می‌کند
    });

    test('کیفِ بدون حساب کاربری → ویرایش با همین گوشی', () async {
      await repo.addWallet(const Wallet(
          id: '', ownerName: 'مامان', label: 'کارت', cardLast4: '5555'));
      final t = await repo.getById(await saveCard('5555'));
      expect(t!.ownerName, 'مامان');
      expect(t.ownerUserId, 'u-me');
    });

    test('ثبت کیف بعداً، تراکنش‌های قبلی را منتسب و برای sync صف می‌کند', () async {
      final id = await saveCard('1234');
      await db.delete('outbox');
      await repo.addWallet(const Wallet(
          id: '', ownerName: 'بابا', label: 'کارت حقوق', cardLast4: '1234'));

      expect((await repo.getById(id))!.ownerName, 'بابا');
      expect(await outboxCount(), 1);
    });

    test('تراکنش کارتِ عضو دیگر در صف دسته‌بندی و بازبینی من نمی‌آید', () async {
      await repo.addWallet(const Wallet(
        id: '',
        ownerName: 'بابا',
        ownerUserId: 'u-father',
        label: 'کارت حقوق',
        cardLast4: '1234',
      ));
      await saveCard('1234');
      await repo.saveParsed(
          parser.parse(
              sender: 'BankMellat', body: 'خرید ناموفق مبلغ 1,000 ریال از کارت 1234'),
          sender: 'BankMellat');
      expect(await repo.uncategorized(), isEmpty);
      expect(await repo.needsReviewCount(), 0);

      await saveCard('9999');
      expect(await repo.uncategorized(), hasLength(1));
    });

    test('تراکنش‌های قبل از «شروع دسته‌بندی» در صف نمی‌آیند', () async {
      await repo.setSetting(SettingKeys.categorizeFrom,
          DateTime.utc(2026, 9, 22, 20, 30).toIso8601String());
      await saveCard('1111', at: DateTime.utc(2026, 9, 10));
      final after = await saveCard('2222', at: DateTime.utc(2026, 9, 25));

      final queue = await repo.uncategorized();
      expect(queue.map((t) => t.id), [after]);
    });
  });

  test('پیش‌فرض شروع دسته‌بندی = اول ماه شمسی بعد، و ثابت می‌ماند', () async {
    var now = DateTime.utc(2026, 9, 11, 9); // ۲۰ شهریور ۱۴۰۵
    final r = TransactionRepository(db, clock: () => now);
    expect(await r.categorizeFrom(), DateTime.utc(2026, 9, 22, 20, 30)); // ۱ مهر
    now = DateTime.utc(2026, 11, 1);
    expect(await r.categorizeFrom(), DateTime.utc(2026, 9, 22, 20, 30));
  });

  group('کمک‌تابع‌های sync', () {
    Map<String, dynamic> remote({
      String id = 'srv-1',
      String? hash,
      bool deleted = false,
      String description = '',
    }) =>
        {
          'id': id,
          'kind': 'expense',
          'amount_rial': 1000,
          'counterparty': '',
          'description': description,
          'source': 'sms',
          'source_message_hash': hash ?? '',
          'needs_review': false,
          'is_deleted': deleted,
          'owner': 'u-father',
          'owner_name': 'بابا',
          'captured_by': 'u-father',
          'wallet_label': 'کارت حقوق',
          'card_last4': '1234',
          'allocations': [
            {'name': 'میوه', 'amount_rial': 600},
            {'name': 'دسته‌ی تازه', 'amount_rial': 400},
          ],
          'transaction_date': '2026-09-10T08:00:00Z',
          'client_updated_at': '2026-09-10T09:00:00Z',
        };

    test('applyRemote تراکنش عضو دیگر را با دسته‌هایش درج می‌کند', () async {
      await repo.applyRemote(remote());
      final t = await repo.getById('srv-1');
      expect(t!.isRemote, isTrue);
      expect(t.ownerName, 'بابا');
      expect(t.ownerUserId, 'u-father');
      expect(t.syncStatus, 'synced');
      expect(t.allocations, const [
        Allocation('میوه', 600),
        Allocation('دسته‌ی تازه', 400),
      ]);
      expect(await outboxCount(), 0); // دریافتی دوباره فرستاده نمی‌شود

      await repo.applyRemote(remote(deleted: true));
      expect(await repo.getAll(), isEmpty);
    });

    test('applyRemote تغییرِ محلیِ ارسال‌نشده را خراب نمی‌کند', () async {
      await repo.applyRemote(remote());
      await repo.updateTransaction('srv-1', description: 'نسخه‌ی من');
      await repo.applyRemote(remote(description: 'نسخه‌ی قدیمی سرور'));
      expect((await repo.getById('srv-1'))!.description, 'نسخه‌ی من');
    });

    test('همان پیامک روی دو گوشی → ردیف محلی شناسه‌ی سرور را می‌گیرد', () async {
      const body = 'خرید مبلغ 1,000 ریال از کارت 1234';
      final local = await repo.saveParsed(
          parser.parse(sender: 'BankMellat', body: body),
          sender: 'BankMellat');
      final hash = (await repo.getById(local.id))!.sourceMessageHash!;
      await db.delete('outbox');

      await repo.applyRemote(remote(hash: hash));
      expect(await repo.count(), 1);
      final merged = await repo.getById('srv-1');
      expect(merged!.smsBody, body); // متن پیامکِ محلی حفظ شد
      expect(await repo.getById(local.id), isNull);
    });

    test('rekey دسته‌ها و صف را هم منتقل می‌کند', () async {
      final o = await repo.saveParsed(
          parser.parse(sender: 'BankMellat', body: 'خرید مبلغ 2,000 ریال از کارت 1234'),
          sender: 'BankMellat');
      final cat = (await repo.categories()).first.id;
      await repo.categorize(o.id, [cat]);

      await repo.rekey(o.id, 'server-x');
      final t = await repo.getById('server-x');
      expect(t!.allocations, hasLength(1));
      expect(await repo.getById(o.id), isNull);
      expect(
        (await db.query('outbox')).single['transaction_id'],
        'server-x',
      );
    });
  });
}
