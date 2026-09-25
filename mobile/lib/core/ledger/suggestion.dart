/// پیشنهادهای برنامه برای پیامک‌ها و پنجره‌های اختلاف (docs/v2-design.md ۵.۳، ۶.۳، ۶.۶).
/// همه **فقط پیشنهاد** است؛ هیچ تابعی اینجا چیزی نمی‌نویسد (I1).
library;

import '../sms/models.dart';
import 'ledger_math.dart';
import 'models.dart';

class AccountReason {
  AccountReason._();
  static const number = 'number';
  static const onlyAccount = 'only_account';
  static const balance = 'balance';
}

class NotTxReason {
  NotTxReason._();
  static const otp = 'otp';
  static const reminder = 'reminder';
  static const failed = 'failed';
  static const noAmount = 'no_amount';

  /// بی‌بانک و بی‌شماره: اعتبارِ کیف پول (دیجی‌پی/دیما)، نه پولِ حسابِ بانکی.
  static const noAccount = 'no_account';
  static const archived = 'archived';
}

const _slack = Duration(minutes: 15);
const _dupWindow = Duration(minutes: 10);

class SuggestionContext {
  final List<LedgerAccount> accounts;

  /// شناسه‌ی حساب ← فهرستِ مرتبِ آن ([orderLedger]).
  final Map<String, List<LedgerItem>> ledgers;

  const SuggestionContext({this.accounts = const [], this.ledgers = const {}});

  factory SuggestionContext.build(
      List<LedgerAccount> accounts, Iterable<Entry> entries, Iterable<Checkpoint> checkpoints) {
    final es = <String, List<Entry>>{};
    final cs = <String, List<Checkpoint>>{};
    for (final e in entries) {
      es.putIfAbsent(e.accountId, () => []).add(e);
    }
    for (final c in checkpoints) {
      cs.putIfAbsent(c.accountId, () => []).add(c);
    }
    return SuggestionContext(accounts: accounts, ledgers: {
      for (final a in accounts) a.id: orderLedger(es[a.id] ?? const [], cs[a.id] ?? const []),
    });
  }

  List<LedgerItem> ledgerOf(String accountId) => ledgers[accountId] ?? const [];

  LedgerAccount? account(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }
}

SmsSuggestion suggest(ParsedTransaction p,
    {required DateTime receivedAt, required SuggestionContext ctx, bool resent = false}) {
  final at = p.occurredAt ?? receivedAt;
  final amount = p.amountRial;
  final balance = p.balanceAfterRial;
  var kind = switch (p.kind) {
    TxKind.income => EntryKind.income,
    TxKind.expense => EntryKind.expense,
    _ => null,
  };

  final (accountId, accountReason, unknownNumber) = _suggestAccount(p, at, kind, ctx);

  // کارت‌به‌کارت/حواله جهت ندارد: از اختلافِ مانده با زنجیره‌ی همان حساب.
  if (kind == null && accountId != null && amount != null && balance != null) {
    final prior = balanceAt(ctx.ledgerOf(accountId), at, backwardFirst: false);
    if (prior != null && balance - prior == amount) kind = EntryKind.income;
    if (prior != null && prior - balance == amount) kind = EntryKind.expense;
  }

  final archived = accountId != null && (ctx.account(accountId)?.archived ?? false);
  final notTx = p.isOtp
      ? NotTxReason.otp
      : p.isReminder
          ? NotTxReason.reminder
          : p.reviewReasons.contains(ReviewReason.failed)
              ? NotTxReason.failed
              : amount == null
                  ? NotTxReason.noAmount
                  : (p.bankId == null && !p.hasAccountId)
                      ? NotTxReason.noAccount
                      : archived
                          ? NotTxReason.archived
                          : null;

  final duplicate = resent ||
      (accountId != null &&
          amount != null &&
          _isLikelyDuplicate(ctx.ledgerOf(accountId), amount, kind, balance, at));

  return SmsSuggestion(
    kind: kind,
    amountRial: amount,
    balanceRial: balance,
    occurredAt: at,
    accountId: accountId,
    accountReason: accountReason,
    notTxReason: notTx,
    likelyDuplicate: duplicate,
    unknownAccountNumber: unknownNumber,
  );
}

