/// مخزن جعلی in-memory برای تست‌های ویجت (بدون I/O بومی، سازگار با FakeAsync).
library;

import 'package:economy/core/sms/models.dart';
import 'package:economy/core/sms/sms_fingerprint.dart';
import 'package:economy/features/categories/data/category.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/wallets/data/wallet.dart';

class FakeTransactionStore implements TransactionStore {
  final List<TransactionRecord> _items = [];
  int _seq = 0;

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

  /// افزودن همگام برای آماده‌سازی داده‌ی تست (بدون await).
  void seed(ParsedTransaction parsed, {required String sender, DateTime? receivedAt}) {
    _put(parsed, sender: sender, receivedAt: receivedAt);
  }

  /// افزودن مستقیم یک رکورد ساخته‌شده (برای تست‌هایی که به فیلدهای دقیق نیاز دارند).
  void addRecord(TransactionRecord record) => _items.add(record);

  TxInsertOutcome _put(
    ParsedTransaction parsed, {
    required String sender,
    DateTime? receivedAt,
  }) {
    final hash = parsed.rawBody.trim().isEmpty
        ? null
        : smsFingerprint(sender: sender, body: parsed.rawBody, receivedAt: receivedAt);
    if (hash != null) {
      for (final item in _items) {
        if (item.sourceMessageHash == hash) {
          return TxInsertOutcome(TxInsertStatus.duplicate, item.id);
        }
      }
    }
    final now = DateTime.now().toUtc();
    final id = 'fake-${_seq++}';
    _items.add(TransactionRecord.fromParsed(parsed,
        id: id, now: now, sourceMessageHash: hash));
    return TxInsertOutcome(TxInsertStatus.created, id);
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
  Future<List<TransactionRecord>> getAll({
    int? limit,
    String? kind,
    bool? needsReview,
    String? search,
  }) async {
    var items = [..._items];
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
              (t.bankId?.contains(q) ?? false))
          .toList();
    }
    items.sort((a, b) => (b.clientCreatedAt ?? b.createdAt)
        .compareTo(a.clientCreatedAt ?? a.createdAt));
    return limit == null ? items : items.take(limit).toList();
  }

  @override
  Future<int> needsReviewCount() async =>
      _items.where((t) => t.needsReview).length;

  @override
  Future<void> updateTransaction(
    String id, {
    String? kind,
    int? amountRial,
    String? counterparty,
    String? description,
    bool? needsReview,
  }) async {
    final index = _items.indexWhere((t) => t.id == id);
    if (index == -1) return;
    _items[index] = _items[index].copyWith(
      kind: kind,
      amountRial: amountRial,
      counterparty: counterparty,
      description: description,
      needsReview: needsReview,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> deleteTransaction(String id) async {
    _items.removeWhere((t) => t.id == id);
    _allocations.remove(id);
  }

  @override
  Future<TransactionRecord?> getById(String id) async {
    for (final t in _items) {
      if (t.id == id) return t;
    }
    return null;
  }

  @override
  Future<List<Wallet>> wallets() async => List.of(_wallets);

  @override
  Future<void> addWallet(Wallet wallet) async {
    _wallets.add(Wallet(
      id: 'w${_walletSeq++}',
      ownerName: wallet.ownerName,
      label: wallet.label,
      bankId: wallet.bankId,
      cardLast4: wallet.cardLast4,
      accountRef: wallet.accountRef,
    ));
  }

  @override
  Future<void> deleteWallet(String id) async {
    _wallets.removeWhere((w) => w.id == id);
  }

  @override
  Future<List<Category>> categories() async => List.of(_categories);

  @override
  Future<void> categorize(
    String transactionId,
    List<String> categoryIds, {
    String? description,
  }) async {
    final index = _items.indexWhere((t) => t.id == transactionId);
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
        description: description,
        updatedAt: DateTime.now().toUtc(),
      );
    }
  }

  @override
  Future<List<CategoryTotal>> categoryTotals({DateTime? from, DateTime? to}) async {
    final totals = <String, int>{};
    for (final t in _items) {
      if (t.kind != 'expense') continue;
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
  Future<List<TransactionRecord>> uncategorized({int? limit}) async {
    final list = _items
        .where((t) =>
            t.amountRial != null &&
            (t.kind == 'income' || t.kind == 'expense') &&
            !_allocations.containsKey(t.id))
        .toList();
    return limit == null ? list : list.take(limit).toList();
  }

  @override
  Future<FinanceSummary> summary({DateTime? from, DateTime? to}) async {
    var income = 0;
    var expense = 0;
    for (final t in _items) {
      final amount = t.amountRial;
      if (amount == null) continue;
      if (t.kind == 'income') {
        income += amount;
      } else if (t.kind == 'expense') {
        expense += amount;
      }
    }
    return FinanceSummary(incomeRial: income, expenseRial: expense);
  }
}
