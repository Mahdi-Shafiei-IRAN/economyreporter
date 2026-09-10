import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
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
      parser.parse(sender: 'Digikala', body: 'خرید مبلغ 100,000 ریال'),
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
      parser.parse(sender: 'Digikala', body: 'خرید مبلغ 100,000 ریال'),
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

  test('deleteTransaction تراکنش و outbox را حذف می‌کند', () async {
    final outcome = await repo.saveParsed(
      parser.parse(sender: 'ملی', body: 'واریز مبلغ 5,000,000 ریال'),
      sender: 'ملی',
    );
    expect(await repo.count(), 1);
    expect(await outboxCount(), 1);

    await repo.deleteTransaction(outcome.id);
    expect(await repo.count(), 0);
    expect(await outboxCount(), 0);
  });
}
