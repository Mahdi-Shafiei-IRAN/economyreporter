/// حالتِ صفحه‌های نسخه‌ی ۲ (docs/v2-design.md بخش ۷)، پشتِ پرچمِ `ledger_v2`.
/// هر تغییرِ دفتر فقط از دکمه‌های کاربر به این کلاس می‌رسد (I1).
library;

import 'package:flutter/foundation.dart';

import '../../core/family/family_api.dart';
import '../../core/ledger/ledger_math.dart';
import '../../core/ledger/ledger_repository.dart';
import '../../core/ledger/models.dart';
import '../../core/ledger/sms_intake.dart';
import '../../core/ledger/suggestion.dart';
import '../../core/sms/jalali.dart';
import '../../core/sms/sms_parser.dart';
import '../senders/data/allowed_sender.dart';
import 'ledger_notifications.dart';

/// اولِ ماهِ شمسیِ [now] تا اولِ ماهِ بعد (UTC).
(DateTime, DateTime) jalaliMonthRange(DateTime now) {
  final j = JalaliDate.fromDateTime(now);
  final next = j.month == 12 ? JalaliDate(j.year + 1, 1, 1) : JalaliDate(j.year, j.month + 1, 1);
  return (JalaliDate(j.year, j.month, 1).toUtcStart(), next.toUtcStart());
}

/// یک حساب روی صفحه‌ی اصلی.
class AccountView {
  final LedgerAccount account;

  /// null = هنوز «موجودیِ الان» ندارد (نه نقطه‌ی دستی، نه پیامکِ ثبت‌شده‌ی مانده‌دار).
  final AccountBalance? balance;

  /// آخرین مانده‌ی بانکِ همین حساب (تراکنشِ ثبت‌شده یا پیامکِ منتظر): پیش‌فرضِ «موجودیِ الان».
  final int? lastBankBalance;
  final DateTime? lastBankBalanceAt;

  /// پیامکِ منتظری که مانده‌اش از آخرین نقطه جدیدتر است (فقط نمایش؛ عدد عوض نمی‌شود).
  final int? unconfirmedBalance;
  final int discrepancyCount;

  const AccountView({
    required this.account,
    required this.balance,
    this.lastBankBalance,
    this.lastBankBalanceAt,
    this.unconfirmedBalance,
    this.discrepancyCount = 0,
  });

  bool get needsAnchor => balance == null;
}

/// پیش‌پرِ فرمِ حسابِ تازه از روی یک پیامک.
class AccountPrefill {
  final String? bankId;
  final String? cardLast4;
  final String? accountRef;
  final int? balanceRial;
  const AccountPrefill({this.bankId, this.cardLast4, this.accountRef, this.balanceRial});
}

typedef LedgerPeople = ({String? meName, String? meUserId, List<FamilyMember> members});

class LedgerController extends ChangeNotifier {
  LedgerController(
    this.repo, {
    required this.allowedSenders,
    this.readInbox,
    this.people,
    DateTime Function()? clock,
    this.parser = const SmsParser(),
  }) : _clock = clock ?? DateTime.now;

  final LedgerRepository repo;
  final Future<List<AllowedSender>> Function() allowedSenders;

  /// صندوقِ پیامکِ گوشی (در اپ: SmsInboxService).
  Future<List<IncomingSms>> Function()? readInbox;

  /// نام و اعضای خانواده (از داشبوردِ نسخه‌ی ۱) برای فرمِ حساب.
  LedgerPeople Function()? people;
  final SmsParser parser;
  final DateTime Function() _clock;

  DateTime get now => _clock().toUtc();

  bool enabled = false;
  DateTime? startDate;
  List<AccountView> accounts = const [];

  /// پیامک‌های منتظر، جدیدترین اول.
  List<SmsItem> pending = const [];
  int monthIncome = 0;
  int monthExpense = 0;
  Map<String, LedgerAccount> _byId = const {};
  List<AllowedSender> _allowed = const [];

  final Set<Future<Object?>> _inflight = {};

  bool get isIdle => _inflight.isEmpty;

  /// منتظرِ همه‌ی کارهای در جریان (برای تست).
  Future<void> settle() async {
    while (_inflight.isNotEmpty) {
      await Future.wait([..._inflight]).catchError((_) => const <Object?>[]);
    }
  }

  Future<T> _track<T>(Future<T> Function() body) {
    final f = body();
    _inflight.add(f);
    f.whenComplete(() => _inflight.remove(f)).ignore();
    return f;
  }

