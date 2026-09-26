import 'package:economy/core/ledger/ledger_math.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/month_report.dart';
import 'package:economy/features/budgets/data/budget.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ledger_fixtures.dart';

void main() {
  final from = DateTime.utc(2026, 9, 22, 20, 30); // ۱ مهر
  final to = DateTime.utc(2026, 10, 22, 20, 30); // ۱ آبان
  DateTime d(int day) => from.add(Duration(days: day));
  const inc = EntryKind.income, exp = EntryKind.expense;

  test('opening goes backward from the first bank balance of the month; totals, categories, budget', () {
    final a1 = orderLedger([
      entry('before', exp, 7, from.subtract(const Duration(days: 3)), acc: 'a1'),
      entry('s1', exp, 100000, d(1), bal: 900000, acc: 'a1'),
      entry('salary', inc, 5000000, d(2), bal: 5900000, acc: 'a1'),
      entry('bread', exp, 30000, d(3), acc: 'a1'),
      entry('fruit', exp, 20000, d(4), acc: 'a1'),
      entry('next', exp, 1, to.add(const Duration(days: 1)), acc: 'a1'),
    ], []);
    final cash = orderLedger([
      entry('cafe', exp, 50000, d(5), acc: 'cash'),
      Entry(
          id: 'move',
          accountId: 'cash',
          kind: exp,
          amountRial: 200000,
          occurredAt: d(6),
          isTransfer: true,
          source: EntrySource.manual,
          createdAt: d(6),
          updatedAt: d(6)),
    ], [
      checkpoint('c', 1000000, d(1), acc: 'cash')
    ]);

    final r = buildMonthReport(
      from: from,
      to: to,
      ledgers: {'a1': a1, 'cash': cash},
      allocations: {
        'bread': const [EntryCategory(categoryId: 'n', name: 'نان', amountRial: 30000)],
        'cafe': const [
          EntryCategory(categoryId: 'r', name: 'رستوران', amountRial: 25000),
          EntryCategory(categoryId: 'n', name: 'نان', amountRial: 25000),
        ],
      },
      budgets: const [
        Budget(id: 'b1', categoryName: 'نان', limitRial: 50000),
        Budget(id: 'b2', categoryName: 'قبوض', limitRial: 100000),
      ],
    );

    expect(r.openingRial, 1000000 + 1000000); // ۹۰۰هزار + ۱۰۰هزارِ همان روز، و نقد
    expect(r.closingRial, 5850000 + 750000);
    expect(r.incomeRial, 5000000);
    expect(r.expenseRial, 100000 + 30000 + 20000 + 50000);
    expect(r.transferRial, 200000);
    expect(r.categories.map((c) => (c.name, c.spentRial, c.limitRial)), [
      ('نان', 55000, 50000),
      ('رستوران', 25000, null),
      ('قبوض', 0, 100000),
    ]);
    expect(r.categories.first.exceeded, isTrue);
    expect(r.uncategorized.map((e) => e.id), ['fruit', 's1']);
    expect(r.uncategorizedRial, 120000);
  });

  test('no checkpoint at all: opening and closing unknown', () {
    final r = buildMonthReport(
        from: from,
        to: to,
        ledgers: {'a': orderLedger([entry('m', exp, 5, d(1))], [])},
        allocations: const {});
    expect(r.openingRial, isNull);
    expect(r.closingRial, isNull);
    expect(r.expenseRial, 5);
  });

  test('splitEqually keeps the exact total', () {
    expect(splitEqually(100, 3), [34, 33, 33]);
    expect(splitEqually(5, 0), isEmpty);
  });
}
