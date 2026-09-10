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
  Future<List<TransactionRecord>> getAll({int? limit}) async {
    final sorted = [..._items]
      ..sort((a, b) => (b.clientCreatedAt ?? b.createdAt)
          .compareTo(a.clientCreatedAt ?? a.createdAt));
    return limit == null ? sorted : sorted.take(limit).toList();
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
