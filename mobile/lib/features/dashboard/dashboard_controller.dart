/// کنترلر صفحه‌ی اصلی: بازه، مرتب‌سازی، فیلترها، انتخاب چندتایی و همه‌ی عملیات
/// روی تراکنش‌ها (با رعایت اینکه فقط صاحب کارت ویرایش می‌کند).
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' hide Category;

import '../../core/family/family_api.dart';
import '../../core/dedup/duplicate_finder.dart';
import '../../core/diagnostics/balance_breakdown.dart';
import '../../core/diagnostics/balance_chain.dart';
import '../../core/diagnostics/diagnostic_report.dart';
import '../../core/diagnostics/repair.dart';
import '../../core/diagnostics/sms_diagnosis.dart';
import '../../core/reconcile/reconciliation.dart';
import '../../core/transfer/transfer_finder.dart';
import '../budgets/data/budget.dart';
import '../../core/sms/sms_importer.dart';
import '../../core/sms/sms_parser.dart';
import '../../core/sync/sync_service.dart';
import '../categories/data/category.dart';
import '../senders/data/allowed_sender.dart';
import '../senders/data/sender_candidates.dart';
import '../transactions/data/period.dart';
import '../transactions/data/transaction_record.dart';
import '../transactions/data/transaction_repository.dart';
import '../transactions/data/tx_query.dart';
import '../wallets/data/wallet.dart';

/// نمای صفحه‌ی اصلی: پله‌ای (شخص ← کارت ← تراکنش) یا همه با هم.
enum HomeView { people, all }

class DashboardController extends ChangeNotifier {
  final TransactionStore repository;
  final SmsParser parser;
  final DateTime Function() _clock;

  /// بعد از هر تغییر محلی صدا زده می‌شود (مثلاً برای همگام‌سازی خودکار).
  VoidCallback? onLocalChange;

  /// خواندن صندوق پیامک گوشی (برای پیشنهاد فرستنده‌های بانک).
  Future<List<RawSms>> Function()? readInbox;

  /// خواندنِ عمیق‌ترِ صندوق برای صفحه‌ی عیب‌یابی (اگر نبود، همان [readInbox]).
  Future<List<RawSms>> Function()? readInboxForDiagnosis;

  /// بعد از مجاز کردن فرستنده‌ی تازه: خواندن دوباره‌ی صندوق، تا پیامک‌های قبلیِ
  /// همان فرستنده هم ثبت شوند.
  Future<void> Function()? onSendersChanged;

