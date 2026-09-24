/// اثبات با مانده‌ی بانک: پیامکی که شماره‌ی حساب/کارت ندارد (یا به‌اشتباه حذف شده بود)
/// ولی مانده‌ی بانکِ **دقیقاً یک** حساب نشان می‌دهد همین پول از همان حساب جابه‌جا شده.
///
/// نمونه‌ی واقعی (پاسارگاد، «بانکداری دیجیتال»): «مبلغ 100,000,000 ریال از طریق حساب پشتوانه
/// برای شما واریز شد. موجودی حساب دیجیتال پاد: 308,174,231» شماره‌ی حساب ندارد، ولی
/// 308,174,231 − 6,260,000 درست مانده‌ی پیامکِ بعدیِ همان حساب است. یا قسطِ ۷۱٬۳۶۷٬۳۹۸
/// که مانده ندارد ولی درست به اندازه‌ی کسریِ بینِ دو پیامکِ مانده‌دارِ همان حساب است.
///
/// شرط‌ها:
///   - مبلغ و نوع (واریز/برداشت) معلوم باشد؛
///   - مانده‌دار: مانده‌اش = مانده‌ی تراکنشِ قبلی ± مبلغ، یا مانده‌ی تراکنشِ بعدی = مانده‌اش ±
///     مبلغِ آن (تراکنش‌های [window] دقیقه‌ی اطراف، و نزدیک‌ترین قبلی/بعدی)؛
///   - بی‌مانده: درست به اندازه‌ی ناجوریِ بینِ دو تراکنشِ مانده‌دارِ همان حساب، و زمانش بینِ آن دو؛
///   - همان تراکنش (همان مانده و مبلغ) از قبل ثبت نشده باشد؛
///   - فقط **یک** حساب جور شود (دو حساب = مبهم = هیچ).
/// جور شدنِ مانده تا ریال احتمالِ تصادف ندارد؛ برای همین این شاهد از شماره‌ی حساب هم محکم‌تر است.
library;

import '../../features/transactions/data/transaction_record.dart';
import '../../features/transactions/data/transaction_repository.dart';
import '../sms/jalali.dart';

/// یک پیامکِ نامزد (ردشده برای نداشتنِ شماره، یا ردیفِ حذف‌شده).
class ProofCandidate {
  /// شناسه‌ی دلخواهِ فراخوان (شناسه‌ی ردیف یا اندیسِ پیامک).
  final String key;

  /// بانکِ پیامک. null = نامزد نیست (بی‌بانک ممکن است اعتبارِ کیف پول باشد).
  final String? bankId;

  /// مبلغِ علامت‌دار: واریز مثبت، برداشت منفی.
  final int signedAmount;
  final int? balanceAfterRial;
  final DateTime at;

  /// اگر پیامک شماره‌ی حساب/کارت دارد: فقط همین حساب ([balanceCardKey]).
  final String? accountKey;

  const ProofCandidate({
    required this.key,
    required this.bankId,
    required this.signedAmount,
    required this.balanceAfterRial,
    required this.at,
    this.accountKey,
  });
}

/// زمانِ قابلِ اعتمادِ پیامک: تاریخِ داخلِ متن، یا زمانِ رسیدن اگر متن فقط تاریخ دارد
/// ([refineDateOnly]؛ ردیف‌های قدیمی هنوز ساعتِ ۰۰:۰۰ دارند).
DateTime? proofTime(DateTime? occurredAt, DateTime? receivedAt) =>
    refineDateOnly(occurredAt, receivedAt);

class _Entry {
  final DateTime at;
  final int? balance;

  /// null = جهتش معلوم نیست (انتقال/نامشخص).
  final int? signed;
  const _Entry(this.at, this.balance, this.signed);
}

class _Account {
  final String key;
  final String? bankId;
  final TransactionRecord sample;
  final List<_Entry> entries;
  _Account(this.key, this.bankId, this.sample, this.entries);
}

int? _signedOf(TransactionRecord t) => switch (t.kind) {
      'income' when !t.needsReview => t.amountRial,
      'expense' when !t.needsReview => t.amountRial == null ? null : -t.amountRial!,
      _ => null,
    };

