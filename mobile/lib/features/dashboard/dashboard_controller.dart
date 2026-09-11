/// کنترلر صفحه‌ی اصلی: بازه، مرتب‌سازی، فیلترها، انتخاب چندتایی و همه‌ی عملیات
/// روی تراکنش‌ها (با رعایت اینکه فقط صاحب کارت ویرایش می‌کند).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;

import '../../core/family/family_api.dart';
import '../../core/reconcile/reconciliation.dart';
import '../../core/sms/sms_parser.dart';
import '../../core/sync/sync_service.dart';
import '../categories/data/category.dart';
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

  DashboardController(
    this.repository, {
    this.parser = const SmsParser(),
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        period = Period.containing((clock ?? DateTime.now)());

  bool loading = true;
  bool _loadedOnce = false;

  /// اکنون (قابل تزریق برای تست).
  DateTime get now => _clock();

  // --- تنظیمات نمایش ---
  Period period;
  TxSort sort = TxSort.newest;
  KindFilter kind = KindFilter.all;

  /// فیلتر شخص (فقط در نمای «همه»).
  String? person;
  String search = '';
  HomeView view = HomeView.people;

  // --- داده ---
  List<TransactionRecord> periodItems = const [];
  List<TransactionRecord> reviewItems = const [];
  List<TransactionRecord> uncategorized = const [];
  List<BalanceGap> balanceGaps = const [];
  List<Wallet> wallets = const [];
  List<FamilyMember> members = const [];
  String? meUserId;
  String? meName;
  DateTime? categorizeFrom;
  SyncStatusInfo syncStatus = const SyncStatusInfo();
  Map<String, TransactionRecord> _byId = const {};

  /// شناسه‌ی تراکنش‌های انتخاب‌شده (انتخاب چندتایی).
  final Set<String> selected = {};

  List<TransactionRecord>? _visibleCache;

  /// تراکنش‌های بازه پس از فیلتر و مرتب‌سازی (همان چیزی که دیده می‌شود و جمع می‌خورد).
  List<TransactionRecord> get visible => _visibleCache ??= applyQuery(
        periodItems,
        sort: sort,
        kind: kind,
        person: view == HomeView.all ? person : null,
        search: search,
      );

  /// سازگاری با صفحه‌های قدیمی/تست‌ها.
  List<TransactionRecord> get transactions => visible;

  FinanceSummary get summary => FinanceSummary.of(visible);
  List<PersonGroup> get personGroups => groupByPerson(visible);
  List<DayGroup> get dayGroups => groupByDay(visible);
  int get needsReviewCount => reviewItems.length;
  int get uncategorizedCount => uncategorized.length;
  bool get selectionMode => selected.isNotEmpty;

  bool get hasActiveFilters =>
      kind != KindFilter.all ||
      (view == HomeView.all && person != null) ||
      search.trim().isNotEmpty;

  /// افرادی که در این بازه تراکنش دارند (برای فیلتر).
  List<String> get people {
    final names = {for (final t in periodItems) personOf(t)}.toList()
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
    members = FamilyMember.decodeList(
        await repository.getSetting(SettingKeys.familyMembers));
    categorizeFrom = await repository.categorizeFrom();

    final all = await repository.getAll();
    _byId = {for (final t in all) t.id: t};
    periodItems = period.isAll
        ? all
        : all.where((t) => period.contains(t.effectiveTime)).toList();
    reviewItems = all.where((t) => t.needsReview && canEdit(t)).toList();
    uncategorized = await repository.uncategorized(limit: 500);
    wallets = await repository.wallets();
    balanceGaps = const ReconciliationService()
        .findGaps(all, dismissed: await _dismissedGaps());
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

  /// یک پیامک را پارس و ذخیره می‌کند (افزودن دستی).
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
