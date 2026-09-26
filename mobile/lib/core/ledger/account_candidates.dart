/// «حساب‌های پیداشده» (docs/v2-design.md ۱۲.۵): حساب هم مثلِ پیامک پیشنهاد می‌شود، نه دستی تایپ.
/// منبع: پیامک‌های منتظرِ شکلِ تراکنش که (۱) شماره‌ی حساب/کارتِ ناشناخته دارند، یا (۲) بی‌شماره‌اند و
/// بانکشان هیچ حسابی (حتی کنارگذاشته) ندارد.
library;

import '../sms/models.dart';
import 'models.dart';

class AccountCandidate {
  final String key;
  final String? bankId;
  final String? cardLast4;
  final String? accountRef;
  final int smsCount;
  final int? lastBalanceRial;
  final DateTime? lastBalanceAt;

  const AccountCandidate({
    required this.key,
    required this.smsCount,
    this.bankId,
    this.cardLast4,
    this.accountRef,
    this.lastBalanceRial,
    this.lastBalanceAt,
  });

  bool get hasNumber => cardLast4 != null || accountRef != null;
}

class _Group {
  final String key;
  final String? bankId;
  final String? cardLast4;
  final String? accountRef;
  int count = 0;
  int? balance;
  DateTime? balanceAt;
  _Group(this.key, this.bankId, this.cardLast4, this.accountRef);
}

List<AccountCandidate> findAccountCandidates({
  required Iterable<SmsItem> pending,
  required Iterable<LedgerAccount> accounts,
  required ParsedTransaction? Function(SmsItem item) parse,
}) {
  final banksWithAccount = {for (final a in accounts) if (a.bankId != null) a.bankId!};
  final groups = <String, _Group>{};
  for (final item in pending) {
    final g = item.suggestion;
    if (item.status != SmsStatus.pending || !g.looksLikeTx || item.body == null) continue;
    final String key;
    ParsedTransaction? p;
    if (g.unknownAccountNumber) {
      p = parse(item);
      if (p == null || !p.hasAccountId) continue;
      final ref = p.accountRef?.replaceAll(RegExp(r'[^0-9]'), '');
      key = '${p.bankId ?? ''}|${p.cardLast4 != null ? 'c:${p.cardLast4}' : 'a:$ref'}';
    } else if (g.accountId == null) {
      p = parse(item);
      if (p == null || p.hasAccountId || p.bankId == null) continue;
      if (banksWithAccount.contains(p.bankId)) continue;
      key = '${p.bankId}|-';
    } else {
      continue;
    }
    final group = groups.putIfAbsent(
        key, () => _Group(key, p!.bankId, p.cardLast4, p.cardLast4 == null ? p.accountRef : null));
    group.count++;
    final at = g.occurredAt ?? item.receivedAt;
    if (g.balanceRial != null && (group.balanceAt == null || at.isAfter(group.balanceAt!))) {
      group.balance = g.balanceRial;
      group.balanceAt = at;
    }
  }
  return [
    for (final g in groups.values)
      AccountCandidate(
        key: g.key,
        bankId: g.bankId,
        cardLast4: g.cardLast4,
        accountRef: g.accountRef,
        smsCount: g.count,
        lastBalanceRial: g.balance,
        lastBalanceAt: g.balanceAt,
      ),
  ]..sort((a, b) => b.smsCount.compareTo(a.smsCount));
}
