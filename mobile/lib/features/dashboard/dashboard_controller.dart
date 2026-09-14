/// کنترلر صفحه‌ی اصلی: بازه، مرتب‌سازی، فیلترها، انتخاب چندتایی و همه‌ی عملیات
/// روی تراکنش‌ها (با رعایت اینکه فقط صاحب کارت ویرایش می‌کند).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;

import '../../core/family/family_api.dart';
import '../../core/dedup/duplicate_finder.dart';
import '../../core/reconcile/reconciliation.dart';
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

  /// بعد از مجاز کردن فرستنده‌ی تازه: خواندن دوباره‌ی صندوق، تا پیامک‌های قبلیِ
  /// همان فرستنده هم ثبت شوند.
  Future<void> Function()? onSendersChanged;

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
  List<Wallet> wallets = const [];
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
    allowedSenders = await repository.allowedSenders();
    balanceGaps = const ReconciliationService()
        .findGaps(all, dismissed: await _dismissedGaps());
    duplicateGroups = const DuplicateFinder()
        .find(all, dismissed: await _dismissedDuplicates());
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
      parser: parser,
    );
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
