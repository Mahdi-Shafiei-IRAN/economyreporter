import 'package:economy/core/database/app_database.dart';
import 'package:economy/features/budgets/data/budget.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../helpers/db_test_helper.dart';

void main() {
  late Database db;
  late TransactionRepository repo;

  setUpAll(initSqfliteFfiForTests);
  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath);
    repo = TransactionRepository(db);
  });
  tearDown(() async => db.close());

  Future<String> catId(String name) async =>
      (await repo.categories()).firstWhere((c) => c.name == name).id;

  test('مصرفِ بودجه = جمعِ خرجِ همان دسته در بازه', () async {
    final at = DateTime.utc(2026, 9, 10);
    final id = await repo.addManual(kind: 'expense', amountRial: 600000, at: at);
    await repo.categorize(id, [await catId('میوه')]);

    await repo.addBudget(const Budget(id: '', categoryName: 'میوه', limitRial: 1000000));

    final usage = await repo.budgetUsage(
        from: DateTime.utc(2026, 9, 1), to: DateTime.utc(2026, 10, 1));
    expect(usage.length, 1);
    expect(usage.single.categoryName, 'میوه');
    expect(usage.single.spentRial, 600000);
    expect(usage.single.remainingRial, 400000);
    expect(usage.single.exceeded, isFalse);
  });

  test('عبور از سقف تشخیص داده می‌شود', () async {
    final at = DateTime.utc(2026, 9, 10);
    final id = await repo.addManual(kind: 'expense', amountRial: 1200000, at: at);
    await repo.categorize(id, [await catId('قبوض')]);
    await repo.addBudget(const Budget(id: '', categoryName: 'قبوض', limitRial: 1000000));

    final usage = await repo.budgetUsage(
        from: DateTime.utc(2026, 9, 1), to: DateTime.utc(2026, 10, 1));
    expect(usage.single.exceeded, isTrue);
    expect(usage.single.remainingRial, -200000);
  });

  test('حذفِ نرمِ بودجه از فهرست خارج می‌شود ولی برای sync می‌ماند', () async {
    await repo.addBudget(const Budget(id: '', categoryName: 'میوه', limitRial: 500000));
    final b = (await repo.budgets()).single;
    await repo.deleteBudget(b.id);
    expect(await repo.budgets(), isEmpty);
    // هنوز pending است تا حذف به سرور برسد
    final pending = await repo.pendingBudgets();
    expect(pending.any((r) => r['id'] == b.id && r['is_deleted'] == 1), isTrue);
  });

  test('کیفِ سرور از راه applyRemoteBudget درج می‌شود', () async {
    await repo.applyRemoteBudget({
      'id': 'srv-1',
      'category_name': 'رستوران',
      'period': 'monthly',
      'limit_rial': 300000,
      'is_deleted': false,
    });
    expect((await repo.budgets()).single.categoryName, 'رستوران');
  });
}
