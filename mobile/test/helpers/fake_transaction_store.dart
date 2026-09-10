/// مخزن جعلی in-memory برای تست‌های ویجت (بدون I/O بومی، سازگار با FakeAsync).
library;

import 'package:economy/core/sms/models.dart';
import 'package:economy/core/sms/sms_fingerprint.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';

class FakeTransactionStore implements TransactionStore {
  final List<TransactionRecord> _items = [];
  int _seq = 0;

  /// افزودن همگام برای آماده‌سازی داده‌ی تست (بدون await).
  void seed(ParsedTransaction parsed, {required String sender, DateTime? receivedAt}) {
    _put(parsed, sender: sender, receivedAt: receivedAt);
  }

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
