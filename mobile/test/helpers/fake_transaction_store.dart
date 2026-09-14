/// مخزن جعلی in-memory برای تست‌های ویجت (بدون I/O بومی، سازگار با FakeAsync).
/// همان قاعده‌های TransactionRepository را (ساده‌شده) پیاده می‌کند.
library;

import 'package:economy/core/sms/models.dart';
import 'package:economy/core/sms/sms_fingerprint.dart';
import 'package:economy/features/budgets/data/budget.dart';
import 'package:economy/features/categories/data/category.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/wallets/data/wallet.dart';

class FakeTransactionStore implements TransactionStore {
  final List<TransactionRecord> _items = [];
  int _seq = 0;
  final DateTime Function() clock;

  final List<Category> _categories = const [
    Category(id: 'c1', name: 'سبزیجات', isSystem: true),
    Category(id: 'c2', name: 'میوه', isSystem: true),
    Category(id: 'c3', name: 'گوشت', isSystem: true),
    Category(id: 'c4', name: 'سایر', isSystem: true),
  ];

  // transactionId -> (categoryId -> amount)
  final Map<String, Map<String, int>> _allocations = {};

  final List<Wallet> _wallets = [];
  int _walletSeq = 0;

  final List<AllowedSender> _senders = [];
  int _senderSeq = 0;

  final Map<String, String> settings = {};

  /// پیش‌فرض تست‌ها: شروع دسته‌بندی در گذشته (همه‌چیز قابل دسته‌بندی).
  FakeTransactionStore({DateTime Function()? clock, DateTime? categorizeFrom})
      : clock = clock ?? DateTime.now {
    settings[SettingKeys.categorizeFrom] =
        (categorizeFrom ?? DateTime.utc(2000)).toIso8601String();
  }

  String? get _me => settings[SettingKeys.meUserId];

  /// افزودن همگام برای آماده‌سازی داده‌ی تست (بدون await).
  void seed(ParsedTransaction parsed, {required String sender, DateTime? receivedAt}) {
    _put(parsed, sender: sender, receivedAt: receivedAt);
  }

  /// افزودن مستقیم یک رکورد ساخته‌شده (برای تست‌هایی که به فیلدهای دقیق نیاز دارند).
  void addRecord(TransactionRecord record) => _items.add(record);

  int get _nextSeq => _seq++;

  ({String? ownerUserId, String? ownerName, String? walletLabel}) _attribution({
    String? sender,
    String? cardLast4,
    String? accountRef,
    String? bankId,
  }) {
    if (sender != null && sender.isNotEmpty) {
      final s = findAllowedSender(_senders, sender);
      if (s != null && s.hasOwner) {
        final w = walletFor(_wallets,
            cardLast4: cardLast4, accountRef: accountRef, bankId: bankId);
        return (ownerUserId: s.ownerUserId ?? _me, ownerName: s.ownerName, walletLabel: w?.label);
      }
    }
    final w = walletFor(_wallets,
        cardLast4: cardLast4, accountRef: accountRef, bankId: bankId);
    if (w == null) return (ownerUserId: _me, ownerName: null, walletLabel: null);
    return (ownerUserId: w.ownerUserId ?? _me, ownerName: w.ownerName, walletLabel: w.label);
  }

  TxInsertOutcome _put(
    ParsedTransaction parsed, {
    required String sender,
    DateTime? receivedAt,
  }) {
    final hasBody = parsed.rawBody.trim().isNotEmpty;
    final hash = hasBody
        ? smsFingerprint(sender: sender, body: parsed.rawBody, receivedAt: receivedAt)
        : null;
    final content = hasBody ? smsContentHash(sender: sender, body: parsed.rawBody) : null;
    for (final item in _items) {
      if (hash != null && item.sourceMessageHash == hash) {
        return TxInsertOutcome(TxInsertStatus.duplicate, item.id);
      }
      if (content != null &&
          receivedAt != null &&
          item.smsContentHash == content &&
          item.smsReceivedAt != null &&
          item.smsReceivedAt!.difference(receivedAt.toUtc()).abs() <=
              kContentDedupWindow) {
        return TxInsertOutcome(TxInsertStatus.duplicate, item.id);
      }
    }
    final a = _attribution(
      sender: sender,
      cardLast4: parsed.cardLast4,
      accountRef: parsed.accountRef,
      bankId: parsed.bankId,
    );
    final now = clock().toUtc();
    final id = 'fake-$_nextSeq';
    _items.add(TransactionRecord.fromParsed(
      parsed,
      id: id,
      now: now,
      sourceMessageHash: hash,
      smsReceivedAt: receivedAt,
      smsContentHash: content,
      ownerUserId: a.ownerUserId,
      ownerName: a.ownerName,
      walletLabel: a.walletLabel,
    ));
    return TxInsertOutcome(TxInsertStatus.created, id);
  }

