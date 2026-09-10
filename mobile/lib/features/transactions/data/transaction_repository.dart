/// مخزن تراکنش‌ها روی پایگاه‌داده‌ی محلی.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sms/models.dart';
import '../../../core/sms/sms_fingerprint.dart';
import 'transaction_record.dart';

enum TxInsertStatus { created, duplicate }

class TxInsertOutcome {
  final TxInsertStatus status;
  final String id;
  const TxInsertOutcome(this.status, this.id);

  bool get isCreated => status == TxInsertStatus.created;
  bool get isDuplicate => status == TxInsertStatus.duplicate;
}

/// جمع مالی یک بازه. transferها و رکوردهای بدون مبلغ در جمع نمی‌آیند.
class FinanceSummary {
  final int incomeRial;
  final int expenseRial;
  const FinanceSummary({required this.incomeRial, required this.expenseRial});

  int get balanceRial => incomeRial - expenseRial;
}

/// انتزاع مخزن تراکنش برای تزریق: اپ از SQLite استفاده می‌کند،
/// تست‌های ویجت از یک پیاده‌سازی in-memory (بدون I/O بومی).
abstract class TransactionStore {
  Future<TxInsertOutcome> saveParsed(
    ParsedTransaction parsed, {
    required String sender,
    String? deviceId,
    DateTime? receivedAt,
  });
  Future<List<TransactionRecord>> getAll({
    int? limit,
    String? kind,
    bool? needsReview,
    String? search,
  });
  Future<FinanceSummary> summary({DateTime? from, DateTime? to});
  Future<int> needsReviewCount();
  Future<void> updateTransaction(
    String id, {
    String? kind,
    int? amountRial,
    String? counterparty,
    String? description,
    bool? needsReview,
  });
  Future<void> deleteTransaction(String id);
}

class TransactionRepository implements TransactionStore {
  final Database _db;
  final Uuid _uuid;

  TransactionRepository(this._db, {Uuid uuid = const Uuid()}) : _uuid = uuid;

  /// ذخیره‌ی خروجی پارسر. اگر پیامک قبلاً ذخیره شده باشد (اثرانگشت یکسان)،
  /// رکورد جدید ساخته نمی‌شود و وضعیت `duplicate` برمی‌گردد.
  @override
  Future<TxInsertOutcome> saveParsed(
    ParsedTransaction parsed, {
    required String sender,
    String? deviceId,
    DateTime? receivedAt,
  }) async {
    final now = DateTime.now().toUtc();
    final hash = parsed.rawBody.trim().isEmpty
        ? null
        : smsFingerprint(sender: sender, body: parsed.rawBody, receivedAt: receivedAt);

    if (hash != null) {
      final existing = await _db.query(
        'transactions',
        columns: ['id'],
        where: 'source_message_hash = ?',
        whereArgs: [hash],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return TxInsertOutcome(TxInsertStatus.duplicate, existing.first['id'] as String);
      }
    }

    final id = _uuid.v4();
    final record = TransactionRecord.fromParsed(
      parsed,
      id: id,
      now: now,
      sourceMessageHash: hash,
      deviceId: deviceId,
    );
    await _db.insert('transactions', record.toMap());
    await _enqueueOutbox(record);
    return TxInsertOutcome(TxInsertStatus.created, id);
  }

  /// درج مستقیم یک رکورد (برای ثبت دستی یا تست).
  Future<void> insert(TransactionRecord record) async {
    await _db.insert('transactions', record.toMap());
    await _enqueueOutbox(record);
  }

  /// صف‌کردن تراکنش برای همگام‌سازی. تراکنش با نوع نامشخص تا بازبینی sync نمی‌شود.
  Future<void> _enqueueOutbox(TransactionRecord record) async {
    if (record.kind == 'unknown') return;
    await _db.insert(
      'outbox',
      {
        'transaction_id': record.id,
        'payload': jsonEncode(record.toSyncPayload()),
        'status': 'pending',
        'retry_count': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<TransactionRecord>> getAll({
    int? limit,
    String? kind,
    bool? needsReview,
    String? search,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    if (needsReview != null) {
      where.add('needs_review = ?');
      args.add(needsReview ? 1 : 0);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(counterparty LIKE ? OR description LIKE ? OR bank_id LIKE ?)');
      final q = '%${search.trim()}%';
      args..add(q)..add(q)..add(q);
    }
    final rows = await _db.query(
      'transactions',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'COALESCE(transaction_date, client_created_at, created_at) DESC',
      limit: limit,
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  Future<int> count() async {
    return Sqflite.firstIntValue(
          await _db.rawQuery('SELECT COUNT(*) FROM transactions'),
        ) ??
        0;
  }

  @override
  Future<int> needsReviewCount() async {
    return Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM transactions WHERE needs_review = 1',
          ),
        ) ??
        0;
  }

  @override
  Future<void> updateTransaction(
    String id, {
    String? kind,
    int? amountRial,
    String? counterparty,
    String? description,
    bool? needsReview,
  }) async {
    final now = DateTime.now().toUtc();
    final data = <String, Object?>{'updated_at': now.toIso8601String()};
    if (kind != null) data['kind'] = kind;
    if (amountRial != null) data['amount_rial'] = amountRial;
    if (counterparty != null) data['counterparty'] = counterparty;
    if (description != null) data['description'] = description;
    if (needsReview != null) data['needs_review'] = needsReview ? 1 : 0;
    await _db.update('transactions', data, where: 'id = ?', whereArgs: [id]);

    final rows =
        await _db.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final record = TransactionRecord.fromMap(rows.first);

    // اگر نوع معتبر شد و هنوز sync نشده، با payload به‌روز دوباره صف کن.
    if (record.kind != 'unknown' && record.syncStatus != 'synced') {
      await _db.update('transactions', {'sync_status': 'pending'},
          where: 'id = ?', whereArgs: [id]);
      await _enqueueOutbox(record);
    }
  }

  @override
  Future<void> deleteTransaction(String id) async {
    await _db.delete('outbox', where: 'transaction_id = ?', whereArgs: [id]);
    await _db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  /// جمع درآمد/هزینه‌ی بازه (transfer و unknown و رکورد بدون مبلغ حذف می‌شوند).
  @override
  Future<FinanceSummary> summary({DateTime? from, DateTime? to}) async {
    final where = StringBuffer(
      "amount_rial IS NOT NULL AND kind IN ('income','expense')",
    );
    final args = <Object?>[];
    const dateExpr = 'COALESCE(transaction_date, client_created_at, created_at)';
    if (from != null) {
      where.write(' AND $dateExpr >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.write(' AND $dateExpr <= ?');
      args.add(to.toUtc().toIso8601String());
    }

    final rows = await _db.rawQuery(
      'SELECT kind, COALESCE(SUM(amount_rial), 0) AS total '
      'FROM transactions WHERE $where GROUP BY kind',
      args,
    );

    var income = 0;
    var expense = 0;
    for (final row in rows) {
      final kind = row['kind'] as String;
      final total = (row['total'] as int?) ?? 0;
      if (kind == 'income') {
        income = total;
      } else if (kind == 'expense') {
        expense = total;
      }
    }
    return FinanceSummary(incomeRial: income, expenseRial: expense);
  }
}
