/// سرویس همگام‌سازی: صف outbox را دسته‌ای به سرور می‌فرستد و نتیجه را اعمال می‌کند.
///
/// idempotency: هر تراکنش id ثابت دارد؛ سرور تکراری‌ها را already_exists می‌کند.
/// در خطای شبکه، آیتم‌ها گم نمی‌شوند و با backoff دوباره زمان‌بندی می‌شوند.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'remote_transaction_api.dart';

class SyncSummary {
  final int synced; // created + already_exists
  final int failed; // error سرور یا خطای شبکه (دوباره زمان‌بندی‌شده)
  const SyncSummary({required this.synced, required this.failed});

  int get total => synced + failed;
}

class SyncService {
  final Database db;
  final RemoteTransactionApi api;
  final String deviceId;
  final DateTime Function() _now;

  static const int batchSize = 50;
  static const List<Duration> backoff = [
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
    Duration(minutes: 30),
  ];

  SyncService({
    required this.db,
    required this.api,
    required this.deviceId,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  Future<SyncSummary> sync() async {
    var synced = 0;
    var failed = 0;

    while (true) {
      final batch = await _eligiblePending();
      if (batch.isEmpty) break;

      final payloads = batch
          .map((row) =>
              jsonDecode(row['payload'] as String) as Map<String, dynamic>)
          .toList();

      List<Map<String, dynamic>> results;
      try {
        results =
            await api.syncBatch(deviceId: deviceId, transactions: payloads);
      } catch (_) {
        // خطای شبکه/سرور: کل دسته با backoff دوباره زمان‌بندی می‌شود (گم نمی‌شود).
        for (final row in batch) {
          await _reschedule(row, 'network');
          failed++;
        }
        break;
      }

      final statusById = {
        for (final r in results) r['id'].toString(): r['status'] as String,
      };

      for (final row in batch) {
        final id = row['transaction_id'] as String;
        final status = statusById[id];
        if (status == 'created' || status == 'already_exists') {
          await _markSynced(id);
          synced++;
        } else {
          await _reschedule(row, status ?? 'no_result');
          failed++;
        }
      }
    }

    return SyncSummary(synced: synced, failed: failed);
  }

  Future<List<Map<String, Object?>>> _eligiblePending() async {
    final nowIso = _now().toUtc().toIso8601String();
    return db.query(
      'outbox',
      where: "status = 'pending' AND (next_retry_at IS NULL OR next_retry_at <= ?)",
      whereArgs: [nowIso],
      orderBy: 'retry_count ASC',
      limit: batchSize,
    );
  }

  Future<void> _markSynced(String id) async {
    final nowIso = _now().toUtc().toIso8601String();
    await db.delete('outbox', where: 'transaction_id = ?', whereArgs: [id]);
    await db.update(
      'transactions',
      {'sync_status': 'synced', 'updated_at': nowIso},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _reschedule(Map<String, Object?> row, String error) async {
    final id = row['transaction_id'] as String;
    final retryCount = (row['retry_count'] as int? ?? 0) + 1;
    final delay = backoff[(retryCount - 1).clamp(0, backoff.length - 1)];
    final now = _now().toUtc();
    await db.update(
      'outbox',
      {
        'status': 'pending',
        'retry_count': retryCount,
        'last_attempt_at': now.toIso8601String(),
        'next_retry_at': now.add(delay).toIso8601String(),
        'last_error': error,
      },
      where: 'transaction_id = ?',
      whereArgs: [id],
    );
    await db.update(
      'transactions',
      {'sync_status': 'failed', 'updated_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
