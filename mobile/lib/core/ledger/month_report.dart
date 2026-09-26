/// گزارشِ ماه (docs/v2-design.md ۶.۱ و ۱۲.۶): موجودیِ اول و آخرِ ماه از نقطه‌ها، درآمد، هزینه،
/// انتقال‌ها، و هزینه به تفکیکِ دسته با سقفِ بودجه.
library;

import '../../features/budgets/data/budget.dart';
import 'ledger_math.dart';
import 'models.dart';

class CategoryLine {
  final String name;
  final int spentRial;
  final int? limitRial;
  const CategoryLine({required this.name, required this.spentRial, this.limitRial});

  bool get exceeded => limitRial != null && spentRial > limitRial!;
}

class MonthReport {
  final DateTime from;
  final DateTime to;

  /// جمعِ حساب‌هایی که موجودیِ آن لحظه‌شان معلوم است؛ null = هیچ‌کدام.
  final int? openingRial;
  final int? closingRial;
  final int incomeRial;
  final int expenseRial;

  /// انتقال بینِ حساب‌های خودم (خروجی‌ها)؛ در درآمد/هزینه نیست.
  final int transferRial;
  final List<CategoryLine> categories;

  /// هزینه‌های بی‌دسته (برای فهرستِ «بی‌دسته»).
  final List<Entry> uncategorized;

  const MonthReport({
    required this.from,
    required this.to,
    required this.openingRial,
    required this.closingRial,
    required this.incomeRial,
    required this.expenseRial,
    required this.transferRial,
    required this.categories,
    required this.uncategorized,
  });

  int get uncategorizedRial => uncategorized.fold(0, (s, e) => s + e.amountRial);
}

int? _sumKnown(Iterable<int?> values) {
  final known = [for (final v in values) if (v != null) v];
  return known.isEmpty ? null : known.fold<int>(0, (s, v) => s + v);
}

/// [ledgers]: فهرستِ مرتبِ حساب‌هایی که در گزارش‌اند (حساب‌های خودم).
MonthReport buildMonthReport({
  required DateTime from,
  required DateTime to,
  required Map<String, List<LedgerItem>> ledgers,
  required Map<String, List<EntryCategory>> allocations,
  List<Budget> budgets = const [],
}) {
  final entries = [
    for (final seq in ledgers.values)
      for (final i in seq)
        if (i is EntryItem && !i.at.isBefore(from) && i.at.isBefore(to)) i.entry,
  ];
  var income = 0, expense = 0, transfer = 0;
  final byCategory = <String, int>{};
  final uncategorized = <Entry>[];
  for (final e in entries) {
    if (e.isTransfer) {
      if (e.kind == EntryKind.expense) transfer += e.amountRial;
      continue;
    }
    if (e.kind == EntryKind.income) {
      income += e.amountRial;
      continue;
    }
    expense += e.amountRial;
    final parts = allocations[e.id] ?? const [];
    if (parts.isEmpty) {
      uncategorized.add(e);
    } else {
      for (final p in parts) {
        byCategory[p.name] = (byCategory[p.name] ?? 0) + p.amountRial;
      }
    }
  }
  final limits = {for (final b in budgets) b.categoryName: b.limitRial};
  final names = {...byCategory.keys, ...limits.keys};
  final lines = [
    for (final n in names) CategoryLine(name: n, spentRial: byCategory[n] ?? 0, limitRial: limits[n]),
  ]..sort((a, b) {
      final c = b.spentRial.compareTo(a.spentRial);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
  uncategorized.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
  return MonthReport(
    from: from,
    to: to,
    openingRial: _sumKnown([for (final seq in ledgers.values) balanceAt(seq, from, inclusive: false)]),
    closingRial: _sumKnown([for (final seq in ledgers.values) balanceAt(seq, to, inclusive: false)]),
    incomeRial: income,
    expenseRial: expense,
    transferRial: transfer,
    categories: lines,
    uncategorized: uncategorized,
  );
}
