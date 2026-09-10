/// تطبیق مانده: با استفاده از «مانده»ی داخل پیامک، پیامک‌های جاافتاده را کشف می‌کند.
///
/// منطق: برای هر کارت، تراکنش‌ها را به‌ترتیب زمان می‌چینیم. مانده‌ی بعد از هر
/// تراکنش باید = مانده‌ی قبلی + (مبلغِ علامت‌دار) باشد. اگر نبود، یعنی بین آن دو
/// تراکنش، تراکنش(هایی) جا افتاده است.
library;

import '../../features/transactions/data/transaction_record.dart';

class BalanceGap {
  final String? cardLast4;
  final String? accountRef;
  final String previousTxId;
  final String currentTxId;

  /// مانده‌ی موردانتظار = مانده‌ی قبلی + مبلغِ علامت‌دارِ تراکنش فعلی.
  final int expectedBalanceRial;

  /// مانده‌ی واقعی که پیامک فعلی گزارش کرده.
  final int actualBalanceRial;

  const BalanceGap({
    required this.cardLast4,
    required this.accountRef,
    required this.previousTxId,
    required this.currentTxId,
    required this.expectedBalanceRial,
    required this.actualBalanceRial,
  });

  /// اختلاف = واقعی − موردانتظار (منفی یعنی برداشتِ ثبت‌نشده، مثبت یعنی واریزِ ثبت‌نشده).
  int get missingAmountRial => actualBalanceRial - expectedBalanceRial;

  @override
  String toString() =>
      'BalanceGap(card: $cardLast4, missing: $missingAmountRial)';
}

class ReconciliationService {
  const ReconciliationService();

  List<BalanceGap> findGaps(List<TransactionRecord> transactions) {
    // کلید گروه: کارت، وگرنه حساب (بانک‌های حساب‌محور).
    final byKey = <String, List<TransactionRecord>>{};
    for (final t in transactions) {
      final key = t.cardLast4 ?? t.accountRef;
      if (key == null ||
          t.balanceAfterRial == null ||
          t.amountRial == null) {
        continue;
      }
      byKey.putIfAbsent(key, () => []).add(t);
    }

    final gaps = <BalanceGap>[];
    for (final list in byKey.values) {
      list.sort((a, b) => a.effectiveTime.compareTo(b.effectiveTime));
      for (var i = 1; i < list.length; i++) {
        final prev = list[i - 1];
        final curr = list[i];
        final signed = _signedAmount(curr);
        if (signed == null) continue; // نوع نامشخص/انتقال → قابل بررسی نیست
        final expected = prev.balanceAfterRial! + signed;
        if (expected != curr.balanceAfterRial) {
          gaps.add(BalanceGap(
            cardLast4: curr.cardLast4,
            accountRef: curr.accountRef,
            previousTxId: prev.id,
            currentTxId: curr.id,
            expectedBalanceRial: expected,
            actualBalanceRial: curr.balanceAfterRial!,
          ));
        }
      }
    }
    return gaps;
  }

  int? _signedAmount(TransactionRecord t) {
    switch (t.kind) {
      case 'income':
        return t.amountRial!;
      case 'expense':
        return -t.amountRial!;
      default:
        return null;
    }
  }
}