  TransactionRecord _withAlloc(TransactionRecord t) {
    final alloc = _allocations[t.id];
    if (alloc == null) return t;
    final names = {for (final c in _categories) c.id: c.name};
    return t.copyWith(allocations: [
      for (final e in alloc.entries) Allocation(names[e.key] ?? e.key, e.value),
    ]);
  }

  bool _inRange(TransactionRecord t, DateTime? from, DateTime? to) {
    final at = t.effectiveTime.toUtc();
    if (from != null && at.isBefore(from.toUtc())) return false;
    if (to != null && !at.isBefore(to.toUtc())) return false;
    return true;
  }

  List<TransactionRecord> _sortedLive() {
    final indexed = [
      for (var i = 0; i < _items.length; i++)
        if (!_items[i].isDeleted) (i, _items[i]),
    ];
    indexed.sort((a, b) {
      final c = b.$2.effectiveTime.compareTo(a.$2.effectiveTime);
      return c != 0 ? c : b.$1.compareTo(a.$1); // جدیدترِ ثبت‌شده اول
    });
    return [for (final e in indexed) _withAlloc(e.$2)];
  }

  @override
  Future<TxInsertOutcome> saveParsed(
    ParsedTransaction parsed, {
    required String sender,
    String? deviceId,
    DateTime? receivedAt,
  }) async {
    return _put(parsed, sender: sender, receivedAt: receivedAt);
  }

  @override
  Future<String> addManual({
    required String kind,
    required int amountRial,
    required DateTime at,
    String? description,
    String? bankId,
    String? cardLast4,
    String? accountRef,
  }) async {
    final now = clock().toUtc();
    final a = _attribution(cardLast4: cardLast4, accountRef: accountRef, bankId: bankId);
    final id = 'manual-$_nextSeq';
    _items.add(TransactionRecord(
      id: id,
      kind: kind,
      amountRial: amountRial,
      transactionDate: at.toUtc(),
      clientCreatedAt: now,
      createdAt: now,
      updatedAt: now,
      source: 'manual',
      description: description,
      bankId: bankId,
      cardLast4: cardLast4,
      accountRef: accountRef,
      ownerUserId: a.ownerUserId,
      ownerName: a.ownerName,
      walletLabel: a.walletLabel,
    ));
    return id;
  }

  @override
  Future<List<TransactionRecord>> getAll({
    int? limit,
    String? kind,
    bool? needsReview,
    String? search,
    DateTime? from,
    DateTime? to,
  }) async {
    var items = _sortedLive().where((t) => _inRange(t, from, to)).toList();
    if (kind != null) items = items.where((t) => t.kind == kind).toList();
    if (needsReview != null) {
      items = items.where((t) => t.needsReview == needsReview).toList();
    }
    if (search != null && search.trim().isNotEmpty) {
      final q = search.trim();
      items = items
          .where((t) =>
              (t.counterparty?.contains(q) ?? false) ||
              (t.description?.contains(q) ?? false) ||
              (t.bankId?.contains(q) ?? false) ||
              (t.ownerName?.contains(q) ?? false))
          .toList();
    }
    return limit == null ? items : items.take(limit).toList();
  }

  @override
  Future<int> needsReviewCount() async => _items
      .where((t) =>
          t.needsReview &&
          !t.isDeleted &&
          (_me == null || t.ownerUserId == null || t.ownerUserId == _me))
      .length;

  int _indexOf(String id) => _items.indexWhere((t) => t.id == id);

  @override
  Future<void> updateTransaction(
    String id, {
    String? kind,
    int? amountRial,
    String? counterparty,
    String? description,
    bool? needsReview,
  }) async {
    final index = _indexOf(id);
    if (index == -1) return;
    _items[index] = _items[index].copyWith(
      kind: kind,
      amountRial: amountRial,
      counterparty: counterparty,
      description: description,
      needsReview: needsReview,
      reviewReasons: needsReview == false ? const [] : null,
      updatedAt: clock().toUtc(),
    );
  }

  @override
  Future<void> deleteTransaction(String id) async {
    final index = _indexOf(id);
    if (index == -1) return;
    _items[index] = _items[index].copyWith(deletedAt: clock().toUtc());
  }

  @override
  Future<TransactionRecord?> getById(String id) async {
    final index = _indexOf(id);
    return index == -1 ? null : _withAlloc(_items[index]);
  }

  @override
  Future<List<Wallet>> wallets() async => List.of(_wallets);

