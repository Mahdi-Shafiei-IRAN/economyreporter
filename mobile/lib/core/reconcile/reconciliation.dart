/// تطبیق مانده: با استفاده از «مانده»ی داخل پیامک، پیامک‌های جاافتاده را کشف می‌کند.
///
/// منطق: برای هر کارت/حساب، تراکنش‌ها را به‌ترتیب زمان می‌چینیم. مانده‌ی بعد از
/// هر تراکنش باید = مانده‌ی قبلی ± مبلغ باشد. اگر نبود، یعنی بین آن دو تراکنش،
/// تراکنشی بوده که پیامکش به این گوشی نرسیده/پاک شده — یا کارمزد/سود بانکی.
library;

import '../../features/transactions/data/transaction_record.dart';

class BalanceGap {
  final String? bankId;
  final String? cardLast4;
  final String? accountRef;
  final String previousTxId;
  final String currentTxId;
  final DateTime previousAt;
  final DateTime currentAt;

  /// مانده‌ی موردانتظار = مانده‌ی قبلی + مبلغِ علامت‌دارِ تراکنش فعلی.
  final int expectedBalanceRial;

  /// مانده‌ی واقعی که پیامک فعلی گزارش کرده.
  final int actualBalanceRial;

  const BalanceGap({
    required this.cardLast4,
    required this.accountRef,
    required this.previousTxId,
    required this.currentTxId,
    required this.previousAt,
    required this.currentAt,
    required this.expectedBalanceRial,
    required this.actualBalanceRial,
    this.bankId,
  });

  /// کلید پایدار (برای «نادیده بگیر»).
  String get key => '$previousTxId|$currentTxId';

  /// اختلاف = واقعی − موردانتظار (منفی یعنی برداشتِ ثبت‌نشده، مثبت یعنی واریزِ ثبت‌نشده).
  int get missingAmountRial => actualBalanceRial - expectedBalanceRial;

  /// زمان تقریبی تراکنشِ جاافتاده (وسط دو پیامک) برای ثبت دستی.
  DateTime get estimatedAt => previousAt.add(currentAt.difference(previousAt) ~/ 2);

  @override
  String toString() =>
      'BalanceGap(card: $cardLast4, missing: $missingAmountRial)';
}

class ReconciliationService {
  const ReconciliationService();

  List<BalanceGap> findGaps(
    List<TransactionRecord> transactions, {
    Set<String> dismissed = const {},
  }) {
    // کلید گروه: بانک + کارت، وگرنه حساب (بانک‌های حساب‌محور).
    final byKey = <String, List<TransactionRecord>>{};
    for (final t in transactions) {
      final ref = t.cardLast4 ?? t.accountRef;
      if (ref == null || t.isDeleted || t.amountRial == null || !_hasReliableTime(t)) {
        continue;
      }
      byKey.putIfAbsent('${t.bankId ?? ''}|$ref', () => []).add(t);
    }

    final gaps = <BalanceGap>[];
    for (final list in byKey.values) {
      list.sort((a, b) => a.effectiveTime.compareTo(b.effectiveTime));
      int? running; // مانده‌ی موردانتظار تا این لحظه
      TransactionRecord? checkpoint; // آخرین تراکنشی که مانده داشت
      for (final t in list) {
        final signed = _signedAmount(t);
        if (signed == null) {
          // تغییرش معلوم نیست (انتقال/منتظر بازبینی) → از مانده‌ی خودش از نو شروع کن.
          running = t.balanceAfterRial;
          checkpoint = t.balanceAfterRial != null ? t : null;
          continue;
        }
        if (running != null) running += signed;
        final actual = t.balanceAfterRial;
        if (actual == null) continue; // مثلاً ثبت دستی: فقط مبلغش به زنجیره اضافه شد
        if (running != null && checkpoint != null && running != actual) {
          final gap = BalanceGap(
            bankId: t.bankId,
            cardLast4: t.cardLast4,
            accountRef: t.accountRef,
            previousTxId: checkpoint.id,
            currentTxId: t.id,
            previousAt: checkpoint.effectiveTime,
            currentAt: t.effectiveTime,
            expectedBalanceRial: running,
            actualBalanceRial: actual,
          );
          if (!dismissed.contains(gap.key)) gaps.add(gap);
        }
        running = actual;
        checkpoint = t;
      }
    }
    return gaps;
  }

  /// بدون زمان واقعی (تاریخ پیامک یا زمان رسیدن)، ترتیب قابل اعتماد نیست و
  /// مقایسه‌ی مانده هشدار اشتباه می‌دهد.
  bool _hasReliableTime(TransactionRecord t) =>
      t.transactionDate != null || t.smsReceivedAt != null;

  int? _signedAmount(TransactionRecord t) {
    if (t.needsReview) return null;
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
