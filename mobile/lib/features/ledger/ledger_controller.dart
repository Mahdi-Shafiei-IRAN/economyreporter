/// حالتِ صفحه‌های نسخه‌ی ۲ (docs/v2-design.md بخش ۷)، پشتِ پرچمِ `ledger_v2`.
/// هر تغییرِ دفتر فقط از دکمه‌های کاربر به این کلاس می‌رسد (I1).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;

import '../../core/family/family_api.dart';
import '../../core/ledger/account_candidates.dart';
import '../../core/ledger/ledger_math.dart';
import '../../core/ledger/ledger_repository.dart';
import '../../core/ledger/models.dart';
import '../../core/ledger/month_report.dart';
import '../budgets/data/budget.dart';
import '../categories/data/category.dart';
import '../../core/ledger/sms_intake.dart';
import '../../core/ledger/suggestion.dart';
import '../../core/sms/bank_registry.dart';
import '../../core/sms/jalali.dart';
import '../../core/sms/models.dart';
import '../../core/sms/sms_parser.dart';
import '../senders/data/allowed_sender.dart';
import '../senders/data/sender_candidates.dart';
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

/// فرستنده‌های پیامکِ بانک (در اپ: همان فهرستِ مجازِ نسخه‌ی ۱ از طریقِ DashboardController).
class SenderOps {
  final Future<List<SenderCandidate>> Function() candidates;
  final Future<void> Function(String address, String? bankId) allow;
  final Future<void> Function(String address) dismiss;
  final Future<void> Function(String id) remove;

  const SenderOps({
    required this.candidates,
    required this.allow,
    required this.dismiss,
    required this.remove,
  });
}

/// کارتِ «قدمِ بعدی» بالای خانه (طرح ۱۲.۵)؛ همیشه یکی، به همین ترتیب.
enum NextStep { chooseBanks, confirmAccounts, setBalances, reviewPending, allGood }

class LedgerController extends ChangeNotifier {
  LedgerController(
    this.repo, {
    required this.allowedSenders,
    this.readInbox,
    this.people,
    this.senders,
    DateTime Function()? clock,
    this.parser = const SmsParser(),
  }) : _clock = clock ?? DateTime.now;

  final LedgerRepository repo;
  final Future<List<AllowedSender>> Function() allowedSenders;

  /// صندوقِ پیامکِ گوشی (در اپ: SmsInboxService).
  Future<List<IncomingSms>> Function()? readInbox;

  /// نام و اعضای خانواده (از داشبوردِ نسخه‌ی ۱) برای فرمِ حساب.
  LedgerPeople Function()? people;

  /// انتخابِ بانک‌ها (قدمِ ۱).
  SenderOps? senders;

  /// هر تغییرِ دفتر به دستِ کاربر (برای همگام‌سازیِ بی‌درنگ با سرور).
  VoidCallback? onLocalChange;

  /// آخرین همگام‌سازی با سرور و تعدادِ منتظرِ ارسال (برای تنظیمات).
  DateTime? lastSyncAt;
  String? lastSyncError;
  int unsyncedCount = 0;
  final SmsParser parser;
  final DateTime Function() _clock;

  DateTime get now => _clock().toUtc();

  bool enabled = false;
  bool setupDone = false;
  DateTime? startDate;

  /// همه‌ی حساب‌ها (کیف‌ها)، شاملِ حساب‌های بقیه‌ی خانواده که از سرور آمده‌اند.
  List<AccountView> accounts = const [];

  /// «حساب‌های پیداشده» در پیامک‌های منتظر.
  List<AccountCandidate> accountCandidates = const [];

  /// پیامک‌های منتظر، جدیدترین اول.
  List<SmsItem> pending = const [];

  /// همه‌ی پیامک‌ها (منتظر، ثبت، رد) — برای راهنمای پنجره‌های اختلاف.
  List<SmsItem> _items = const [];
  Map<String, List<LedgerItem>> _ledgers = const {};
  List<Category> categories = const [];
  Map<String, List<EntryCategory>> allocations = const {};
  List<Budget> budgets = const [];
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

  List<AllowedSender> get banks => _allowed;

  /// حسابِ خودم یا حسابی که روی همین گوشی ساخته شده. حساب‌های بقیه‌ی خانواده پیامکشان به گوشیِ
  /// خودشان می‌رود؛ تا همگام‌سازیِ نسخه‌ی ۲ (فاز ۴) اینجا نشان داده نمی‌شوند.
  bool isMine(LedgerAccount a) {
    final me = people?.call().meUserId;
    return a.ownerUserId == null || me == null || a.ownerUserId == me;
  }

