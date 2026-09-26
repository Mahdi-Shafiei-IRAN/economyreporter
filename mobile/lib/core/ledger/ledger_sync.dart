/// همگام‌سازیِ دفترِ نسخه‌ی ۲ با سرور (docs/v2-design.md ۸ و ۱۲.۷): تراکنش‌ها، نقطه‌های مانده، تصمیم‌های
/// پیامک (بدونِ متن و فرستنده) و تنظیمات. حساب‌ها (کیف‌ها) و بودجه با همگام‌سازیِ نسخه‌ی ۱ می‌روند.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import '../sync/remote_transaction_api.dart' show PullPage;
import 'ledger_repository.dart';
import 'models.dart';

abstract class LedgerRemote {
  Future<List<Map<String, dynamic>>> push(String what, List<Map<String, dynamic>> items);
  Future<PullPage> pull(String what, {String? since});
  Future<Map<String, dynamic>> getSettings();
  Future<void> putSettings(Map<String, Object?> settings);
}

class DioLedgerRemote implements LedgerRemote {
  final Dio dio;
  DioLedgerRemote(this.dio);

  static final _slow = Options(
    sendTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 60),
  );

  @override
  Future<List<Map<String, dynamic>>> push(String what, List<Map<String, dynamic>> items) async {
    final resp = await dio.post('/ledger/$what/sync/', data: {what: items}, options: _slow);
    final data = resp.data;
    return data is Map && data['results'] is List
        ? [for (final e in data['results'] as List) if (e is Map) Map<String, dynamic>.from(e)]
        : const [];
  }

  @override
  Future<PullPage> pull(String what, {String? since}) async {
    final resp = await dio.get('/ledger/$what/sync/',
        queryParameters: {if (since != null) 'since': since}, options: _slow);
    final map = Map<String, dynamic>.from(resp.data as Map);
    return PullPage(
      results: [for (final e in (map['results'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)],
      cursor: map['cursor'] as String?,
      hasMore: map['has_more'] == true,
    );
  }

  @override
  Future<Map<String, dynamic>> getSettings() async =>
      Map<String, dynamic>.from((await dio.get('/ledger/settings/')).data as Map);

  @override
  Future<void> putSettings(Map<String, Object?> settings) async {
    await dio.put('/ledger/settings/', data: settings);
  }
}

class LedgerSyncResult {
  final int sent;
  final int received;
  final int failed;

  /// null = بی‌خطا؛ وگرنه متنِ کوتاهِ خطا (مثلاً وصل نشد).
  final String? error;

  const LedgerSyncResult({this.sent = 0, this.received = 0, this.failed = 0, this.error});

  bool get ok => error == null && failed == 0;
}

class LedgerSyncService {
  final LedgerRepository repo;
  final LedgerRemote remote;
  final DateTime Function() _clock;

  LedgerSyncService(this.repo, this.remote, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  Future<LedgerSyncResult>? _running;

  /// تنظیمات همیشه؛ داده فقط وقتی نسخه‌ی ۲ روشن است. اجرای هم‌زمان نه (همان را برمی‌گرداند).
  Future<LedgerSyncResult> sync() {
    final running = _running;
    if (running != null) return running;
    final f = _doSync();
    _running = f;
    return f.whenComplete(() => _running = null);
  }

  Future<LedgerSyncResult> _doSync() async {
    var sent = 0, received = 0, failed = 0;
    String? error;
    try {
      final dirty = await repo.dirtySettings();
      if (dirty != null) {
        await remote.putSettings(dirty);
        await repo.markSettingsSent();
      }
      await repo.applyRemoteSettings(await remote.getSettings());
      {
        final (s1, f1) = await _pushEntries();
        final (s2, f2) = await _pushCheckpoints();
        final (s3, f3) = await _pushDecisions();
        sent = s1 + s2 + s3;
        failed = f1 + f2 + f3;
        received += await _pull('entries', repo.applyRemoteEntry);
        received += await _pull('checkpoints', repo.applyRemoteCheckpoint);
        received += await _pull('decisions', repo.applyRemoteDecision);
      }
    } on DioException catch (e) {
      error = switch (e.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'به سرور وصل نشد',
        _ => 'خطای سرور ${e.response?.statusCode ?? ''}'.trim(),
      };
    } catch (e) {
      error = 'خطای برنامه: $e';
    }
    final result = LedgerSyncResult(sent: sent, received: received, failed: failed, error: error);
    await repo.setSyncStatus(jsonEncode({
      'at': _clock().toUtc().toIso8601String(),
      'sent': sent,
      'received': received,
      'failed': failed,
      'error': error,
    }));
    return result;
  }

  Map<String, dynamic> _entryPayload(Entry e, List<String> categories) {
    final m = e.toMap();
    return {
      'id': e.id,
      'account_id': e.accountId,
      'kind': m['kind'],
      'is_transfer': e.isTransfer,
      'transfer_pair_id': e.transferPairId,
      'amount_rial': e.amountRial,
      'occurred_at': m['occurred_at'],
      'bank_balance_after': e.bankBalanceAfter,
      'source': m['source'],
      'sms_key': e.smsKey ?? '',
      'note': e.note ?? '',
      'categories': categories,
      'created_by_device': e.createdByDevice ?? '',
      'client_updated_at': m['updated_at'],
      'deleted_at': m['deleted_at'],
    };
  }

  /// (ارسال‌شده، ناموفق). stale = سرور جدیدتر است → همان گرفته می‌شود.
  Future<(int, int)> _pushEntries() async {
    final rows = await repo.pendingEntries();
    if (rows.isEmpty) return (0, 0);
    final payloads = [for (final e in rows) _entryPayload(e, await repo.categoryNamesOf(e.id))];
    return _applyResults(rows.length, await remote.push('entries', payloads), (i, r) async {
      switch (r['status']) {
        case 'created' || 'updated':
          await repo.markEntrySent(rows[i]);
          return true;
        case 'stale':
          await repo.applyRemoteEntry(r);
          return true;
        case 'forbidden' || 'conflict':
          await repo.markEntrySent(rows[i], rejected: true);
          return false;
      }
      return false;
    });
  }

  Future<(int, int)> _pushCheckpoints() async {
    final rows = await repo.pendingCheckpoints();
    if (rows.isEmpty) return (0, 0);
    final payloads = [
      for (final c in rows)
        {
          'id': c.id,
          'account_id': c.accountId,
          'at': c.toMap()['at'],
          'balance_rial': c.balanceRial,
          'note': c.note ?? '',
          'client_updated_at': c.toMap()['updated_at'],
          'deleted_at': c.toMap()['deleted_at'],
        },
    ];
    return _applyResults(rows.length, await remote.push('checkpoints', payloads), (i, r) async {
      switch (r['status']) {
        case 'created' || 'updated':
          await repo.markCheckpointSent(rows[i]);
          return true;
        case 'stale':
          await repo.applyRemoteCheckpoint(r);
          return true;
        case 'forbidden' || 'conflict':
          await repo.markCheckpointSent(rows[i], rejected: true);
          return false;
      }
      return false;
    });
  }

  /// فقط کلید، اثرانگشت، زمان و تصمیم — هرگز متن یا فرستنده (I6).
  Future<(int, int)> _pushDecisions() async {
    final rows = await repo.pendingDecisions();
    if (rows.isEmpty) return (0, 0);
    final payloads = [for (final i in rows) i.decision.toPayload()];
    return _applyResults(rows.length, await remote.push('decisions', payloads), (i, r) async {
      switch (r['status']) {
        case 'created' || 'updated':
          await repo.markDecisionSent(rows[i]);
          return true;
        case 'stale':
          await repo.markDecisionSent(rows[i]);
          if (r['decision'] is Map) {
            await repo.applyRemoteDecision(Map<String, dynamic>.from(r['decision'] as Map));
          }
          return true;
      }
      return false;
    });
  }

  Future<(int, int)> _applyResults(int count, List<Map<String, dynamic>> results,
      Future<bool> Function(int index, Map<String, dynamic> result) apply) async {
    var ok = 0, bad = 0;
    for (var i = 0; i < count; i++) {
      final done = i < results.length && await apply(i, results[i]);
      done ? ok++ : bad++;
    }
    return (ok, bad);
  }

  Future<int> _pull(String what, Future<void> Function(Map<String, dynamic>) apply) async {
    var cursor = await repo.syncCursor(what);
    var n = 0;
    for (var guard = 0; guard < 100; guard++) {
      final page = await remote.pull(what, since: cursor);
      for (final row in page.results) {
        await apply(row);
        n++;
      }
      if (page.cursor != null) {
        cursor = page.cursor;
        await repo.setSyncCursor(what, cursor!);
      }
      if (!page.hasMore || page.results.isEmpty) break;
    }
    return n;
  }
}
