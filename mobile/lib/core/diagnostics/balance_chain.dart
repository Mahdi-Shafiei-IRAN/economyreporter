/// عیب‌یابیِ «زنجیره‌ی مانده»: مانده‌ی بانک مرجعِ حقیقت است.
///
/// هر پیامکِ بانک مانده‌ی حساب را بعد از تراکنش می‌گوید؛ پس برای هر حساب باید
/// «مانده‌ی این پیامک = مانده‌ی پیامکِ قبلی ± مبلغ» باشد. هر جا نبود، مقدارِ اختلاف
/// خودش علت را لو می‌دهد:
///   * اختلاف = ۲ برابرِ مبلغ   → نوع برعکس ثبت شده (واریز ↔ برداشت)
///   * مانده عوض نشده          → تکراری است یا اصلاً تراکنش نبوده
///   * دو پیامکِ پشت‌سرهم جابه‌جا → ترتیب زمانی غلط است
///   * هر اختلافِ دیگر          → پیامکِ جاافتاده، کارمزد/سود، یا مبلغِ اشتباه
///
/// هر پیوند فقط با مانده‌ی واقعیِ قبلی سنجیده می‌شود، پس یک خطا به بعدی‌ها سرایت
/// نمی‌کند. گروه‌بندیِ حساب‌ها دقیقاً همان [balanceCardKey] است که موجودیِ کارت
/// خلاصه با آن حساب می‌شود.
library;

import '../../features/transactions/data/transaction_record.dart';
import '../../features/transactions/data/transaction_repository.dart';

enum ChainStatus {
  /// اولین مانده‌ی این حساب (چیزی برای مقایسه نیست).
  start,

  /// با مانده‌ی قبلی جور است.
  ok,

  /// پیامک مانده نداشت؛ فقط مبلغش به انتظارِ بعدی اضافه شد.
  noBalance,

  /// نوعش برعکس ثبت شده (واریز ↔ برداشت).
  signFlipped,

  /// مانده تغییر نکرده: تکراری است یا اصلاً تراکنشِ واقعی نبوده.
  noEffect,

  /// انتقال/نامشخص/منتظر بازبینی است ولی مانده نشان می‌دهد واریز یا برداشت بوده.
  kindSuggested,

  /// ترتیبِ زمانیِ این پیامک و پیامکِ کناری‌اش جابه‌جاست.
  outOfOrder,

  /// اختلافی که با خودِ این پیامک توضیح داده نمی‌شود.
  mismatch,
}

extension ChainStatusInfo on ChainStatus {
  bool get isProblem => switch (this) {
        ChainStatus.start || ChainStatus.ok || ChainStatus.noBalance => false,
        _ => true,
      };

  String get label => switch (this) {
        ChainStatus.start => 'شروع زنجیره',
        ChainStatus.ok => 'جور است',
        ChainStatus.noBalance => 'بدون مانده',
        ChainStatus.signFlipped => 'نوع برعکس ثبت شده',
        ChainStatus.noEffect => 'مانده تغییر نکرده (تکراری/غیرتراکنش)',
        ChainStatus.kindSuggested => 'نوعش از مانده معلوم است',
        ChainStatus.outOfOrder => 'ترتیب زمانی جابه‌جا',
        ChainStatus.mismatch => 'ناجور با مانده',
      };
}

class ChainLink {
  final TransactionRecord tx;
  final ChainStatus status;

  /// مانده‌ی واقعیِ پیامکِ مانده‌دارِ قبلی.
  final int? previousBalanceRial;

  /// انتظار = مانده‌ی قبلی + تراکنش‌های بی‌مانده‌ی بین‌راه + مبلغِ علامت‌دارِ این یکی.
  final int? expectedBalanceRial;

  /// مانده‌ای که خودِ این پیامک گزارش کرده.
  final int? actualBalanceRial;

  /// تغییری که بانک برای همین پیامک نشان می‌دهد (مانده‌ی این − مانده‌ی قبلی − بین‌راه).
  final int? bankDeltaRial;

  /// برای [ChainStatus.kindSuggested]/[ChainStatus.signFlipped]: نوعی که مانده نشان می‌دهد.
  final String? suggestedKind;

  const ChainLink({
    required this.tx,
    required this.status,
    this.previousBalanceRial,
    this.expectedBalanceRial,
    this.actualBalanceRial,
    this.bankDeltaRial,
    this.suggestedKind,
  });

  /// واقعی − انتظار (منفی: برداشتِ ثبت‌نشده/کارمزد؛ مثبت: واریزِ ثبت‌نشده/سود).
  int? get diffRial => (actualBalanceRial == null || expectedBalanceRial == null)
      ? null
      : actualBalanceRial! - expectedBalanceRial!;
}