/// (حساب، دلیل، شماره‌ی ناشناخته). ترتیب: شماره‌ی داخلِ پیامک؛ تنها حسابِ آن بانک؛
/// حسابی که مانده‌اش دقیقاً با زنجیره جور است؛ وگرنه هیچ.
(String?, String?, bool) _suggestAccount(
    ParsedTransaction p, DateTime at, EntryKind? kind, SuggestionContext ctx) {
  if (p.hasAccountId) {
    final byNumber = [for (final a in ctx.accounts) if (_numberMatches(a, p)) a];
    if (byNumber.length == 1) return (byNumber.single.id, AccountReason.number, false);
    if (byNumber.length > 1) return (null, null, false);
  }
  if (p.bankId == null) return (null, null, p.hasAccountId);
  // پیامکِ شماره‌دار فقط به حسابِ بی‌شماره‌ی همان بانک می‌خورد.
  final candidates = [
    for (final a in ctx.accounts)
      if (!a.archived && a.bankId == p.bankId && !(p.hasAccountId && a.hasNumber)) a,
  ];
  if (candidates.length == 1) return (candidates.single.id, AccountReason.onlyAccount, false);
  final amount = p.amountRial, balance = p.balanceAfterRial;
  if (candidates.length > 1 && amount != null && balance != null) {
    final fits = [
      for (final a in candidates)
        if (_fitsChain(ctx.ledgerOf(a.id), at, amount, balance, kind)) a,
    ];
    if (fits.length == 1) return (fits.single.id, AccountReason.balance, false);
  }
  return (null, null, p.hasAccountId);
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

bool _numberMatches(LedgerAccount a, ParsedTransaction p) {
  if (a.bankId != null && p.bankId != null && a.bankId != p.bankId) return false;
  if (p.cardLast4 != null && a.cardLast4 == p.cardLast4) return true;
  final ref = p.accountRef;
  return ref != null && a.accountRef != null && _digits(a.accountRef!) == _digits(ref);
}

bool _fitsChain(List<LedgerItem> seq, DateTime at, int amount, int balance, EntryKind? kind) {
  final prior = balanceAt(seq, at, backwardFirst: false);
  if (prior == null) return false;
  return switch (kind) {
    EntryKind.income => prior + amount == balance,
    EntryKind.expense => prior - amount == balance,
    null => (balance - prior).abs() == amount,
  };
}

bool _isLikelyDuplicate(
    List<LedgerItem> seq, int amount, EntryKind? kind, int? balance, DateTime at) {
  for (final item in seq) {
    if (item is! EntryItem) continue;
    final e = item.entry;
    if (e.amountRial != amount || (kind != null && e.kind != kind)) continue;
    final eb = e.bankBalanceAfter;
    if (balance != null && eb != null) {
      if (eb == balance) return true;
      continue;
    }
    if (e.occurredAt.difference(at).abs() <= _dupWindow) return true;
  }
  return false;
}

/// راهنمای یک پنجره‌ی اختلاف (۶.۳).
class WindowHints {
  /// پیامک‌های منتظر یا ردشده‌ی داخلِ بازه که مبلغشان دقیقاً اختلاف را توضیح می‌دهد.
  final List<String> explainingSmsKeys;

  /// اختلاف = ۲ برابرِ مبلغِ این تراکنش‌ها با علامتِ برعکس: احتمالاً نوعشان برعکس است.
  final List<String> reversedEntryIds;

  /// نارنجی: پیامکِ منتظر در بازه هست (شاید فقط باید تأیید شود)؛ وگرنه قرمز.
  final bool hasPendingInRange;

  const WindowHints({
    required this.explainingSmsKeys,
    required this.reversedEntryIds,
    required this.hasPendingInRange,
  });
}

WindowHints analyzeWindow(DiscrepancyWindow w, Iterable<SmsItem> sms) {
  final diff = w.diffRial;
  final lo = w.start.subtract(_slack), hi = w.end.add(_slack);
  final explaining = <String>[];
  var pending = false;
  for (final s in sms) {
    if (s.status == SmsStatus.accepted) continue;
    final g = s.suggestion;
    if (g.accountId != null && g.accountId != w.accountId) continue;
    final t = g.occurredAt ?? s.receivedAt;
    if (t.isBefore(lo) || t.isAfter(hi)) continue;
    if (s.status == SmsStatus.pending) pending = true;
    final a = g.amountRial;
    if (a == null) continue;
    final explains = switch (g.kind) {
      EntryKind.income => a == diff,
      EntryKind.expense => -a == diff,
      null => a == diff.abs(),
    };
    if (explains) explaining.add(s.key);
  }
  return WindowHints(
    explainingSmsKeys: explaining,
    reversedEntryIds: [for (final e in w.entries) if (diff == -2 * e.signed) e.id],
    hasPendingInRange: pending,
  );
}