  List<AccountView> get activeAccounts =>
      [for (final a in accounts) if (!a.account.archived && isMine(a.account)) a];
  List<AccountView> get archivedAccounts =>
      [for (final a in accounts) if (a.account.archived && isMine(a.account)) a];
  int get othersAccountCount => [for (final a in accounts) if (!isMine(a.account)) a].length;

  NextStep get nextStep {
    if (_allowed.isEmpty) return NextStep.chooseBanks;
    if (accountCandidates.isNotEmpty) return NextStep.confirmAccounts;
    if (activeAccounts.any((a) => a.needsAnchor)) return NextStep.setBalances;
    if (pendingCount > 0) return NextStep.reviewPending;
    return NextStep.allGood;
  }

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
    setupDone = await repo.isSetupDone();
    startDate = await repo.startDate();
    _allowed = await allowedSenders();
    final accs = await repo.accounts();
    final entries = await repo.entries();
    final cps = await repo.checkpoints();
    final items = await repo.smsItems();
    _byId = {for (final a in accs) a.id: a};
    _items = items;
    pending = [for (final i in items) if (i.status == SmsStatus.pending) i];
    categories = await repo.categories();
    allocations = await repo.allocations();
    budgets = await repo.budgets();
    final ctx = SuggestionContext.build(accs, entries, cps);
    _ledgers = ctx.ledgers;
    accounts = [for (final a in accs) _view(a, ctx.ledgerOf(a.id))];
    accountCandidates = findAccountCandidates(pending: pending, accounts: accs, parse: _parse);
    final (from, to) = jalaliMonthRange(now);
    final totals = periodTotals(entries, from, to);
    monthIncome = totals.income;
    monthExpense = totals.expense;
    unsyncedCount = await repo.unsyncedCount();
    final status = await repo.syncStatus();
    if (status != null) {
      final j = jsonDecode(status) as Map<String, dynamic>;
      lastSyncAt = DateTime.tryParse(j['at'] as String? ?? '')?.toUtc();
      lastSyncError = j['error'] as String?;
    }
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
        onLocalChange?.call();
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
    onLocalChange?.call();
  }

  // --- کارِ کاربر ---

  Future<void> accept(
    SmsItem item, {
    required String accountId,
    required EntryKind kind,
    required int amountRial,
    DateTime? occurredAt,
    String? note,
    bool isTransfer = false,
    List<String> categoryIds = const [],
  }) =>
      _track(() async {
        await repo.acceptSms(item.key,
            accountId: accountId,
            kind: kind,
            amountRial: amountRial,
            occurredAt: occurredAt,
            note: note,
            isTransfer: isTransfer,
            categoryIds: categoryIds);
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
    bool isTransfer = false,
    List<String> categoryIds = const [],
  }) =>
      _track(() async {
        await repo.addEntry(
            accountId: accountId,
            kind: kind,
            amountRial: amountRial,
            occurredAt: occurredAt,
            note: note,
            isTransfer: isTransfer,
            categoryIds: categoryIds);
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

  // --- جزئیاتِ حساب و اختلاف (فاز ۳) ---

  AccountView? view(String accountId) {
    for (final v in accounts) {
      if (v.account.id == accountId) return v;
    }
    return null;
  }

  List<LedgerItem> ledgerOf(String accountId) => _ledgers[accountId] ?? const [];

  List<DiscrepancyWindow> windowsOf(String accountId) => discrepancies(ledgerOf(accountId));

  WindowHints hintsFor(DiscrepancyWindow w) => analyzeWindow(w, _items);

  SmsItem? smsItemByKey(String key) {
    for (final i in _items) {
      if (i.key == key) return i;
    }
    return null;
  }

  Future<void> updateEntry(Entry e, {List<String>? categoryIds}) => _track(() async {
        await repo.updateEntry(e, categoryIds: categoryIds);
        await _afterLedgerChange();
      });

  Future<void> deleteEntry(String id) => _track(() async {
        await repo.deleteEntry(id);
        await _afterLedgerChange();
      });

  Future<void> deleteCheckpoint(String id) => _track(() async {
        await repo.deleteCheckpoint(id);
        await _afterLedgerChange();
      });

  /// «نوعش برعکس است» — پیشنهادِ پنجره‌ی اختلاف، با دستِ کاربر.
  Future<void> flipKind(Entry e) => updateEntry(e.copyWith(
      kind: e.kind == EntryKind.income ? EntryKind.expense : EntryKind.income));

  /// «اصلاح»: تراکنشِ صریح با یادداشتِ اجباری، وسطِ بازه تا داخلِ همان پنجره بیفتد (۱۲.۶).
  Future<void> addAdjustment(DiscrepancyWindow w, String note) => _track(() async {
        final diff = w.diffRial;
        final mid = w.start.add(w.end.difference(w.start) ~/ 2);
        await repo.addEntry(
          accountId: w.accountId,
          kind: diff > 0 ? EntryKind.income : EntryKind.expense,
          amountRial: diff.abs(),
          occurredAt: mid,
          note: note,
          source: EntrySource.adjustment,
        );
        await _afterLedgerChange();
      });

  /// زمانِ پیش‌فرضِ «تراکنشِ جاافتاده» برای یک پنجره: وسطِ بازه.
  DateTime gapTime(DiscrepancyWindow w) => w.start.add(w.end.difference(w.start) ~/ 2);

  Future<void> setEntryCategories(String entryId, List<String> categoryIds) => _track(() async {
        await repo.setEntryCategories(entryId, categoryIds);
        await _load();
        onLocalChange?.call();
      });

  Future<List<String>> suggestedCategoryIds(SmsItem item) => repo.v1CategoryIdsFor(item);

  /// گزارشِ ماهی که [anyTimeInMonth] در آن است؛ فقط حساب‌های خودم.
  MonthReport monthReport(DateTime anyTimeInMonth) {
    final (from, to) = jalaliMonthRange(anyTimeInMonth);
    return buildMonthReport(
      from: from,
      to: to,
      ledgers: {for (final v in activeAccounts) v.account.id: ledgerOf(v.account.id)},
      allocations: allocations,
      budgets: budgets,
    );
  }

  Future<void> setBudget(String categoryName, int? limitRial) => _track(() async {
        await repo.setBudget(categoryName, limitRial);
        await _load();
        onLocalChange?.call();
      });

  // --- راهنمای سه‌قدمی و حساب‌های پیداشده ---

  Future<void> finishSetup() => _track(() async {
        await repo.setSetupDone();
        await _load();
        onLocalChange?.call();
      });

  /// «مالِ من است»: حساب با آخرین مانده‌ی پیامک به‌عنوانِ «موجودیِ الان» (قابلِ اصلاح).
  Future<LedgerAccount> acceptCandidate(
    AccountCandidate c, {
    required String ownerName,
    String? ownerUserId,
    String? label,
    int? balanceRial,
  }) =>
      createAccount(
        ownerName: ownerName,
        ownerUserId: ownerUserId,
        label: (label == null || label.trim().isEmpty) ? _defaultLabel(c.bankId) : label,
        bankId: c.bankId,
        cardLast4: c.cardLast4,
        accountRef: c.accountRef,
        balanceRial: balanceRial,
      );

  /// «پیگیری نکن»: حسابِ کنارگذاشته؛ پیامک‌هایش «تراکنش نیست» پیشنهاد می‌شوند.
  Future<void> dismissCandidate(AccountCandidate c) => _track(() async {
        final me = people?.call();
        final a = await repo.createAccount(
          ownerName: me?.meName ?? 'من',
          ownerUserId: me?.meUserId,
          label: _defaultLabel(c.bankId),
          bankId: c.bankId,
          cardLast4: c.cardLast4,
          accountRef: c.accountRef,
        );
        await repo.setArchived(a.id, true);
        await _afterLedgerChange();
      });

  String _defaultLabel(String? bankId) => bankId == null ? 'نقد' : bankNameById(bankId);

  Future<List<SenderCandidate>> senderCandidates() async =>
      await senders?.candidates() ?? const [];

  /// «بانک است»: فرستنده مجاز می‌شود و پیامک‌هایش (از تاریخِ شروع) منتظرِ تأیید می‌آیند.
  Future<void> allowSender(String address, String? bankId) => _track(() async {
        await senders?.allow(address, bankId);
        await _syncInbox();
      });

  Future<void> dismissSender(String address) => _track(() async {
        await senders?.dismiss(address);
        await _load();
      });

  Future<void> removeSender(String id) => _track(() async {
        await senders?.remove(id);
        await _load();
      });

  ParsedTransaction? _parse(SmsItem item) {
    final body = item.body;
    if (body == null) return null;
    return parser.parse(
        sender: item.sender,
        body: body,
        bankId: findAllowedSender(_allowed, item.sender)?.bankId,
        receivedAt: item.receivedAt);
  }

  /// پیش‌پرِ «حسابِ تازه» از متنِ پیامکی که شماره‌اش ناشناخته است.
  AccountPrefill prefillFrom(SmsItem item) {
    final p = _parse(item);
    if (p == null) return const AccountPrefill();
    return AccountPrefill(
        bankId: p.bankId,
        cardLast4: p.cardLast4,
        accountRef: p.accountRef,
        balanceRial: p.balanceAfterRial);
  }
}
