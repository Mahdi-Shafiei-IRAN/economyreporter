/// سرویس همگام‌سازی دوطرفه با سرور خانواده.
///
/// چرا لازم است؟ تا بقیه‌ی اعضای خانواده تراکنش‌های این گوشی را ببینند (و این
/// گوشی تراکنش‌های آن‌ها را)، و یک نسخه‌ی پشتیبان روی سرور بماند.
///
/// ارسال: صف outbox دسته‌ای فرستاده می‌شود؛ payload هر بار از روی آخرین نسخه‌ی
/// ردیف ساخته می‌شود. idempotent: هر تراکنش id ثابت دارد.
/// دریافت: تغییرات خانواده از آخرین cursor به بعد اعمال می‌شود.
/// در خطای شبکه، آیتم‌ها گم نمی‌شوند و با backoff دوباره زمان‌بندی می‌شوند.
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../features/transactions/data/transaction_repository.dart';
import '../format/money_format.dart';
import 'remote_transaction_api.dart';

class SyncSummary {
  final int synced; // created + updated + already_exists
  final int failed; // error سرور یا خطای شبکه (دوباره زمان‌بندی‌شده)
  final int pulled; // تراکنش‌های دریافتی از اعضای دیگر
  final int rejected; // forbidden: مال عضو دیگر است
  /// `network` یعنی سرور در دسترس نبود.
  final String? error;

  const SyncSummary({
    required this.synced,
    required this.failed,
    this.pulled = 0,
    this.rejected = 0,
    this.error,
  });

  int get total => synced + failed;
  bool get offline => error == 'network';

  /// پیام قابل‌فهم برای کاربر.
  String get message {
    String fa(int n) => toPersianDigits('$n');
    if (error == 'auth') return 'باید دوباره وارد شوی.';
    if (offline) {
      return 'سرور در دسترس نبود (کامپیوترِ سرور روشن و روی همان Wi-Fi است؟). '
          '${failed > 0 ? '${fa(failed)} تراکنش در صف ماند و ' : ''}'
          'بعداً خودکار ارسال می‌شود.';
    }
    final parts = ['${fa(synced)} ارسال', '${fa(pulled)} دریافت'];
    if (failed > 0) parts.add('${fa(failed)} خطا');
    if (rejected > 0) parts.add('${fa(rejected)} ردشده');
    return 'همگام‌سازی انجام شد: ${parts.join('، ')}';
  }

  Map<String, Object?> toJson(DateTime at) => {
        'at': at.toUtc().toIso8601String(),
        'synced': synced,
        'failed': failed,
        'pulled': pulled,
        'rejected': rejected,
        'error': error,
      };