  @override
  Future<void> addWallet(Wallet wallet) async {
    _wallets.add(Wallet(
      id: 'w${_walletSeq++}',
      ownerName: wallet.ownerName,
      ownerUserId: wallet.ownerUserId,
      label: wallet.label,
      bankId: wallet.bankId,
      cardLast4: wallet.cardLast4,
      accountRef: wallet.accountRef,
    ));
    await reattributeLocal();
  }

  @override
  Future<void> updateWallet(Wallet wallet) async {
    final i = _wallets.indexWhere((w) => w.id == wallet.id);
    if (i != -1) _wallets[i] = wallet;
    await reattributeLocal();
  }

  @override
  Future<void> deleteWallet(String id) async {
    _wallets.removeWhere((w) => w.id == id);
    await reattributeLocal();
  }

  @override
  Future<List<Map<String, Object?>>> pendingWallets() async => const [];

  @override
  Future<void> markWalletSynced(String id) async {}

  final List<Budget> _budgets = [];
  int _budgetSeq = 1;

  @override
  Future<List<Budget>> budgets() async => List.of(_budgets);

  @override
  Future<void> addBudget(Budget budget) async {
    _budgets.add(Budget(
      id: 'b${_budgetSeq++}',
      categoryName: budget.categoryName,
      limitRial: budget.limitRial,
      period: budget.period,
    ));
  }

  @override
  Future<void> updateBudget(Budget budget) async {
    final i = _budgets.indexWhere((b) => b.id == budget.id);
    if (i != -1) _budgets[i] = budget;
  }

  @override
  Future<void> deleteBudget(String id) async {
    _budgets.removeWhere((b) => b.id == id);
  }

  @override
  Future<List<BudgetUsage>> budgetUsage({DateTime? from, DateTime? to}) async {
    final totals = await categoryTotals(from: from, to: to);
    final spent = <String, int>{};
    for (final t in totals) {
      spent[t.name] = (spent[t.name] ?? 0) + t.amountRial;
    }
    return [
      for (final b in _budgets)
        BudgetUsage(budget: b, spentRial: spent[b.categoryName] ?? 0),
    ];
  }

  @override
  Future<List<Map<String, Object?>>> pendingBudgets() async => const [];

  @override
  Future<void> markBudgetSynced(String id) async {}

  @override
  Future<void> applyRemoteBudget(Map<String, dynamic> j) async {
    if (j['is_deleted'] == true) {
      _budgets.removeWhere((b) => b.id == j['id'].toString());
      return;
    }
    final b = Budget(
      id: j['id'].toString(),
      categoryName: (j['category_name'] ?? '').toString(),
      period: (j['period'] ?? 'monthly').toString(),
      limitRial: (j['limit_rial'] as num?)?.toInt() ?? 0,
    );
    final i = _budgets.indexWhere((e) => e.id == b.id);
    if (i == -1) {
      _budgets.add(b);
    } else {
      _budgets[i] = b;
    }
  }

  @override
  Future<void> applyRemoteWallet(Map<String, dynamic> j) async {
    if (j['is_deleted'] == true) {
      _wallets.removeWhere((w) => w.id == j['id'].toString());
      return;
    }
    final w = Wallet(
      id: j['id'].toString(),
      ownerName: (j['owner_name'] ?? '').toString(),
      ownerUserId: (j['owner_user_id'] as String?),
      label: (j['label'] ?? '').toString(),
      bankId: j['bank_id'] as String?,
      cardLast4: j['card_last4'] as String?,
      accountRef: j['account_ref'] as String?,
    );
    final i = _wallets.indexWhere((e) => e.id == w.id);
    if (i == -1) {
      _wallets.add(w);
    } else {
      _wallets[i] = w;
    }
    await reattributeLocal();
  }

  @override
  Future<List<AllowedSender>> allowedSenders() async => List.of(_senders);

  @override
  Future<AllowedSender> addAllowedSender(String address,
      {String? bankId, String? ownerName, String? ownerUserId}) async {
    final existing = findAllowedSender(_senders, address);
    if (existing != null) return existing;
    final sender = AllowedSender(
      id: 's${_senderSeq++}',
      address: address.trim(),
      bankId: bankId,
      ownerName: ownerName,
      ownerUserId: ownerUserId,
    );
    _senders.add(sender);
    if (bankId != null) {
      // پیامک‌های قبلیِ بی‌بانکِ همین فرستنده، بانکِ فرستنده را می‌گیرند.
      for (var i = 0; i < _items.length; i++) {
        final t = _items[i];
        if (t.isRemote || t.bankId != null || t.smsSender == null) continue;
        if (sender.matches(t.smsSender!)) _items[i] = t.copyWith(bankId: bankId);
      }
    }
    await reattributeLocal();
    return sender;
  }

