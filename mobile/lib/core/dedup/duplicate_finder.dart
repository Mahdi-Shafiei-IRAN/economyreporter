/// کشف تراکنش‌های احتمالاً تکراری: وقتی یک رخداد (مثل حقوق) دوبار ثبت شده باشد —
/// چون بانک دو پیامکِ متفاوت داده یا از دو سامانه آمده. اینجا فقط «پیشنهاد» می‌دهیم؛
/// حذف با تصمیم کاربر است (مثل تطبیق مانده).
library;

import '../../features/transactions/data/transaction_record.dart';

/// دو تراکنش با مبلغ/نوع/کارتِ یکسان که در این بازه از هم‌اند، احتمالاً یک رخدادند.
const Duration kDuplicateWindow = Duration(hours: 6);

class DuplicateGroup {
  /// به‌ترتیب زمان؛ همیشه دو یا بیشتر.
  final List<TransactionRecord> items;

  const DuplicateGroup(this.items);

  /// قدیمی‌ترین را نگه می‌داریم، بقیه تکراری‌اند.
  TransactionRecord get keep => items.first;
  List<TransactionRecord> get extras => items.sublist(1);

  int get amountRial => items.first.amountRial!;
  String get kind => items.first.kind;

  /// کلید پایدار برای «تکراری نیست» (نادیده گرفتن).
  String get key => (items.map((t) => t.id).toList()..sort()).join('|');
}

class DuplicateFinder {
  const DuplicateFinder();

  List<DuplicateGroup> find(
    List<TransactionRecord> transactions, {
    Set<String> dismissed = const {},
  }) {
    // گروهِ اولیه: نوع + مبلغ + بانک + کارت/حساب یکسان.
    final byKey = <String, List<TransactionRecord>>{};
    for (final t in transactions) {
      if (t.isDeleted || t.needsReview || t.amountRial == null) continue;
      if (t.kind != 'income' && t.kind != 'expense') continue;
      final ref = t.cardLast4 ?? t.accountRef ?? '';
      byKey
          .putIfAbsent('${t.kind}|${t.amountRial}|${t.bankId ?? ''}|$ref', () => [])
          .add(t);
    }

    final groups = <DuplicateGroup>[];
    for (final list in byKey.values) {
      if (list.length < 2) continue;
      list.sort((a, b) => a.effectiveTime.compareTo(b.effectiveTime));
      // خوشه‌های پیاپی که در بازه‌ی زمانیِ نزدیک‌اند.
      var cluster = <TransactionRecord>[list.first];
      for (var i = 1; i < list.length; i++) {
        final gap = list[i].effectiveTime.difference(cluster.last.effectiveTime).abs();
        if (gap <= kDuplicateWindow) {
          cluster.add(list[i]);
        } else {
          _emit(groups, cluster, dismissed);
          cluster = [list[i]];
        }
      }
      _emit(groups, cluster, dismissed);
    }
    // پیشنهادِ بزرگ‌ترین مبلغ اول (مهم‌ترها بالا).
    groups.sort((a, b) => b.amountRial.compareTo(a.amountRial));
    return groups;
  }

  void _emit(List<DuplicateGroup> out, List<TransactionRecord> cluster, Set<String> dismissed) {
    if (cluster.length < 2) return;
    final g = DuplicateGroup(List.of(cluster));
    if (!dismissed.contains(g.key)) out.add(g);
  }
}