  static SyncSummary fromJson(Map<String, dynamic> j) => SyncSummary(
        synced: (j['synced'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        pulled: (j['pulled'] as num?)?.toInt() ?? 0,
        rejected: (j['rejected'] as num?)?.toInt() ?? 0,
        error: j['error'] as String?,
      );
}

/// وضعیت همگام‌سازی برای نمایش در تنظیمات.
class SyncStatusInfo {
  final DateTime? lastAt;
  final SyncSummary? last;
  final int pendingCount;

  const SyncStatusInfo({this.lastAt, this.last, this.pendingCount = 0});

  static Future<SyncStatusInfo> load(TransactionStore store) async {
    final raw = await store.getSetting(SettingKeys.lastSync);
    final pending = await store.pendingSyncCount();
    if (raw == null) return SyncStatusInfo(pendingCount: pending);
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return SyncStatusInfo(
      lastAt: DateTime.tryParse(j['at'] as String? ?? ''),
      last: SyncSummary.fromJson(j),
      pendingCount: pending,
    );
  }
}

class SyncService {
  final Database db;
  final RemoteTransactionApi api;
  final String deviceId;
  final DateTime Function() _now;
  late final TransactionRepository _repo = TransactionRepository(db, clock: _now);

  Future<SyncSummary>? _running;

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

  /// [force]: همگام‌سازی دستی — منتظر backoff نمی‌ماند.
  /// اگر همگام‌سازی دیگری در جریان باشد، همان را برمی‌گرداند (اجرای هم‌زمان نه).
  Future<SyncSummary> sync({bool force = false}) {
    final running = _running;
    if (running != null) return running;
    final future = _doSync(force: force);
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<SyncSummary> _doSync({required bool force}) async {
    var synced = 0;
    var failed = 0;
    var rejected = 0;
    var pulled = 0;
    String? error;
    var refetchAll = false;
    final attempted = <String>{};

    while (true) {
      final batch = await _eligiblePending(force: force, attempted: attempted);
      if (batch.isEmpty) break;

      final rows = <Map<String, Object?>>[];
      final payloads = <Map<String, dynamic>>[];
      for (final row in batch) {
        final id = row['transaction_id'] as String;
        attempted.add(id);
        final record = await _repo.getById(id);
        if (record == null || record.kind == 'unknown') {
          await db.delete('outbox', where: 'transaction_id = ?', whereArgs: [id]);
          continue;
        }
        rows.add(row);
        payloads.add(record.toSyncPayload());
      }
      if (payloads.isEmpty) continue;

      List<Map<String, dynamic>> results;
      try {
        results = await api.syncBatch(deviceId: deviceId, transactions: payloads);
      } catch (_) {
        // خطای شبکه/سرور: کل دسته با backoff دوباره زمان‌بندی می‌شود (گم نمی‌شود).
        for (final row in rows) {
          await _reschedule(row, 'network');
          failed++;
        }
        error = 'network';
        break;
      }

      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final id = row['transaction_id'] as String;
        final result = _resultFor(results, i, id, rows.length);
        final status = result?['status'] as String?;
        final serverId = result?['id']?.toString();
        if (status == 'created' || status == 'updated' || status == 'already_exists') {
          if (serverId != null && serverId.isNotEmpty && serverId != id) {
            // سرور همین پیامک را با شناسه‌ی دیگری دارد → یکی شوند.
            await _repo.rekey(id, serverId);
            await _markSynced(serverId);
          } else {
            await _markSynced(id);
          }
          synced++;
        } else if (status == 'forbidden') {
          // تراکنش مال عضو دیگر است؛ نسخه‌ی سرور دوباره دریافت می‌شود.
          await _markSynced(id);
          rejected++;
          refetchAll = true;
        } else {
          await _reschedule(row, status ?? 'no_result');
          failed++;
        }
      }
    }

    if (error == null) {
      try {
        pulled = await _pull(fromScratch: refetchAll);
      } catch (_) {
        error = 'network';
      }
    }

    // کیف‌ها و بودجه‌ها هم هم‌گام شوند؛ خطایشان نباید کل sync را بشکند.
    if (error == null) {
      try {
        await _syncWallets(fromScratch: refetchAll);
        await _syncBudgets(fromScratch: refetchAll);
      } catch (_) {
        error = 'network';
      }
    }

    final summary = SyncSummary(
      synced: synced,
      failed: failed,
      pulled: pulled,
      rejected: rejected,
      error: error,
    );
    await _repo.setSetting(SettingKeys.lastSync, jsonEncode(summary.toJson(_now())));
    return summary;
  }

  Map<String, dynamic>? _resultFor(
    List<Map<String, dynamic>> results,
    int index,
    String id,
    int sent,
  ) {
    // سرور نتایج را به همان ترتیب برمی‌گرداند (در «تکراری» id سرور فرق می‌کند).
    if (results.length == sent) return results[index];
    for (final r in results) {
      if (r['id']?.toString() == id) return r;
    }
    return null;
  }

  Future<int> _pull({required bool fromScratch}) async {
    final me = await _repo.getSetting(SettingKeys.meUserId);
    // عضوِ عادی فقط تراکنش‌های خودش را می‌بیند؛ حتی اگر سرور (هنوز به‌روزنشده)
    // داده‌ی بقیه را بفرستد، اینجا کنار گذاشته می‌شود تا جزئیاتِ مدیر لو نرود.
    final memberOnly =
        me != null && (await _repo.getSetting(SettingKeys.myRole)) == 'member';
    var cursor = fromScratch ? null : await _repo.getSetting(SettingKeys.pullCursor);
    var fromOthers = 0;
    for (var guard = 0; guard < 100; guard++) {
      final page = await api.pull(since: cursor);
      for (final item in page.results) {
        final owner = item['owner']?.toString();
        final capturedBy = item['captured_by']?.toString();
        if (memberOnly && owner != me && capturedBy != me) {
          continue; // مالِ عضوِ دیگر یا کارتِ بی‌صاحبِ گوشیِ دیگر → نادیده
        }
        await _repo.applyRemote(item);
        if (me == null || capturedBy != me) fromOthers++;
      }
      if (page.cursor != null) cursor = page.cursor;
      if (!page.hasMore || page.results.isEmpty) break;
    }
    if (cursor != null) await _repo.setSetting(SettingKeys.pullCursor, cursor);
    return fromOthers;
  }

  /// هم‌گام‌سازی کیف‌ها: ابتدا کیف‌های pending آپلود، سپس تغییرات سرور دریافت.
  Future<void> _syncWallets({required bool fromScratch}) async {
    // ۱) آپلودِ کیف‌های تغییرکرده.
    final pending = await _repo.pendingWallets();
    if (pending.isNotEmpty) {
      final payloads = [for (final w in pending) _walletPayload(w)];
      await api.syncWallets(wallets: payloads);
      for (final w in pending) {
        await _repo.markWalletSynced(w['id'] as String);
      }
    }
    // ۲) دریافتِ کیف‌های خانواده (نقش را سرور اعمال می‌کند).
    var cursor =
        fromScratch ? null : await _repo.getSetting(SettingKeys.walletCursor);
    for (var guard = 0; guard < 100; guard++) {
      final page = await api.pullWallets(since: cursor);
      for (final item in page.results) {
        await _repo.applyRemoteWallet(item);
      }
      if (page.cursor != null) cursor = page.cursor;
      if (!page.hasMore || page.results.isEmpty) break;
    }
    if (cursor != null) await _repo.setSetting(SettingKeys.walletCursor, cursor);
  }

  /// هم‌گام‌سازی بودجه‌ها (مثلِ کیف‌ها؛ بین اعضای خانواده مشترک‌اند).
  Future<void> _syncBudgets({required bool fromScratch}) async {
    final pending = await _repo.pendingBudgets();
    if (pending.isNotEmpty) {
      final payloads = [for (final b in pending) _budgetPayload(b)];
      await api.syncBudgets(budgets: payloads);
      for (final b in pending) {
        await _repo.markBudgetSynced(b['id'] as String);
      }
    }
    var cursor =
        fromScratch ? null : await _repo.getSetting(SettingKeys.budgetCursor);
    for (var guard = 0; guard < 100; guard++) {
      final page = await api.pullBudgets(since: cursor);
      for (final item in page.results) {
        await _repo.applyRemoteBudget(item);
      }
      if (page.cursor != null) cursor = page.cursor;
      if (!page.hasMore || page.results.isEmpty) break;
    }
    if (cursor != null) await _repo.setSetting(SettingKeys.budgetCursor, cursor);
  }

  Map<String, dynamic> _budgetPayload(Map<String, Object?> b) => {
        'id': b['id'],
        'category_name': b['category_name'] ?? '',
        'period': b['period'] ?? 'monthly',
        'limit_rial': b['limit_rial'] ?? 0,
        'is_deleted': (b['is_deleted'] as int? ?? 0) == 1,
        'client_updated_at': b['client_updated_at'],
      };

  Map<String, dynamic> _walletPayload(Map<String, Object?> w) => {
        'id': w['id'],
        'owner_user_id': w['owner_user_id'],
        'owner_name': w['owner_name'] ?? '',
        'label': w['label'] ?? '',
        'bank_id': w['bank_id'] ?? '',
        'card_last4': w['card_last4'] ?? '',
        'account_ref': w['account_ref'] ?? '',
        'is_deleted': (w['is_deleted'] as int? ?? 0) == 1,
        'client_updated_at': w['client_updated_at'],
      };

  Future<List<Map<String, Object?>>> _eligiblePending({
    required bool force,
    required Set<String> attempted,
  }) async {
    final nowIso = _now().toUtc().toIso8601String();
    final rows = await db.query(
      'outbox',
      where: force
          ? "status = 'pending'"
          : "status = 'pending' AND (next_retry_at IS NULL OR next_retry_at <= ?)",
      whereArgs: force ? null : [nowIso],
      orderBy: 'retry_count ASC',
    );
    return rows
        .where((r) => !attempted.contains(r['transaction_id']))
        .take(batchSize)
        .toList();
  }

  Future<void> _markSynced(String id) async {
    await db.delete('outbox', where: 'transaction_id = ?', whereArgs: [id]);
    await db.update(
      'transactions',
      {'sync_status': 'synced'},
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
      {'sync_status': 'failed'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