class AccountChain {
  /// همان [balanceCardKey].
  final String key;

  /// یک تراکنشِ نمونه (برای عنوان و صاحب).
  final TransactionRecord sample;

  /// به‌ترتیبِ زمان (قدیمی ← جدید).
  final List<ChainLink> links;

  const AccountChain({required this.key, required this.sample, required this.links});

  String? get bankId => sample.bankId;

  /// شماره‌ی کارت یا حساب دارد؟ (وگرنه تراکنش‌ها فقط با بانک/صاحب کنار هم آمده‌اند.)
  bool get hasId => !key.contains('|u:');

  List<ChainLink> get problems => [for (final l in links) if (l.status.isProblem) l];

  bool get hasBalance => links.any((l) => l.actualBalanceRial != null);

  int? get lastBalanceRial {
    for (final l in links.reversed) {
      if (l.actualBalanceRial != null) return l.actualBalanceRial;
    }
    return null;
  }
}

/// دو گروه از یک بانک که به‌احتمالِ زیاد **یک حساب**‌اند (مثلاً پیامک‌های خرید با
/// شماره‌ی کارت و واریزها با شماره‌ی حساب). در موجودی هر کدام جدا جمع می‌شوند، پس
/// موجودیِ این حساب دو بار شمرده می‌شود.
class SplitAccountHint {
  final AccountChain a;
  final AccountChain b;

  /// چند بار پیامکِ مانده‌دار بین این دو گروه جابه‌جا شد.
  final int switches;

  /// در چندتا از آن جابه‌جایی‌ها مانده با فرضِ «یک حساب» دقیقاً جور بود.
  final int consistent;

  const SplitAccountHint({
    required this.a,
    required this.b,
    required this.switches,
    required this.consistent,
  });
}

class BalanceChainReport {
  final List<AccountChain> accounts;
  final List<SplitAccountHint> splitHints;

  const BalanceChainReport({required this.accounts, required this.splitHints});

  int get problemCount =>
      accounts.fold(0, (s, a) => s + a.problems.length) + splitHints.length;
}

/// مبلغِ علامت‌دار برای زنجیره؛ null یعنی جهتش معلوم نیست (انتقال/نامشخص/بازبینی).
int? _signed(TransactionRecord t) {
  if (t.needsReview || t.amountRial == null) return null;
  return switch (t.kind) {
    'income' => t.amountRial!,
    'expense' => -t.amountRial!,
    _ => null,
  };
}

