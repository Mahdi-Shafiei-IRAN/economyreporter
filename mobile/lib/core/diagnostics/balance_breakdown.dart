/// توضیحِ عددِ «موجودی» کارتِ خلاصه، کارت به کارت.
///
/// کارت خلاصه می‌گوید: موجودیِ نهایی = موجودیِ اول دوره + درآمد − هزینه. این فایل
/// همان عدد را برای هر کارت باز می‌کند و کنارش «موجودیِ آخرِ دوره طبق بانک» را
/// می‌گذارد. اختلافِ این دو یعنی تراکنش‌های دوره با مانده‌ی بانک نمی‌خوانند
/// (پیامک اشتباه/جاافتاده/تکراری، نوعِ برعکس، انتقال، …).
///
/// عمداً از همان [realBalanceByCard] و همان قاعده‌ی [countsInTotals] استفاده می‌کند
/// تا جمعِ این جدول دقیقاً عددِ کارتِ خلاصه باشد.
library;

import '../../features/transactions/data/period.dart';
import '../../features/transactions/data/transaction_record.dart';
import '../../features/transactions/data/transaction_repository.dart';

class CardPeriodBalance {
  final String key;
  final TransactionRecord sample;

  /// موجودی درست پیش از شروع دوره؛ null یعنی قبل از دوره هیچ تراکنشی نیست (صفر).
  final CardBalance? opening;

  /// موجودیِ آخرِ دوره طبق مانده‌ی بانک؛ null یعنی تا آخر دوره تراکنشی نیست.
  final CardBalance? closing;

  final int incomeRial;
  final int expenseRial;

  /// تراکنش‌های دوره که در درآمد/هزینه نمی‌آیند (انتقال، بازبینی، نامشخص).
  final List<TransactionRecord> uncounted;

  const CardPeriodBalance({
    required this.key,
    required this.sample,
    required this.opening,
    required this.closing,
    required this.incomeRial,
    required this.expenseRial,
    required this.uncounted,
  });

  int get openingRial => opening?.balanceRial ?? 0;
  int get closingRial => closing?.balanceRial ?? 0;

  /// آنچه کارت خلاصه برای این کارت نشان می‌دهد.
  int get expectedClosingRial => openingRial + incomeRial - expenseRial;

  /// بانک − کارت خلاصه. صفر یعنی تراکنش‌های این دوره با مانده‌ی بانک می‌خوانند.
  int get diffRial => closingRial - expectedClosingRial;

  /// موجودیِ اول دوره از مانده‌ی بانک نیامده (تخمین یا صفر).
  bool get openingIsEstimate => opening == null || opening!.isEstimate;

  /// موجودیِ آخر دوره از مانده‌ی بانک نیامده.
  bool get closingIsEstimate => closing == null || closing!.isEstimate;

  /// شماره‌ی کارت/حساب ندارد (فقط با بانک/صاحب گروه شده).
  bool get hasId => !key.contains('|u:');
}

class BalanceBreakdown {
  final Period period;
  final List<CardPeriodBalance> cards;

  const BalanceBreakdown({required this.period, required this.cards});

  int get openingRial => cards.fold(0, (s, c) => s + c.openingRial);
  int get incomeRial => cards.fold(0, (s, c) => s + c.incomeRial);
  int get expenseRial => cards.fold(0, (s, c) => s + c.expenseRial);
  int get expectedClosingRial => openingRial + incomeRial - expenseRial;
  int get bankClosingRial => cards.fold(0, (s, c) => s + c.closingRial);
  int get diffRial => bankClosingRial - expectedClosingRial;
}

/// [scoped]: همه‌ی تراکنش‌های شخصِ انتخاب‌شده (بدون فیلترِ نوع/جستجو).
BalanceBreakdown computeBalanceBreakdown(
    Iterable<TransactionRecord> scoped, Period period) {
  final items = [for (final t in scoped) if (!t.isDeleted) t];
  final start = period.from;
  final end = period.to;
  final openings = start == null
      ? const <String, CardBalance>{}
      : realBalanceByCard(items, asOf: start.subtract(const Duration(microseconds: 1)));
  final closings = realBalanceByCard(items,
      asOf: end?.subtract(const Duration(microseconds: 1)));

  final inPeriod = <String, List<TransactionRecord>>{};
  for (final t in items) {
    if (period.contains(t.effectiveTime)) {
      inPeriod.putIfAbsent(balanceCardKey(t), () => []).add(t);
    }
  }

  final keys = {...openings.keys, ...closings.keys, ...inPeriod.keys};
  final cards = <CardPeriodBalance>[];
  for (final key in keys) {
    final list = inPeriod[key] ?? const <TransactionRecord>[];
    final s = FinanceSummary.of(list);
    final sample = closings[key]?.sample ??
        (list.isNotEmpty ? list.last : openings[key]!.sample);
    cards.add(CardPeriodBalance(
      key: key,
      sample: sample,
      opening: openings[key],
      closing: closings[key],
      incomeRial: s.incomeRial,
      expenseRial: s.expenseRial,
      uncounted: [for (final t in list) if (!countsInTotals(t)) t],
    ));
  }
  // اول کارت‌هایی که اختلاف دارند، بعد بر اساسِ موجودی.
  cards.sort((a, b) {
    final d = b.diffRial.abs().compareTo(a.diffRial.abs());
    return d != 0 ? d : b.closingRial.compareTo(a.closingRial);
  });
  return BalanceBreakdown(period: period, cards: cards);
}
