import 'package:economy/core/ledger/ledger_math.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ledger_fixtures.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 23, 6);
  DateTime h(int hours) => t0.add(Duration(hours: hours));
  const inc = EntryKind.income, exp = EntryKind.expense;

  group('orderLedger', () {
    test('same-minute SMS are chained by bank balance, not by creation order', () {
      final a = entry('A', exp, 100, h(1), bal: 900, created: h(3));
      final b = entry('B', exp, 100, h(1), bal: 800, created: h(2));
      final seq = orderLedger([b, a], [checkpoint('c', 1000, t0)]);
      expect(seq.map((i) => i is EntryItem ? i.entry.id : 'cp'), ['cp', 'A', 'B']);
    });

    test('a manual checkpoint sits after entries at or before its time', () {
      final seq = orderLedger(
          [entry('late', exp, 5, h(2)), entry('same', exp, 5, h(1))], [checkpoint('c', 50, h(1))]);
      expect(seq.map((i) => i is EntryItem ? i.entry.id : 'cp'), ['same', 'cp', 'late']);
    });

    test('deleted entries and checkpoints are left out', () {
      final gone = entry('x', exp, 5, h(1)).copyWith(deletedAt: h(2));
      expect(orderLedger([gone], []), isEmpty);
    });
  });

  group('currentBalance', () {
    test('last checkpoint plus signed entries after it', () {
      final seq = orderLedger([
        entry('s1', exp, 100, h(1), bal: 900),
        entry('m1', exp, 50, h(2)),
      ], [
        checkpoint('c', 1000, t0)
      ]);
      final b = currentBalance(seq)!;
      expect(b.balanceRial, 850);
      expect((b.anchor as EntryItem).entry.id, 's1');
    });

    test('no checkpoint at all: unknown balance', () {
      expect(currentBalance(orderLedger([entry('m', exp, 5, h(1))], [])), isNull);
    });
  });

  group('discrepancies', () {
    test('scenario 2: consistent chain has no window', () {
      final seq = orderLedger([
        entry('s1', exp, 100, h(1), bal: 900),
        entry('s2', inc, 300, h(2), bal: 1200),
      ], [
        checkpoint('c', 1000, t0)
      ]);
      expect(discrepancies(seq), isEmpty);
      expect(currentBalance(seq)!.balanceRial, 1200);
    });

    test('scenario 3: a missing SMS shows as a window with its exact amount', () {
      final seq = orderLedger([
        entry('s1', exp, 100, h(1), bal: 900),
        // missing: expense 200 at h(2), balance 700
        entry('s3', exp, 50, h(3), bal: 650),
      ], [
        checkpoint('c', 1000, t0)
      ]);
      final ws = discrepancies(seq);
      expect(ws, hasLength(1));
      expect(ws.single.diffRial, -200);
      expect(ws.single.start, h(1));
      expect(ws.single.end, h(3));
      expect(ws.single.entries.map((e) => e.id), ['s3']);
      expect(ws.single.accountId, 'a1');
    });

    test('scenario 5: cash account, reconcile, adjustment closes the gap', () {
      final base = [
        entry('m1', exp, 1000000, h(1)),
      ];
      final cps = [checkpoint('anchor', 10000000, t0), checkpoint('real', 8500000, h(2))];
      expect(currentBalance(orderLedger(base, [cps.first]))!.balanceRial, 9000000);
      final ws = discrepancies(orderLedger(base, cps));
      expect(ws.single.diffRial, -500000);
      final fixed = orderLedger([...base, entry('adj', exp, 500000, h(2))], cps);
      expect(discrepancies(fixed), isEmpty);
      expect(currentBalance(fixed)!.balanceRial, 8500000);
    });

    test('scenario 6: a wrong "balance now" shows at the next bank SMS', () {
      final seq = orderLedger([entry('s1', exp, 100000, h(1), bal: 5000000)],
          [checkpoint('anchor', 5000000, t0)]); // really 5,100,000
      expect(discrepancies(seq).single.diffRial, 100000);
    });
  });

  group('balanceAt', () {
    test('month opening goes backward from the nearest later checkpoint', () {
      final seq = orderLedger([
        entry('s1', exp, 100, h(24), bal: 900),
        entry('s2', exp, 50, h(48), bal: 850),
      ], []);
      expect(balanceAt(seq, t0, inclusive: false), 1000);
    });

    test('without a later checkpoint it goes forward from the previous one', () {
      final seq = orderLedger([entry('m', exp, 100, h(1))], [checkpoint('c', 1000, t0)]);
      expect(balanceAt(seq, h(5)), 900);
    });

    test('forward-first gives the chain value right before a new SMS', () {
      final seq = orderLedger([entry('s1', exp, 100, h(1), bal: 900)], [checkpoint('c', 1000, t0)]);
      expect(balanceAt(seq, h(2), backwardFirst: false), 900);
    });

    test('empty ledger: null', () {
      expect(balanceAt(const [], t0), isNull);
    });
  });
}