  LedgerAccount? account(String? id) => id == null ? null : _byId[id];

  List<AccountView> get activeAccounts => [for (final a in accounts) if (!a.account.archived) a];
  List<AccountView> get archivedAccounts => [for (final a in accounts) if (a.account.archived) a];

  List<SmsItem> get pendingArchived =>
      [for (final i in pending) if (i.suggestion.notTxReason == NotTxReason.archived) i];
  List<SmsItem> get pendingActive =>
      [for (final i in pending) if (i.suggestion.notTxReason != NotTxReason.archived) i];
  int get pendingCount => pendingActive.length;

  /// «انتخابِ همه‌ی موارد بی‌مشکل»: پیشنهادِ کامل و نه احتمالاً تکراری. فقط انتخاب؛ ثبت با کاربر.
  List<SmsItem> get readyToAccept => [
        for (final i in pendingActive)
          if (i.suggestion.isComplete && !i.suggestion.likelyDuplicate) i,
      ];

  int? get totalBalance {
    final known = [for (final a in activeAccounts) if (a.balance != null) a.balance!.balanceRial];
    return known.isEmpty ? null : known.fold<int>(0, (s, b) => s + b);
  }

  Future<void> load() => _track(_load);

  Future<void> _load() async {
    enabled = await repo.isEnabled();
    startDate = await repo.startDate();
    _allowed = await allowedSenders();
    final accs = await repo.accounts();
    final entries = await repo.entries();
    final cps = await repo.checkpoints();
    final items = await repo.smsItems();
    _byId = {for (final a in accs) a.id: a};
    pending = [for (final i in items) if (i.status == SmsStatus.pending) i];
    final ctx = SuggestionContext.build(accs, entries, cps);
    accounts = [for (final a in accs) _view(a, ctx.ledgerOf(a.id))];
    final (from, to) = jalaliMonthRange(now);
    final totals = periodTotals(entries, from, to);
    monthIncome = totals.income;
    monthExpense = totals.expense;
    notifyListeners();
  }

  AccountView _view(LedgerAccount a, List<LedgerItem> seq) {
    final balance = currentBalance(seq);
    int? last;
    DateTime? lastAt;
    void consider(int? b, DateTime at) {
      if (b == null || (lastAt != null && !at.isAfter(lastAt!))) return;
      last = b;
      lastAt = at;
    }

    for (final i in seq) {
      if (i is EntryItem) consider(i.entry.bankBalanceAfter, i.at);
    }
    int? unconfirmed;
    DateTime? unconfirmedAt;
    for (final s in pending) {
      final g = s.suggestion;
      if (g.accountId != a.id || g.balanceRial == null) continue;
      final at = g.occurredAt ?? s.receivedAt;
      consider(g.balanceRial, at);
      final newer = balance != null && at.isAfter(balance.anchor.at);
      if (newer && (unconfirmedAt == null || at.isAfter(unconfirmedAt))) {
        unconfirmed = g.balanceRial;
        unconfirmedAt = at;
      }
    }
    return AccountView(
      account: a,
      balance: balance,
      lastBankBalance: last,
      lastBankBalanceAt: lastAt,
      unconfirmedBalance: unconfirmed,
      discrepancyCount: discrepancies(seq).length,
    );
  }

  /// روشن/خاموش کردنِ نسخه‌ی ۲. روشن: تاریخِ شروع + خواندنِ پیامک‌های این ماه (همه منتظر).
  Future<void> setEnabled(bool on) => _track(() async {
        await repo.setEnabled(on);
        if (on) {
          await repo.ensureStartDate();
          await _syncInbox();
        }
        await _load();
      });

  /// خواندنِ صندوق → پیامک‌های منتظر (هرگز تراکنش). تعدادِ پیامکِ تازه.
  Future<int> syncInbox() => _track(_syncInbox);

  Future<int> _syncInbox() async {
    final read = readInbox;
    if (read == null) return 0;
    final allowed = await allowedSenders();
    final results = await repo.intakeAll(await read(), allowed: allowed);
    await repo.refreshPendingSuggestions(allowed: allowed);
    await _load();
    return results.whereType<IntakeNew>().length;
  }

  /// پیامکِ زنده؛ پیامک‌های منتظرِ تازه را برمی‌گرداند (برای نوتیفیکیشن).
  Future<List<SmsItem>> intake(List<IncomingSms> sms) => _track(() async {
        final results = await repo.intakeAll(sms, allowed: await allowedSenders());
        await _load();
        return [
          for (final r in results)
            if (r is IntakeNew && r.item.status == SmsStatus.pending) r.item,
        ];
      });