  @override
  Future<void> deleteAllowedSender(String id) async =>
      _senders.removeWhere((s) => s.id == id);

  @override
  Future<void> reattributeLocal() async {
    for (var i = 0; i < _items.length; i++) {
      final t = _items[i];
      if (t.isRemote || t.isDeleted) continue;
      final a = _attribution(
          sender: t.smsSender,
          cardLast4: t.cardLast4,
          accountRef: t.accountRef,
          bankId: t.bankId);
      _items[i] = t.copyWith(
        ownerUserId: a.ownerUserId,
        ownerName: a.ownerName,
        clearOwnerName: a.ownerName == null,
        walletLabel: a.walletLabel,
        clearWalletLabel: a.walletLabel == null,
      );
    }
  }

  @override
  Future<void> switchAccount({
    required String previousUserId,
    required String userId,
    required String userName,
    Set<String>? memberIds,
  }) async {
    _items.removeWhere((t) => t.isRemote);
    for (var i = 0; i < _wallets.length; i++) {
      final w = _wallets[i];
      if (w.ownerUserId == previousUserId) {
        _wallets[i] = w.copyWith(ownerUserId: userId, ownerName: userName);
      } else if (memberIds != null &&
          w.ownerUserId != null &&
          !{...memberIds, userId}.contains(w.ownerUserId)) {
        _wallets[i] = w.copyWith(clearOwnerUserId: true);
      }
    }
    settings
      ..remove(SettingKeys.pullCursor)
      ..remove(SettingKeys.lastSync);
  }

  @override
  Future<void> purgeRemoteNotOwnedBy(String meUserId) async {
    _items.removeWhere((t) => t.isRemote && t.ownerUserId != meUserId);
  }

  @override
  Future<int> pendingSyncCount() async => 0;

  @override
  Future<List<Category>> categories() async => List.of(_categories);

  @override
  Future<void> categorize(
    String transactionId,
    List<String> categoryIds, {
    String? description,
  }) async {
    final index = _indexOf(transactionId);
    final amount = index == -1 ? 0 : (_items[index].amountRial ?? 0);
    final n = categoryIds.length;
    _allocations.remove(transactionId);
    if (n > 0) {
      final base = amount ~/ n;
      final remainder = amount - base * n;
      final map = <String, int>{};
      for (var i = 0; i < n; i++) {
        map[categoryIds[i]] = base + (i < remainder ? 1 : 0);
      }
      _allocations[transactionId] = map;
    }
    if (index != -1) {
      _items[index] = _items[index].copyWith(
        needsReview: false,
        reviewReasons: const [],
        description: description,
        updatedAt: clock().toUtc(),
      );
    }
  }

  @override
  Future<List<CategoryTotal>> categoryTotals({DateTime? from, DateTime? to}) async {
    final totals = <String, int>{};
    for (final t in _items) {
      if (t.kind != 'expense' || t.isDeleted || !_inRange(t, from, to)) continue;
      final alloc = _allocations[t.id];
      if (alloc == null) continue;
      alloc.forEach((cid, amt) => totals[cid] = (totals[cid] ?? 0) + amt);
    }
    final byId = {for (final c in _categories) c.id: c.name};
    final list = totals.entries
        .map((e) => CategoryTotal(
              categoryId: e.key,
              name: byId[e.key] ?? e.key,
              amountRial: e.value,
            ))
        .toList()
      ..sort((a, b) => b.amountRial.compareTo(a.amountRial));
    return list;
  }

  @override
  Future<DateTime> categorizeFrom() async =>
      DateTime.parse(settings[SettingKeys.categorizeFrom]!);

  @override
  Future<List<TransactionRecord>> uncategorized({int? limit}) async {
    final from = await categorizeFrom();
    final list = _sortedLive()
        .where((t) =>
            t.amountRial != null &&
            (t.kind == 'income' || t.kind == 'expense') &&
            !t.needsReview &&
            (_me == null || t.ownerUserId == null || t.ownerUserId == _me) &&
            !t.effectiveTime.isBefore(from) &&
            !_allocations.containsKey(t.id) &&
            t.allocations.isEmpty)
        .toList();
    return limit == null ? list : list.take(limit).toList();
  }

  @override
  Future<FinanceSummary> summary({DateTime? from, DateTime? to}) async =>
      FinanceSummary.of(_sortedLive().where((t) => _inRange(t, from, to)));

  @override
  Future<String?> getSetting(String key) async => settings[key];

  @override
  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      settings.remove(key);
    } else {
      settings[key] = value;
    }
  }
}
