import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

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
  tearDown(() async => db.close());

  Future<String> saveExpense(String body, {String sender = 'BankMellat'}) async {
    final o = await repo.saveParsed(parser.parse(sender: sender, body: body),
        sender: sender);
    return o.id;
  }

  test('دسته‌های پیش‌فرض seed می‌شوند', () async {
    final cats = await repo.categories();
    expect(cats.length, greaterThanOrEqualTo(10));
    expect(cats.map((c) => c.name), contains('سبزیجات'));
  });

  test('تقسیم مساوی: جمع تخصیص‌ها دقیقاً برابر مبلغ است', () async {
    final id = await saveExpense('خرید مبلغ 100,000 ریال از کارت 1234');
    final ids = (await repo.categories()).take(3).map((c) => c.id).toList();

    await repo.categorize(id, ids);

    final totals = await repo.categoryTotals();
    expect(totals.length, 3);
    expect(totals.fold<int>(0, (a, t) => a + t.amountRial), 100000);
  });

  test('uncategorized قبل و بعد از دسته‌بندی', () async {
    final id = await saveExpense('خرید مبلغ 50,000 ریال از کارت 1234');
    expect((await repo.uncategorized()).any((t) => t.id == id), isTrue);

    final ids = (await repo.categories()).take(1).map((c) => c.id).toList();
    await repo.categorize(id, ids);
    expect((await repo.uncategorized()).any((t) => t.id == id), isFalse);
  });

  test('دسته‌بندی، پرچم بازبینی را پاک می‌کند', () async {
    // فرستنده‌ی ناشناخته → needsReview=true
    final id = await saveExpense('خرید مبلغ 30,000 ریال', sender: 'Digikala');
    final before = (await repo.getAll()).firstWhere((t) => t.id == id);
    expect(before.needsReview, isTrue);

    final firstCat = (await repo.categories()).first.id;
    await repo.categorize(id, [firstCat], description: 'نان سنگک');

    final after = (await repo.getAll()).firstWhere((t) => t.id == id);
    expect(after.needsReview, isFalse);
    expect(after.description, 'نان سنگک');
  });
}