/// کلیدِ نامزد ← نمونه‌ای از حسابی که مانده ثابتش کرد (بانک/کارت/حسابش را از آن بگیر).
/// نامزدها به ترتیبِ زمان و در چند دور بررسی می‌شوند؛ هر اثبات به زنجیره اضافه می‌شود تا
/// چند تراکنشِ پشتِ هم (کارمزد، بعد واریزِ وام) هم ثابت شوند.
Map<String, TransactionRecord> proveByBalance({
  required Iterable<TransactionRecord> live,
  required Iterable<ProofCandidate> candidates,
  Duration window = const Duration(minutes: 15),
}) {
  final byKey = <String, List<TransactionRecord>>{};
  for (final t in live) {
    if (t.isDeleted) continue;
    if (t.cardLast4 == null && t.accountRef == null) continue; // حسابِ بی‌شماره
    if (t.isRemote && t.smsBody == null) continue; // تراکنشِ گوشیِ دیگر (عضوِ خانواده)
    byKey.putIfAbsent(balanceCardKey(t), () => []).add(t);
  }
  final accounts = <_Account>[];
  byKey.forEach((key, list) {
    if (!list.any((t) => t.balanceAfterRial != null)) return;
    sortForBalance(list);
    accounts.add(_Account(key, list.last.bankId, list.last, [
      for (final t in list)
        _Entry(proofTime(t.transactionDate, t.smsReceivedAt) ?? t.effectiveTime,
            t.balanceAfterRial, _signedOf(t)),
    ]));
  });

  final pending = [
    for (final c in candidates)
      if (c.bankId != null && c.signedAmount != 0) c,
  ]..sort((a, b) => a.at.compareTo(b.at));
  final proven = <String, TransactionRecord>{};
  for (var pass = 0; pass < 4 && pending.isNotEmpty; pass++) {
    var changed = false;
    for (final c in [...pending]) {
      _Account? match;
      int? insertAt;
      var ambiguous = false;
      for (final a in accounts) {
        if (c.accountKey != null ? a.key != c.accountKey : a.bankId != c.bankId) continue;
        final at = _fit(a.entries, c, window);
        if (at == null) continue;
        if (match != null) ambiguous = true;
        match = a;
        insertAt = at;
      }
      if (match == null || ambiguous) continue;
      proven[c.key] = match.sample;
      match.entries.insert(insertAt!, _Entry(c.at, c.balanceAfterRial, c.signedAmount));
      pending.remove(c);
      changed = true;
    }
    if (!changed) break;
  }
  return proven;
}

/// جای نامزد در زنجیره اگر جور است؛ وگرنه null.
int? _fit(List<_Entry> es, ProofCandidate c, Duration w) {
  final d = c.signedAmount;
  final lo = c.at.subtract(w), hi = c.at.add(w);
  bool near(_Entry e) => !e.at.isBefore(lo) && !e.at.isAfter(hi);
  final bal = c.balanceAfterRial;

  if (bal != null) {
    // همین تراکنش قبلاً ثبت شده (پیامکِ دوباره، یا دو پیامک برای یک تراکنش).
    if (es.any((e) =>
        e.balance == bal && e.signed == d && e.at.difference(c.at).abs() <= const Duration(days: 2))) {
      return null;
    }
    var before = -1, after = -1;
    for (var i = 0; i < es.length; i++) {
      if (es[i].balance == null) continue;
      if (es[i].at.isBefore(lo)) before = i;
      if (after == -1 && es[i].at.isAfter(hi)) after = i;
    }
    for (var i = 0; i < es.length; i++) {
      final e = es[i];
      if (e.balance == null || !(near(e) || i == before)) continue;
      if (e.balance! + d == bal) return i + 1; // بعد از e
    }
    for (var i = 0; i < es.length; i++) {
      final e = es[i];
      if (e.balance == null || e.signed == null || !(near(e) || i == after)) continue;
      if (bal + e.signed! == e.balance) return i; // قبل از e
    }
    return null;
  }

  // بی‌مانده: اندازه‌ی ناجوریِ بینِ دو تراکنشِ مانده‌دارِ پشتِ هم.
  int? prev;
  var sum = 0;
  var unknown = false;
  for (var i = 0; i < es.length; i++) {
    final e = es[i];
    if (e.balance == null) {
      if (e.signed == null) {
        unknown = true;
      } else {
        sum += e.signed!;
      }
      continue;
    }
    if (prev != null && !unknown && e.signed != null) {
      final p = es[prev];
      final gap = e.balance! - (p.balance! + sum + e.signed!);
      if (gap == d && !c.at.isBefore(p.at.subtract(w)) && !c.at.isAfter(e.at.add(w))) {
        return prev + 1;
      }
    }
    prev = i;
    sum = 0;
    unknown = false;
  }
  return null;
}