  Future<void> _afterLedgerChange() async {
    await repo.refreshPendingSuggestions(allowed: await allowedSenders(), force: true);
    await _load();
  }

  // --- کارِ کاربر ---

  Future<void> accept(
    SmsItem item, {
    required String accountId,
    required EntryKind kind,
    required int amountRial,
    DateTime? occurredAt,
    String? note,
  }) =>
      _track(() async {
        await repo.acceptSms(item.key,
            accountId: accountId,
            kind: kind,
            amountRial: amountRial,
            occurredAt: occurredAt,
            note: note);
        await _afterLedgerChange();
      });

  Future<void> acceptSuggested(SmsItem item) => _track(() async {
        await repo.acceptSuggested(item.key);
        await _afterLedgerChange();
      });

  /// «ثبتِ انتخاب‌شده‌ها»؛ فقط پیشنهادهای کامل. تعدادِ ثبت‌شده.
  Future<int> acceptMany(Iterable<SmsItem> items) => _track(() async {
        var n = 0;
        for (final i in items) {
          if (!i.suggestion.isComplete) continue;
          await repo.acceptSuggested(i.key);
          n++;
        }
        await _afterLedgerChange();
        return n;
      });

  Future<void> reject(SmsItem item, RejectReason reason) => _track(() async {
        await repo.rejectSms(item.key, reason);
        await _afterLedgerChange();
      });

  /// «ردِ همه‌ی پیامک‌های حسابِ کنارگذاشته» — با یک فشارِ کاربر (۶.۵).
  Future<int> rejectArchived() => _track(() async {
        final items = pendingArchived;
        for (final i in items) {
          await repo.rejectSms(i.key, RejectReason.notTx);
        }
        await _afterLedgerChange();
        return items.length;
      });

  Future<void> addManual({
    required String accountId,
    required EntryKind kind,
    required int amountRial,
    required DateTime occurredAt,
    String? note,
  }) =>
      _track(() async {
        await repo.addEntry(
            accountId: accountId,
            kind: kind,
            amountRial: amountRial,
            occurredAt: occurredAt,
            note: note);
        await _afterLedgerChange();
      });

  /// حسابِ تازه؛ [balanceRial] = «موجودیِ الان» (لنگر، ۶.۲).
  Future<LedgerAccount> createAccount({
    required String ownerName,
    required String label,
    String? ownerUserId,
    String? bankId,
    String? cardLast4,
    String? accountRef,
    int? balanceRial,
  }) =>
      _track(() async {
        final a = await repo.createAccount(
            ownerName: ownerName,
            ownerUserId: ownerUserId,
            label: label,
            bankId: bankId,
            cardLast4: cardLast4,
            accountRef: accountRef);
        if (balanceRial != null) {
          await repo.addCheckpoint(accountId: a.id, balanceRial: balanceRial, at: now);
        }
        await _afterLedgerChange();
        return a;
      });

  /// «موجودیِ الان» / «تطبیق با موجودیِ واقعی»: نقطه‌ی دستی با زمانِ الان.
  Future<void> setBalanceNow(String accountId, int balanceRial) => _track(() async {
        await repo.addCheckpoint(accountId: accountId, balanceRial: balanceRial, at: now);
        await _afterLedgerChange();
      });

  Future<void> setArchived(String accountId, bool archived) => _track(() async {
        await repo.setArchived(accountId, archived);
        await _afterLedgerChange();
      });

  /// دکمه‌ی نوتیفیکیشن وقتی اپ باز است.
  Future<bool> applyNotificationAction(String actionId, String smsKey) => _track(() async {
        final done = await applyLedgerAction(repo, actionId, smsKey);
        if (done) {
          await _afterLedgerChange();
        } else {
          await _load();
        }
        return done;
      });

  /// پیش‌پرِ «حسابِ تازه» از متنِ پیامکی که شماره‌اش ناشناخته است.
  AccountPrefill prefillFrom(SmsItem item) {
    final body = item.body;
    if (body == null) return const AccountPrefill();
    final p = parser.parse(
        sender: item.sender,
        body: body,
        bankId: findAllowedSender(_allowed, item.sender)?.bankId,
        receivedAt: item.receivedAt);
    return AccountPrefill(
        bankId: p.bankId,
        cardLast4: p.cardLast4,
        accountRef: p.accountRef,
        balanceRial: p.balanceAfterRial);
  }
}