/// ترتیبِ پایدار: زمانِ رخداد، بعد زمانِ رسیدنِ پیامک، بعد زمانِ ثبت.
int _chronological(TransactionRecord a, TransactionRecord b) {
  var c = a.effectiveTime.compareTo(b.effectiveTime);
  if (c != 0) return c;
  final ar = a.smsReceivedAt, br = b.smsReceivedAt;
  if (ar != null && br != null) {
    c = ar.compareTo(br);
    if (c != 0) return c;
  }
  c = a.createdAt.compareTo(b.createdAt);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// زنجیره‌ی مانده‌ی همه‌ی حساب‌ها (تراکنش‌های حذف‌شده کنار می‌روند).
BalanceChainReport auditBalanceChains(Iterable<TransactionRecord> all) {
  final byKey = <String, List<TransactionRecord>>{};
  for (final t in all) {
    if (t.isDeleted) continue;
    byKey.putIfAbsent(balanceCardKey(t), () => []).add(t);
  }
  final accounts = <AccountChain>[];
  byKey.forEach((key, list) {
    list.sort(_chronological);
    accounts.add(AccountChain(key: key, sample: list.last, links: _walk(list)));
  });
  accounts.sort((x, y) {
    final c = y.problems.length.compareTo(x.problems.length);
    return c != 0 ? c : y.links.length.compareTo(x.links.length);
  });
  return BalanceChainReport(
    accounts: accounts,
    splitHints: _findSplitAccounts(accounts),
  );
}

List<ChainLink> _walk(List<TransactionRecord> list) {
  final links = <ChainLink>[];
  int? prev; // مانده‌ی واقعیِ آخرین پیامکِ مانده‌دار
  var pending = 0; // جمعِ علامت‌دارِ تراکنش‌های بی‌مانده بعد از prev

  var i = 0;
  while (i < list.length) {
    final t = list[i];
    final actual = t.balanceAfterRial;
    final signed = _signed(t);

    if (actual == null) {
      links.add(ChainLink(tx: t, status: ChainStatus.noBalance));
      if (signed != null) pending += signed;
      i++;
      continue;
    }
    if (prev == null) {
      links.add(ChainLink(tx: t, status: ChainStatus.start, actualBalanceRial: actual));
      prev = actual;
      pending = 0;
      i++;
      continue;
    }

    final base = prev + pending;
    final delta = actual - base;

    // ترتیبِ جابه‌جا: اگر این و پیامکِ بعدی با ترتیبِ برعکس هر دو جور می‌شوند.
    if (signed != null && delta != signed && i + 1 < list.length) {
      final n = list[i + 1];
      final nSigned = _signed(n);
      final nActual = n.balanceAfterRial;
      if (nSigned != null &&
          nActual != null &&
          base + nSigned == nActual &&
          nActual + signed == actual) {
        links.add(ChainLink(
          tx: t,
          status: ChainStatus.outOfOrder,
          previousBalanceRial: prev,
          expectedBalanceRial: base + signed,
          actualBalanceRial: actual,
          bankDeltaRial: delta,
        ));
        links.add(ChainLink(
          tx: n,
          status: ChainStatus.outOfOrder,
          previousBalanceRial: actual,
          expectedBalanceRial: actual + nSigned,
          actualBalanceRial: nActual,
          bankDeltaRial: nActual - actual,
        ));
        // در ترتیبِ درست، پیامکِ i آخر است.
        prev = actual;
        pending = 0;
        i += 2;
        continue;
      }
    }

    final status = _judge(t, signed, delta);
    links.add(ChainLink(
      tx: t,
      status: status,
      previousBalanceRial: prev,
      expectedBalanceRial: base + (signed ?? 0),
      actualBalanceRial: actual,
      bankDeltaRial: delta,
      suggestedKind: switch (status) {
        ChainStatus.signFlipped || ChainStatus.kindSuggested =>
          delta > 0 ? 'income' : 'expense',
        _ => null,
      },
    ));
    prev = actual;
    pending = 0;
    i++;
  }
  return links;
}

ChainStatus _judge(TransactionRecord t, int? signed, int delta) {
  if (signed != null) {
    if (delta == signed) return ChainStatus.ok;
    if (signed != 0 && delta == -signed) return ChainStatus.signFlipped;
    if (delta == 0) return ChainStatus.noEffect;
    return ChainStatus.mismatch;
  }
  // جهت معلوم نیست (انتقال/نامشخص/بازبینی).
  final amount = t.amountRial;
  if (delta == 0) return ChainStatus.noEffect;
  if (amount != null && delta.abs() == amount) {
    // انتقالی که مانده را به همان اندازه جابه‌جا کرده درست است.
    if (t.kind == 'transfer' && !t.needsReview) return ChainStatus.ok;
    return ChainStatus.kindSuggested;
  }
  return ChainStatus.mismatch;
}

/// گروه‌های هم‌بانکی که مانده‌هایشان یک زنجیره‌ی واحد می‌سازند.
List<SplitAccountHint> _findSplitAccounts(List<AccountChain> accounts) {
  final hints = <SplitAccountHint>[];
  final withBalance = [for (final a in accounts) if (a.hasBalance) a];
  for (var x = 0; x < withBalance.length; x++) {
    for (var y = x + 1; y < withBalance.length; y++) {
      final a = withBalance[x], b = withBalance[y];
      if ((a.bankId ?? '') != (b.bankId ?? '')) continue;
      final merged = [
        for (final l in a.links)
          if (l.actualBalanceRial != null) (l.tx, 0),
        for (final l in b.links)
          if (l.actualBalanceRial != null) (l.tx, 1),
      ]..sort((p, q) => _chronological(p.$1, q.$1));
      var switches = 0;
      var consistent = 0;
      for (var i = 1; i < merged.length; i++) {
        final (p, pg) = merged[i - 1];
        final (q, qg) = merged[i];
        if (pg == qg) continue;
        final s = _signed(q);
        if (s == null) continue;
        switches++;
        if (p.balanceAfterRial! + s == q.balanceAfterRial!) consistent++;
      }
      // تساویِ دقیقِ مانده بین دو حسابِ جدا عملاً اتفاقی نمی‌افتد؛ پس یک جور شدن هم
      // نشانه‌ی قوی است، به شرطی که اکثرِ جابه‌جایی‌ها جور باشند.
      if (consistent > 0 && consistent * 2 >= switches) {
        hints.add(SplitAccountHint(
            a: a, b: b, switches: switches, consistent: consistent));
      }
    }
  }
  return hints;
}
