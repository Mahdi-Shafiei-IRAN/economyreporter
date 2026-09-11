/// داده‌ی گزارش (منطق خالص و تست‌پذیر): ستون‌های نمودار، تفکیک‌ها و بسته‌ی PDF.
library;

import '../../core/format/money_format.dart';
import '../../core/sms/jalali.dart';
import '../transactions/data/period.dart';
import '../transactions/data/transaction_record.dart';
import '../transactions/data/transaction_repository.dart';
import '../transactions/data/tx_query.dart';

const List<String> _shortMonths = [
  'فرو', 'ارد', 'خرد', 'تیر', 'مرد', 'شهر', 'مهر', 'آبا', 'آذر', 'دی', 'بهم', 'اسف',
];

String kindLabel(String kind) => switch (kind) {
      'income' => 'واریز',
      'expense' => 'برداشت',
      'transfer' => 'انتقال',
      _ => 'نامشخص',
    };

/// یک ستون نمودار (یک روز یا یک ماه).
class ChartBucket {
  final String label;
  final String fullLabel;
  int incomeRial = 0;
  int expenseRial = 0;

  ChartBucket(this.label, this.fullLabel);
}

/// ستون‌های روزانه‌ی یک ماه، یا ماهانه (۱۲ ماهِ آخرِ دارای داده) برای «همه‌ی زمان‌ها».
List<ChartBucket> buildBuckets(Period period, List<TransactionRecord> items) {
  final counted = items.where(countsInTotals).toList();
  if (!period.isAll) {
    final len = jalaliMonthLength(period.year!, period.month!);
    final month = kJalaliMonthNamesForReport[period.month! - 1];
    final buckets = [
      for (var d = 1; d <= len; d++)
        ChartBucket(toPersianDigits('$d'), toPersianDigits('$d $month')),
    ];
    for (final t in counted) {
      final day = JalaliDate.fromDateTime(t.effectiveTime).day;
      if (day < 1 || day > len) continue;
      _add(buckets[day - 1], t);
    }
    return buckets;
  }
  if (counted.isEmpty) return [];
  final latest = counted
      .map((t) => t.effectiveTime)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final months = <Period>[];
  var p = Period.containing(latest);
  for (var i = 0; i < 12; i++) {
    months.insert(0, p);
    p = p.previous;
  }
  final byMonth = {
    for (final m in months) m: ChartBucket(_shortMonths[m.month! - 1], m.title),
  };
  for (final t in counted) {
    final b = byMonth[Period.containing(t.effectiveTime)];
    if (b != null) _add(b, t);
  }
  return [for (final m in months) byMonth[m]!];
}

void _add(ChartBucket b, TransactionRecord t) {
  if (t.kind == 'income') {
    b.incomeRial += t.amountRial!;
  } else {
    b.expenseRial += t.amountRial!;
  }
}

/// نام ماه‌ها (همان date_format؛ این‌جا تکرار نشده تا وابستگی چرخه‌ای نسازد).
const List<String> kJalaliMonthNamesForReport = [
  'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
  'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
];

/// یک ردیف تفکیک (شخص/کارت/دسته).
class BreakdownEntry {
  final String label;
  final int incomeRial;
  final int expenseRial;
  final int count;

  const BreakdownEntry({
    required this.label,
    required this.incomeRial,
    required this.expenseRial,
    required this.count,
  });
}

/// جمع درآمد/هزینه به‌تفکیک یک کلید؛ به‌ترتیب هزینه (بیشترین اول).
List<BreakdownEntry> breakdown(
  List<TransactionRecord> items,
  String Function(TransactionRecord) keyOf,
) {
  final income = <String, int>{};
  final expense = <String, int>{};
  final count = <String, int>{};
  for (final t in items.where(countsInTotals)) {
    final k = keyOf(t);
    count[k] = (count[k] ?? 0) + 1;
    if (t.kind == 'income') {
      income[k] = (income[k] ?? 0) + t.amountRial!;
    } else {
      expense[k] = (expense[k] ?? 0) + t.amountRial!;
    }
  }
  final list = [
    for (final k in count.keys)
      BreakdownEntry(
        label: k,
        incomeRial: income[k] ?? 0,
        expenseRial: expense[k] ?? 0,
        count: count[k]!,
      ),
  ]..sort((a, b) {
      final c = b.expenseRial.compareTo(a.expenseRial);
      return c != 0 ? c : b.incomeRial.compareTo(a.incomeRial);
    });
  return list;
}

/// هزینه به‌تفکیک دسته (از تخصیص‌های روی خود تراکنش‌ها).
List<BreakdownEntry> categoryBreakdown(List<TransactionRecord> items) {
  final amount = <String, int>{};
  final count = <String, int>{};
  for (final t in items.where((t) => countsInTotals(t) && t.kind == 'expense')) {
    for (final a in t.allocations) {
      amount[a.categoryName] = (amount[a.categoryName] ?? 0) + a.amountRial;
      count[a.categoryName] = (count[a.categoryName] ?? 0) + 1;
    }
  }
  return [
    for (final e in amount.entries)
      BreakdownEntry(label: e.key, incomeRial: 0, expenseRial: e.value, count: count[e.key]!),
  ]..sort((a, b) => b.expenseRial.compareTo(a.expenseRial));
}

/// همه‌ی داده‌ی لازم برای PDF.
class ReportData {
  final String title;
  final String rangeLabel;
  final String fileName;
  final FinanceSummary summary;
  final List<BreakdownEntry> people;
  final List<BreakdownEntry> cards;
  final List<BreakdownEntry> categories;
  final List<TransactionRecord> transactions;
  final DateTime generatedAt;

  const ReportData({
    required this.title,
    required this.rangeLabel,
    required this.fileName,
    required this.summary,
    required this.people,
    required this.cards,
    required this.categories,
    required this.transactions,
    required this.generatedAt,
  });

  factory ReportData.from({
    required Period period,
    required List<TransactionRecord> items,
    required DateTime now,
  }) {
    return ReportData(
      title: 'گزارش مالی خانواده — ${period.title}',
      rangeLabel: period.rangeLabel,
      fileName: period.isAll
          ? 'family-report-all.pdf'
          : 'family-report-${period.year}-${period.month.toString().padLeft(2, '0')}.pdf',
      summary: FinanceSummary.of(items),
      people: breakdown(items, personOf),
      cards: breakdown(items, (t) => '${personOf(t)} — ${cardTitleOf(t)}'),
      categories: categoryBreakdown(items),
      transactions: sortTransactions(items.where((t) => !t.isDeleted), TxSort.newest),
      generatedAt: now,
    );
  }
}
