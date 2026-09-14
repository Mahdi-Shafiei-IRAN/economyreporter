/// کشفِ انتقالِ بینِ کارت‌های خانواده: وقتی از یک کارت مبلغی برداشت می‌شود و
/// «تقریباً هم‌زمان» همان مبلغ به کارتِ دیگری واریز می‌شود، این یک جابه‌جاییِ پول
/// است، نه درآمد/خرجِ واقعی — پس نباید در خالص حساب شود. اینجا فقط «پیشنهاد» می‌دهیم؛
/// نشان‌کردن با تصمیم کاربر است (مثل تطبیق مانده و تکراری‌ها).
library;

import '../../features/transactions/data/transaction_record.dart';

/// بازه‌ی زمانیِ نزدیک برای اینکه یک برداشت و یک واریزِ هم‌مبلغ، «یک انتقال» باشند.
const Duration kTransferWindow = Duration(minutes: 30);

class TransferPair {
  /// برداشت (از کارتِ مبدأ) و واریز (به کارتِ مقصد).
  final TransactionRecord out; // expense
  final TransactionRecord inn; // income

  const TransferPair(this.out, this.inn);

  int get amountRial => out.amountRial ?? 0;

  /// کلید پایدار برای «نه، انتقال نیست» (نادیده‌گرفتن).
  String get key => ([out.id, inn.id]..sort()).join('|');
}

class TransferFinder {
  const TransferFinder();

  List<TransferPair> find(
    List<TransactionRecord> transactions, {
    Set<String> dismissed = const {},
  }) {
    bool usable(TransactionRecord t) =>
        !t.isDeleted &&
        !t.needsReview &&
        t.amountRial != null &&
        t.amountRial! > 0;

    final expenses = [
      for (final t in transactions)
        if (t.kind == 'expense' && usable(t)) t
    ]..sort((a, b) => a.effectiveTime.compareTo(b.effectiveTime));
    final incomes = [
      for (final t in transactions)
        if (t.kind == 'income' && usable(t)) t
    ]..sort((a, b) => a.effectiveTime.compareTo(b.effectiveTime));

    final used = <String>{};
    final pairs = <TransferPair>[];
    for (final e in expenses) {
      if (used.contains(e.id)) continue;
      TransactionRecord? best;
      for (final i in incomes) {
        if (used.contains(i.id)) continue;
        if (i.amountRial != e.amountRial) continue;
        // کارتِ مبدأ و مقصد باید فرق کنند (وگرنه یک تراکنش دوبار است، نه انتقال).
        if (_sameCard(e, i)) continue;
        final gap = i.effectiveTime.difference(e.effectiveTime).abs();
        if (gap > kTransferWindow) continue;
        best = i;
        break; // نزدیک‌ترینِ هم‌مبلغ (incomes مرتب‌اند)
      }
      if (best == null) continue;
      final pair = TransferPair(e, best);
      if (dismissed.contains(pair.key)) continue;
      used..add(e.id)..add(best.id);
      pairs.add(pair);
    }
    pairs.sort((a, b) => b.amountRial.compareTo(a.amountRial));
    return pairs;
  }

  bool _sameCard(TransactionRecord a, TransactionRecord b) {
    String? ref(TransactionRecord t) =>
        (t.cardLast4?.isNotEmpty ?? false) ? '${t.bankId}|${t.cardLast4}' :
        (t.accountRef?.isNotEmpty ?? false) ? '${t.bankId}|${t.accountRef}' : null;
    final ra = ref(a), rb = ref(b);
    // اگر هر دو شناسه دارند و یکی‌اند → همان کارت. اگر شناسه نامعلوم است، بر اساسِ
    // صاحبِ کارت جدا در نظر می‌گیریم (انتقال بین دو نفر).
    if (ra != null && rb != null) return ra == rb;
    return (a.ownerUserId != null && a.ownerUserId == b.ownerUserId);
  }
}