  DashboardController(
    this.repository, {
    this.parser = const SmsParser(),
    this.familyApi,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        period = Period.containing((clock ?? DateTime.now)());

  /// برای افزودنِ عضوِ خانواده توسطِ مدیر (اختیاری؛ در تست‌ها معمولاً null).
  final FamilyApi? familyApi;

  bool loading = true;
  bool _loadedOnce = false;

  /// اکنون (قابل تزریق برای تست).
  DateTime get now => _clock();

  // --- تنظیمات نمایش ---
  Period period;
  TxSort sort = TxSort.newest;
  KindFilter kind = KindFilter.all;

  /// شخص انتخاب‌شده (در هر دو نما)؛ جمعِ بالای صفحه هم فقط مال همین شخص است.
  String? person;
  String search = '';
  HomeView view = HomeView.people;

  // --- داده ---
  List<TransactionRecord> periodItems = const [];
  List<TransactionRecord> reviewItems = const [];
  List<TransactionRecord> uncategorized = const [];
  List<BalanceGap> balanceGaps = const [];
  List<DuplicateGroup> duplicateGroups = const [];
  List<TransferPair> transferPairs = const [];
  List<Wallet> wallets = const [];

  /// تراکنش‌های پیامکیِ حذف‌شده (برای «برگرداندن» در عیب‌یابی).
  List<TransactionRecord> deletedSms = const [];

  /// نتیجه‌ی آخرین تعمیرِ خودکار (null یعنی هنوز اجرا نشده).
  RepairResult? lastRepair;
  List<AllowedSender> allowedSenders = const [];
  List<FamilyMember> members = const [];
  String? meUserId;
  String? meName;
  String? myRole;
  DateTime? categorizeFrom;
  SyncStatusInfo syncStatus = const SyncStatusInfo();
  Map<String, TransactionRecord> _byId = const {};

  /// نمایش متن پیامک اصلی روی ردیف تراکنش‌ها.
  bool showSmsText = true;

  /// شناسه‌ی تراکنش‌های انتخاب‌شده (انتخاب چندتایی).
  final Set<String> selected = {};

  List<TransactionRecord>? _visibleCache;

  /// تراکنش‌های بازه پس از فیلتر و مرتب‌سازی (همان چیزی که دیده می‌شود و جمع می‌خورد).
  List<TransactionRecord> get visible => _visibleCache ??= applyQuery(
        periodItems,
        sort: sort,
        kind: kind,
        person: person,
        search: search,
      );

  /// سازگاری با صفحه‌های قدیمی/تست‌ها.
  List<TransactionRecord> get transactions => visible;

  FinanceSummary get summary => FinanceSummary.of(visible);

  /// آیا اصلاً مانده‌ای از بانک داریم؟ (اگر نه، موجودیِ اول دوره نامعلوم است.)
  bool get hasRealBalance =>
      _byId.values.any((t) => !t.isDeleted && t.balanceAfterRial != null);

  Iterable<TransactionRecord> get _scopedAll =>
      _byId.values.where((t) => person == null || personOf(t) == person);

  /// موجودیِ «اولِ دوره» (از «مانده»ی پیامک‌ها، درست پیش از شروع دوره).
  /// null یعنی مانده‌ای نداریم یا دوره «همه» است.
  int? get openingBalance {
    if (!hasRealBalance || period.isAll) return null;
    final start = period.from;
    if (start == null) return null;
    return realBalanceRial(_scopedAll,
        asOf: start.subtract(const Duration(microseconds: 1)));
  }

  /// موجودیِ نهایی = موجودیِ اول دوره + درآمد − هزینه (اگر اول‌دوره معلوم باشد).
  int? get closingBalance {
    final o = openingBalance;
    if (o == null) return null;
    return o + summary.balanceRial;
  }

  // ---------------------------------------------------------------------------
  // عیب‌یابی (فقط خواندنی؛ چیزی را تغییر نمی‌دهد)
  // ---------------------------------------------------------------------------

  /// عددِ موجودیِ کارت خلاصه، کارت به کارت، کنارِ موجودیِ آخرِ دوره طبق بانک.
  BalanceBreakdown balanceBreakdown() =>
      computeBalanceBreakdown(_scopedAll, period);

  /// زنجیره‌ی مانده‌ی هر حساب (شخصِ انتخاب‌شده اعمال می‌شود).
  BalanceChainReport balanceChains() => auditBalanceChains(_scopedAll,
      deleted: deletedSms.where((t) => person == null || personOf(t) == person));

  /// سرنوشتِ هر پیامکِ فرستنده‌های مجاز + پیش‌نمایشِ قانونِ پیشنهادی.
  Future<SmsDiagnosisReport> diagnoseSmsMessages() async {
    var inbox = const <RawSms>[];
    var inboxRead = false;
    final read = readInboxForDiagnosis ?? readInbox;
    if (read != null) {
      try {
        inbox = await read();
        inboxRead = true;
      } catch (_) {
        // بدون مجوز پیامک فقط تراکنش‌های ثبت‌شده بررسی می‌شوند.
      }
    }
    return diagnoseSms(
      inbox: inbox,
      stored: [..._byId.values, ...deletedSms],
      allowed: allowedSenders,
      parser: parser,
      inboxRead: inboxRead,
    );
  }

  // ---------------------------------------------------------------------------
  // درست کردن (از صفحه‌ی عیب‌یابی)
  // ---------------------------------------------------------------------------

  static RepairResult? _decodeRepair(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return RepairResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>> _kept() async {
    final raw = await repository.getSetting(SettingKeys.keptTransactions);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<List<RawSms>> _readInboxSafe() async {
    final read = readInboxForDiagnosis ?? readInbox;
    if (read == null) return const [];
    try {
      return await read();
    } catch (_) {
      return const []; // بدون مجوز پیامک
    }
  }

  /// تعمیرِ خودکار با قانون‌های فعلی (نگاه کن به [planRepair]) و بعد واردکردنِ
  /// پیامک‌های تراکنشیِ صندوق که هنوز ثبت نشده‌اند. نتیجه ذخیره می‌شود.
  Future<RepairResult> runRepair() async {
    await load();
    final inbox = await _readInboxSafe();
    final plan = planRepair(
      records: _byId.values,
      inbox: inbox,
      allowed: allowedSenders,
      now: _clock(),
      kept: await _kept(),
      parser: parser,
    );
    await repository.applyPatches(plan.patches);
    var imported = 0;
    if (inbox.isNotEmpty) {
      final importer = SmsImporter(repository,
          parser: parser, deviceId: await repository.getSetting(SettingKeys.deviceId));
      imported = (await importer.importAll(inbox)).created;
    }
    final result = RepairResult(
      at: plan.result.at,
      adopted: plan.result.adopted,
      backfilled: plan.result.backfilled,
      removedIds: plan.result.removedIds,
      imported: imported,
    );
    await repository.setSetting(SettingKeys.repairResult, jsonEncode(result.toJson()));
    await _changed();
    return result;
  }

  /// یک بار بعد از نصبِ این نسخه (بعدها از دکمه‌ی «اجرای دوباره»).
  Future<RepairResult?> runRepairOnce() async {
    if (await repository.getSetting(SettingKeys.repairResult) != null) return null;
    return runRepair();
  }

  /// برگرداندنِ تراکنشِ حذف‌شده؛ تعمیرِ خودکار دیگر حذفش نمی‌کند.
  Future<void> restoreTransaction(TransactionRecord t) async {
    final kept = await _kept()..add(t.id);
    await repository.setSetting(SettingKeys.keptTransactions, jsonEncode(kept.toList()));
    await repository.applyPatches([TxPatch(t.id, restore: true)]);
    await _changed();
  }

  /// نوعی که مانده‌ی بانک نشان می‌دهد (واریز/برداشت) + خروج از بازبینی.
  Future<void> fixKind(TransactionRecord t, String kind) =>
      updateTransaction(t.id, kind: kind, needsReview: false);

  /// «این دو یک حساب‌اند»: تراکنش‌های [hint.merge] هویتِ [hint.keep] را می‌گیرند و
  /// پیامک‌های بعدیِ آن کارت/حساب هم به همین حساب می‌روند.
  Future<void> mergeAccounts(SplitAccountHint hint) async {
    final target = AccountIdentity.of(hint.keep.sample);
    final from = AccountIdentity.of(hint.merge.sample);
    if (hint.merge.hasId) {
      final aliases = AccountIdentity.decodeMap(
          await repository.getSetting(SettingKeys.accountAliases))
        ..[from.key] = target;
      await repository.setSetting(
          SettingKeys.accountAliases, AccountIdentity.encodeMap(aliases));
    }
    await repository.applyPatches([
      for (final l in hint.merge.links)
        if (canEdit(l.tx)) TxPatch(l.tx.id, set: target.columns),
    ]);
    await _changed();
  }

  /// ثبتِ دستیِ مبلغی که مانده‌ی بانک نشان می‌دهد ولی پیامکش نیست ([diffRial]:
  /// منفی = برداشت، مثبت = واریز)، کمی پیش از [before] و روی همان حساب.
  Future<void> addMissingBefore(TransactionRecord before, int diffRial) async {
    await repository.addManual(
      kind: diffRial < 0 ? 'expense' : 'income',
      amountRial: diffRial.abs(),
      at: before.effectiveTime.subtract(const Duration(minutes: 1)),
      description: 'ثبت دستی: مانده‌ی بانک نشان می‌داد، پیامکش نبود',
      bankId: before.bankId,
      cardLast4: before.cardLast4,
      accountRef: before.accountRef,
    );
    await _changed();
  }

  /// «این تراکنش است؛ ثبت کن» برای پیامکی که قانون ردش کرده (مثلاً بانکی که شماره‌ی
  /// حساب نمی‌فرستد). تعمیرِ خودکار دیگر حذفش نمی‌کند.
  Future<void> saveAnyway(SmsDiagnosis d) async {
    final outcome =
        await repository.saveParsed(d.parsed, sender: d.sender, receivedAt: d.at);
    final kept = await _kept()..add(outcome.id);
    await repository.setSetting(SettingKeys.keptTransactions, jsonEncode(kept.toList()));
    await _changed();
  }

  /// واردکردنِ پیامک‌هایی که تراکنش‌اند ولی ثبت نشده‌اند.
  Future<int> importMissing(List<RawSms> messages) async {
    final importer = SmsImporter(repository,
        parser: parser, deviceId: await repository.getSetting(SettingKeys.deviceId));
    final created = (await importer.importAll(messages)).created;
    await _changed();
    return created;
  }

  /// گزارشِ عیب‌یابیِ متنی (شماره‌ی کارت/حساب پوشانده) برای کپی.
  String diagnosticReportText({SmsDiagnosisReport? sms, String? appVersion}) =>
      buildDiagnosticReport(
        balance: balanceBreakdown(),
        chains: balanceChains(),
        sms: sms,
        now: now,
        scope: person,
        appVersion: appVersion,
        repair: lastRepair,
      );

  /// گزارشِ به‌تفکیکِ کارت: هر کارت با موجودیِ واقعی و درآمد/هزینهٔ [p].
  /// (شخصِ انتخاب‌شده اعمال می‌شود؛ کارت‌ها بر اساسِ موجودی مرتب می‌شوند.)
  List<CardReport> cardReports([Period? p]) {
    final range = p ?? period;
    final scoped =
        _scopedAll.where((t) => !t.isDeleted).toList();
    final byCard = <String, List<TransactionRecord>>{};
    for (final t in scoped) {
      byCard.putIfAbsent(cardKeyOf(t), () => []).add(t);
    }
    final asOf = range.isAll
        ? null
        : range.to?.subtract(const Duration(microseconds: 1));
    final reports = <CardReport>[];
    byCard.forEach((key, items) {
      final periodItems = range.isAll
          ? items
          : items.where((t) => range.contains(t.effectiveTime)).toList();
      final s = FinanceSummary.of(periodItems);
      final hasBalance = items.any((t) => t.balanceAfterRial != null);
      reports.add(CardReport(
        key: key,
        title: cardTitleOf(items.first),
        owner: personOf(items.first),
        details: cardDetailsOf(items.first),
        balanceRial: hasBalance ? realBalanceRial(items, asOf: asOf) : null,
        incomeRial: s.incomeRial,
        expenseRial: s.expenseRial,
        items: periodItems..sort((a, b) => b.effectiveTime.compareTo(a.effectiveTime)),
      ));
    });
    reports.sort((a, b) =>
        (b.balanceRial ?? b.netRial).compareTo(a.balanceRial ?? a.netRial));
    return reports;
  }

  List<PersonGroup> get personGroups => groupByPerson(visible);
  List<DayGroup> get dayGroups => groupByDay(visible);
  int get needsReviewCount => reviewItems.length;
  int get uncategorizedCount => uncategorized.length;
  bool get selectionMode => selected.isNotEmpty;

  /// فیلترهای برگه‌ی «فیلتر» (شخص جداگانه بالای صفحه انتخاب می‌شود).
  bool get hasActiveFilters => kind != KindFilter.all || search.trim().isNotEmpty;

  /// تا فرستنده‌ی مجازی تعیین نشود، هیچ پیامکی خودکار ثبت نمی‌شود.
  bool get needsSenderSetup => allowedSenders.isEmpty;

  /// مدیر خانواده (یا نقشِ نامعلوم)؛ عضو عادی فقط تراکنش‌های خودش را دارد و جمعِ
  /// خانواده را از «داشبورد خانواده» می‌بیند.
  bool get isManager => myRole != 'member';

  /// همه‌ی افرادی که تراکنش دارند (برای انتخاب شخص؛ «نامشخص» آخر).
  List<String> get people {
    final names = {for (final t in _byId.values) personOf(t)}.toList()
      ..sort((a, b) {
        if (a == kUnknownPerson) return 1;
        if (b == kUnknownPerson) return -1;
        return a.compareTo(b);
      });
    return names;
  }

  List<TransactionRecord> get selectedRecords =>
      [for (final id in selected) if (_byId[id] != null) _byId[id]!];

  void _invalidate() => _visibleCache = null;

  Future<void> load() async {
    if (!_loadedOnce) {
      loading = true;
      notifyListeners();
    }
    meUserId = await repository.getSetting(SettingKeys.meUserId);
    meName = await repository.getSetting(SettingKeys.meName);
    myRole = await repository.getSetting(SettingKeys.myRole);
    members = FamilyMember.decodeList(
        await repository.getSetting(SettingKeys.familyMembers));
    categorizeFrom = await repository.categorizeFrom();
    showSmsText = await repository.getSetting(SettingKeys.showSmsText) != '0';

    final all = await repository.getAll();
    _byId = {for (final t in all) t.id: t};
    periodItems = period.isAll
        ? all
        : all.where((t) => period.contains(t.effectiveTime)).toList();
    reviewItems = all.where((t) => t.needsReview && canEdit(t)).toList();
    uncategorized = await repository.uncategorized(limit: 500);
    wallets = await repository.wallets();
    deletedSms = await repository.deletedSmsTransactions();
    lastRepair = _decodeRepair(await repository.getSetting(SettingKeys.repairResult));
    allowedSenders = await repository.allowedSenders();
    balanceGaps = const ReconciliationService()
        .findGaps(all, dismissed: await _dismissedGaps());
    duplicateGroups = const DuplicateFinder()
        .find(all, dismissed: await _dismissedDuplicates());
    transferPairs = const TransferFinder()
        .find(all, dismissed: await _dismissedTransfers());
    syncStatus = await SyncStatusInfo.load(repository);
    selected.removeWhere((id) => !_byId.containsKey(id));

    _invalidate();
    loading = false;
    _loadedOnce = true;
    notifyListeners();
  }

  Future<void> refreshSyncStatus() async {
    syncStatus = await SyncStatusInfo.load(repository);
    notifyListeners();
  }

  Future<void> _changed() async {
    await load();
    onLocalChange?.call();
  }

  // ---------------------------------------------------------------------------
  // نمایش
  // ---------------------------------------------------------------------------

  Future<void> setPeriod(Period p) async {
    period = p;
    selected.clear();
    await load();
  }

  void setSort(TxSort s) {
    sort = s;
    _invalidate();
    notifyListeners();
  }

  void setKind(KindFilter k) {
    kind = k;
    _invalidate();
    notifyListeners();
  }

  void setPerson(String? p) {
    person = p;
    _invalidate();
    notifyListeners();
  }

  void setSearch(String q) {
    search = q;
    _invalidate();
    notifyListeners();
  }

  void setView(HomeView v) {
    view = v;
    _invalidate();
    notifyListeners();
  }

  void clearFilters() {
    kind = KindFilter.all;
    person = null;
    search = '';
    _invalidate();
    notifyListeners();
  }

  Future<void> setShowSmsText(bool value) async {
    showSmsText = value;
    notifyListeners();
    await repository.setSetting(SettingKeys.showSmsText, value ? '1' : '0');
  }

  // ---------------------------------------------------------------------------
  // مالکیت: فقط صاحب کارت ویرایش/دسته‌بندی می‌کند؛ بقیه فقط می‌بینند.
  // ---------------------------------------------------------------------------

  bool canEdit(TransactionRecord t) =>
      t.ownerUserId == null || meUserId == null || t.ownerUserId == meUserId;

  String? memberName(String? userId) {
    if (userId == null) return null;
    for (final m in members) {
      if (m.id == userId) return m.name;
    }
    return userId == meUserId ? meName : null;
  }

  /// نام کسی که اجازه‌ی ویرایش این تراکنش را دارد.
  String editorName(TransactionRecord t) =>
      memberName(t.ownerUserId) ?? t.ownerName ?? 'صاحب کارت';

  TransactionRecord? cachedById(String id) => _byId[id];

  /// همه‌ی تراکنش‌های یک بازه (برای گزارش).
  List<TransactionRecord> itemsIn(Period p) =>
      _byId.values.where((t) => p.contains(t.effectiveTime)).toList();

  // ---------------------------------------------------------------------------
  // انتخاب چندتایی
  // ---------------------------------------------------------------------------

  bool isSelected(String id) => selected.contains(id);

  /// false یعنی اجازه نداری (تراکنش مال عضو دیگر است).
  bool toggleSelect(TransactionRecord t) {
    if (!canEdit(t)) return false;
    if (!selected.remove(t.id)) selected.add(t.id);
    notifyListeners();
    return true;
  }

  void selectAllVisible() {
    selected
      ..clear()
      ..addAll(visible.where(canEdit).map((t) => t.id));
    notifyListeners();
  }

  void clearSelection() {
    if (selected.isEmpty) return;
    selected.clear();
    notifyListeners();
  }

  Future<void> deleteSelected() async {
    final ids = selected.toList();
    selected.clear();
    for (final id in ids) {
      await repository.deleteTransaction(id);
    }
    await _changed();
  }

  /// حذف (نامعتبر) گروهی؛ فقط تراکنش‌هایی که اجازه‌اش را داری. تعداد حذف‌شده.
  Future<int> invalidateMany(Iterable<TransactionRecord> records) async {
    var n = 0;
    for (final t in records) {
      if (t.isDeleted || !canEdit(t)) continue;
      await repository.deleteTransaction(t.id);
      selected.remove(t.id);
      n++;
    }
    if (n > 0) await _changed();
    return n;
  }

  Future<void> categorizeMany(
    List<String> ids,
    List<String> categoryIds, {
    String? description,
  }) async {
    for (final id in ids) {
      await repository.categorize(id, categoryIds, description: description);
    }
    selected.removeAll(ids);
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // عملیات روی یک تراکنش
  // ---------------------------------------------------------------------------

  Future<TransactionRecord?> transactionById(String id) => repository.getById(id);

  Future<List<Category>> categories() => repository.categories();

  Future<List<CategoryTotal>> categoryTotals({DateTime? from, DateTime? to}) =>
      repository.categoryTotals(from: from, to: to);

  Future<void> categorize(
    String transactionId,
    List<String> categoryIds, {
    String? description,
  }) =>
      categorizeMany([transactionId], categoryIds, description: description);

  Future<void> updateTransaction(
    String id, {
    String? kind,
    int? amountRial,
    String? counterparty,
    String? description,
    bool? needsReview,
  }) async {
    await repository.updateTransaction(
      id,
      kind: kind,
      amountRial: amountRial,
      counterparty: counterparty,
      description: description,
      needsReview: needsReview,
    );
    await _changed();
  }

  /// تأیید یک مورد صف بازبینی: نوع/مبلغ نهایی + پاک‌کردن پرچم بازبینی.
  Future<void> confirmReview(String id, {String? kind, int? amountRial}) =>
      updateTransaction(id, kind: kind, amountRial: amountRial, needsReview: false);

  /// «نامعتبر»: تراکنش انجام‌نشده یا پیامکِ رمزِ اشتباهی ثبت‌شده (حذف نرم).
  Future<void> deleteTransaction(String id) async {
    await repository.deleteTransaction(id);
    selected.remove(id);
    await _changed();
  }

  /// یک پیامک را پارس و ذخیره می‌کند (افزودن دستی؛ فهرست فرستنده‌های مجاز
  /// عمداً اعمال نمی‌شود چون خود کاربر پیامک را آورده).
  Future<TxInsertOutcome> addFromSms({
    required String sender,
    required String body,
  }) async {
    final parsed = parser.parse(sender: sender, body: body);
    final outcome = await repository.saveParsed(
      parsed,
      sender: sender,
      receivedAt: _clock(),
    );
    await _changed();
    return outcome;
  }

  // ---------------------------------------------------------------------------
  // کیف‌ها (کارت‌ها و حساب‌های اعضا)
  // ---------------------------------------------------------------------------

  Future<void> addWallet(Wallet wallet) async {
    await repository.addWallet(wallet);
    await _changed();
  }

  Future<void> updateWallet(Wallet wallet) async {
    await repository.updateWallet(wallet);
    await _changed();
  }

  Future<void> deleteWallet(String id) async {
    await repository.deleteWallet(id);
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // فرستنده‌های مجاز پیامک
  // ---------------------------------------------------------------------------

  /// فرستنده‌هایی که پیامکِ مبلغ‌دار داده‌اند ولی هنوز مجاز نیستند (صندوق گوشی +
  /// تراکنش‌های قبلاً ثبت‌شده).
  Future<List<SenderCandidate>> senderCandidates() async {
    var inbox = const <RawSms>[];
    try {
      inbox = await readInbox?.call() ?? const [];
    } catch (_) {
      // بدون مجوز پیامک، فقط از تراکنش‌های ثبت‌شده پیشنهاد می‌دهیم.
    }
    return findSenderCandidates(
      inbox: inbox,
      stored: _byId.values,
      allowed: allowedSenders,
      dismissed: await _dismissedSenders(),
      parser: parser,
    );
  }

  Future<Set<String>> _dismissedSenders() async {
    final raw = await repository.getSetting(SettingKeys.dismissedSenders);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  /// «بانک نیست»: فرستنده دیگر پیشنهاد نمی‌شود؛ تراکنش‌های اشتباهی‌اش (اگر باشد) حذف
  /// می‌شوند. تعداد تراکنش‌های حذف‌شده را برمی‌گرداند.
  Future<int> rejectSender(String address, Iterable<TransactionRecord> stored) async {
    final keys = await _dismissedSenders()..add(address.trim());
    await repository.setSetting(
        SettingKeys.dismissedSenders, jsonEncode(keys.toList()));
    final n = await invalidateMany(stored.where(canEdit));
    await load();
    return n;
  }

  Future<void> addAllowedSender(String address,
      {String? bankId, String? ownerName, String? ownerUserId}) async {
    await repository.addAllowedSender(address,
        bankId: bankId, ownerName: ownerName, ownerUserId: ownerUserId);
    try {
      await onSendersChanged?.call();
    } catch (_) {
      // خواندن صندوق نشد؛ پیامک‌های بعدیِ این فرستنده به‌هرحال ثبت می‌شوند.
    }
    await load();
  }

  Future<void> removeAllowedSender(String id) async {
    await repository.deleteAllowedSender(id);
    await load();
  }

  // ---------------------------------------------------------------------------
  // تطبیق مانده (پیامک جاافتاده)
  // ---------------------------------------------------------------------------

  Future<Set<String>> _dismissedGaps() async {
    final raw = await repository.getSetting(SettingKeys.dismissedGaps);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  // ---------------------------------------------------------------------------
  // تراکنش‌های تکراری (یک رخداد که دوبار ثبت شده)
  // ---------------------------------------------------------------------------

  Future<Set<String>> _dismissedDuplicates() async {
    final raw = await repository.getSetting(SettingKeys.dismissedDuplicates);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  /// «تکراری نیست»: این گروه دیگر پیشنهاد نشود.
  Future<void> dismissDuplicate(DuplicateGroup group) async {
    final keys = await _dismissedDuplicates()..add(group.key);
    await repository.setSetting(
        SettingKeys.dismissedDuplicates, jsonEncode(keys.toList()));
    await load();
  }

  // ---------------------------------------------------------------------------
  // انتقال بین کارت‌ها (برداشت از یکی + واریزِ هم‌مبلغ به دیگری)
  // ---------------------------------------------------------------------------

  Future<Set<String>> _dismissedTransfers() async {
    final raw = await repository.getSetting(SettingKeys.dismissedTransfers);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  /// تأیید انتقال: هر دو طرف به نوعِ «انتقال» تبدیل می‌شوند تا از خالص بیرون بروند.
  Future<void> confirmTransfer(TransferPair pair) async {
    if (canEdit(pair.out)) {
      await repository.updateTransaction(pair.out.id, kind: 'transfer');
    }
    if (canEdit(pair.inn)) {
      await repository.updateTransaction(pair.inn.id, kind: 'transfer');
    }
    await _changed();
  }

  /// «انتقال نیست»: این جفت دیگر پیشنهاد نشود.
  Future<void> dismissTransfer(TransferPair pair) async {
    final keys = await _dismissedTransfers()..add(pair.key);
    await repository.setSetting(
        SettingKeys.dismissedTransfers, jsonEncode(keys.toList()));
    await load();
  }

  /// افزودنِ عضو فقط برای مدیرِ خانواده (بدون سقفِ تعداد).
  bool get canAddMember => familyApi != null && isManager;

  // --- انتسابِ دستیِ کارت (برای چند حساب در یک بانک) ---

  /// کیف‌هایی که می‌شود این تراکنش را به آن‌ها نسبت داد (اولویت با هم‌بانک).
  List<Wallet> assignableWallets(TransactionRecord t) {
    if (wallets.isEmpty) return const [];
    final bank = t.bankId;
    final sameBank = [
      for (final w in wallets)
        if (bank != null && bank.isNotEmpty && w.bankId == bank) w
    ];
    return sameBank.isNotEmpty ? sameBank : List.of(wallets);
  }

  Future<void> assignWallet(TransactionRecord t, Wallet wallet) async {
    if (!canEdit(t)) return;
    await repository.assignWalletToTransaction(t.id, wallet);
    await _changed();
  }

  Future<void> clearWalletPin(TransactionRecord t) async {
    if (!canEdit(t)) return;
    await repository.clearWalletPin(t.id);
    await _changed();
  }

  // --- بودجه‌ها -------------------------------------------------------------

  /// بودجه‌ها همراهِ مصرفِ همین ماهِ شمسی (پرمصرف‌ترها اول).
  Future<List<BudgetUsage>> budgetUsages() {
    final month = Period.containing(now);
    return repository.budgetUsage(from: month.from, to: month.to);
  }

  Future<List<Budget>> budgets() => repository.budgets();

  Future<void> saveBudget(
      {String? id, required String categoryName, required int limitRial}) async {
    if (id == null) {
      await repository
          .addBudget(Budget(id: '', categoryName: categoryName, limitRial: limitRial));
    } else {
      await repository.updateBudget(
          Budget(id: id, categoryName: categoryName, limitRial: limitRial));
    }
    onLocalChange?.call();
    notifyListeners();
  }

  Future<void> deleteBudget(String id) async {
    await repository.deleteBudget(id);
    onLocalChange?.call();
    notifyListeners();
  }

  /// افزودنِ عضوِ تازه توسطِ مدیر؛ در صورت خطا پیام فارسی برمی‌گرداند، وگرنه null.
  Future<String?> addMember({
    required String phone,
    required String password,
    String? fullName,
  }) async {
    final api = familyApi;
    if (api == null) return 'افزودن عضو در این حالت ممکن نیست';
    try {
      await api.addMember(phone: phone, password: password, fullName: fullName);
      // فهرست اعضا را تازه کن
      final fresh = await api.members();
      members = fresh;
      await repository.setSetting(
          SettingKeys.familyMembers, FamilyMember.encodeList(fresh));
      notifyListeners();
      return null;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        for (final f in const ['phone', 'password', 'detail', 'non_field_errors']) {
          final v = data[f];
          if (v is List && v.isNotEmpty) return v.first.toString();
          if (v is String) return v;
        }
      }
      if (e.response?.statusCode == 403) return 'فقط مدیرِ خانواده می‌تواند عضو اضافه کند';
      return 'خطا در افزودن عضو';
    } catch (_) {
      return 'خطا در افزودن عضو';
    }
  }

  /// حذفِ تکراری‌ها: قدیمی‌ترین می‌ماند، بقیه حذف (نامعتبر) می‌شوند.
  Future<void> resolveDuplicate(DuplicateGroup group) async {
    for (final t in group.extras) {
      if (canEdit(t)) await repository.deleteTransaction(t.id);
    }
    await _changed();
  }

  Future<void> dismissGap(BalanceGap gap) async {
    final keys = await _dismissedGaps()
      ..add(gap.key);
    await repository.setSetting(SettingKeys.dismissedGaps, jsonEncode(keys.toList()));
    await load();
  }

  /// ثبت دستی تراکنشی که پیامکش نرسیده (همان مبلغ اختلاف مانده).
  Future<void> addMissingFromGap(BalanceGap gap) async {
    await repository.addManual(
      kind: gap.missingAmountRial < 0 ? 'expense' : 'income',
      amountRial: gap.missingAmountRial.abs(),
      at: gap.estimatedAt,
      description: 'ثبت دستی: پیامکش نرسیده بود',
      bankId: gap.bankId,
      cardLast4: gap.cardLast4,
      accountRef: gap.accountRef,
    );
    await _changed();
  }

  // ---------------------------------------------------------------------------
  // تنظیمات
  // ---------------------------------------------------------------------------

  /// تراکنش‌های قبل از این لحظه وارد صف دسته‌بندی نمی‌شوند.
  Future<void> setCategorizeFrom(DateTime from) async {
    await repository.setSetting(
        SettingKeys.categorizeFrom, from.toUtc().toIso8601String());
    await load();
  }
}
