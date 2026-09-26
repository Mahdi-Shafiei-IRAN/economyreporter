/// سرویس همگام‌سازی دوطرفه با سرور خانواده.
///
/// چرا لازم است؟ تا بقیه‌ی اعضای خانواده تراکنش‌های این گوشی را ببینند (و این
/// گوشی تراکنش‌های آن‌ها را)، و یک نسخه‌ی پشتیبان روی سرور بماند.
///
/// ارسال: صف outbox دسته‌ای فرستاده می‌شود؛ payload هر بار از روی آخرین نسخه‌ی
/// ردیف ساخته می‌شود. idempotent: هر تراکنش id ثابت دارد.
/// دریافت: تغییرات خانواده از آخرین cursor به بعد اعمال می‌شود.
/// در خطای شبکه، آیتم‌ها گم نمی‌شوند و با backoff دوباره زمان‌بندی می‌شوند.
///
/// خطاها دقیق گزارش می‌شوند (نه همه «سرور در دسترس نبود»): وصل نشدن، خطای سرور با کد
/// و مرحله، یا خطای خودِ برنامه. یک آیتمِ خراب (تراکنش/کیف/بودجه) بقیه را نگه نمی‌دارد.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../features/transactions/data/transaction_repository.dart';
import '../format/money_format.dart';
import 'remote_transaction_api.dart';

/// یک خطای همگام‌سازی، با نوع و مرحله (برای پیامِ دقیق و عیب‌یابی).
class SyncFailure {
  /// `network` (به سرور وصل نشد) | `http` (سرور جواب داد ولی خطا) | `auth` | `app`.
  final String kind;

  /// `send` | `pull` | `wallets` | `budgets`.
  final String stage;

  /// کدِ HTTP (برای `http`).
  final int? status;

  /// توضیحِ کوتاه (پیامِ سرور یا نوعِ خطا).
  final String? detail;

  const SyncFailure(this.kind, this.stage, {this.status, this.detail});

  bool get isNetwork => kind == 'network';

  /// دسته‌بندیِ هر خطا: فقط وصل‌نشدن «شبکه» است؛ جوابِ خطادارِ سرور و باگِ برنامه نه.
  factory SyncFailure.of(Object e, String stage) {
    if (e is SyncItemsError) return e.failure;
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return SyncFailure('network', stage, detail: e.type.name);
        case DioExceptionType.badResponse:
          final code = e.response?.statusCode;
          if (code == 401) return SyncFailure('auth', stage, status: code);
          return SyncFailure('http', stage, status: code, detail: _short(e.response?.data));
        default:
          final inner = e.error;
          if (inner is SocketException || inner is HandshakeException || inner is HttpException) {
            return SyncFailure('network', stage, detail: inner.runtimeType.toString());
          }
          return SyncFailure('app', stage, detail: _short(inner ?? e.message));
      }
    }
    if (e is SocketException || e is HttpException) {
      return SyncFailure('network', stage, detail: e.runtimeType.toString());
    }
    return SyncFailure('app', stage, detail: _short(e));
  }

  static String? _short(Object? v) {
    if (v == null) return null;
    final s = v.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return null;
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  String get stageLabel => switch (stage) {
        'send' => 'ارسال تراکنش‌ها',
        'pull' => 'دریافت تراکنش‌ها',
        'wallets' => 'کارت‌ها',
        'budgets' => 'بودجه‌ها',
        _ => stage,
      };

  Map<String, Object?> toJson() =>
      {'kind': kind, 'stage': stage, 'status': status, 'detail': detail};

  static SyncFailure? fromJson(Object? j) {
    if (j is! Map) return null;
    return SyncFailure(
      j['kind']?.toString() ?? 'app',
      j['stage']?.toString() ?? '',
      status: (j['status'] as num?)?.toInt(),
      detail: j['detail'] as String?,
    );
  }
}

/// بعضی آیتم‌های یک مرحله (کیف/بودجه) را سرور نپذیرفت؛ بقیه‌ی مرحله انجام شد.
class SyncItemsError implements Exception {
  final SyncFailure failure;
  const SyncItemsError(this.failure);
}

class SyncSummary {
  final int synced; // created + updated + already_exists
  final int failed; // error سرور یا خطای شبکه (دوباره زمان‌بندی‌شده)
  final int pulled; // تراکنش‌های دریافتی از اعضای دیگر
  final int rejected; // forbidden: مال عضو دیگر است
  /// نوعِ خطا: `network` (وصل نشد)، `auth`، `http`، `app`؛ null یعنی بی‌خطا.
  final String? error;

  /// جزئیاتِ خطا (مرحله، کد، پیام).
  final SyncFailure? failure;

  const SyncSummary({
    required this.synced,
    required this.failed,
    this.pulled = 0,
    this.rejected = 0,
    this.error,
    this.failure,
  });

  int get total => synced + failed;
  bool get offline => error == 'network';

  /// پیام قابل‌فهم برای کاربر.
  String get message {
    String fa(int n) => toPersianDigits('$n');
    if (error == 'auth') return 'باید دوباره وارد شوی.';
    final queued =
        failed > 0 ? '${fa(failed)} تراکنش در صف ماند و بعداً خودکار ارسال می‌شود.' : '';
    if (offline) {
      return 'به سرور وصل نشد (اینترنتِ گوشی، یا خاموش بودنِ سرویسِ سرور). $queued'.trim();
    }
    final parts = ['${fa(synced)} ارسال', '${fa(pulled)} دریافت'];
    if (failed > 0) parts.add('${fa(failed)} خطا');
    if (rejected > 0) parts.add('${fa(rejected)} ردشده');
    final f = failure;
    if (f == null || error == null) return 'همگام‌سازی انجام شد: ${parts.join('، ')}';
    final what = f.kind == 'http'
        ? 'سرور خطای ${fa(f.status ?? 0)} داد'
        : 'خطای برنامه';
    return 'همگام‌سازی نیمه‌کاره (${parts.join('، ')}). در «${f.stageLabel}» $what'
        '${f.detail == null ? '' : ': ${f.detail}'}';
  }

  Map<String, Object?> toJson(DateTime at) => {
        'at': at.toUtc().toIso8601String(),
        'synced': synced,
        'failed': failed,
        'pulled': pulled,
        'rejected': rejected,
        'error': error,
        'failure': failure?.toJson(),
      };

  static SyncSummary fromJson(Map<String, dynamic> j) => SyncSummary(
        synced: (j['synced'] as num?)?.toInt() ?? 0,
        failed: (j['failed'] as num?)?.toInt() ?? 0,
        pulled: (j['pulled'] as num?)?.toInt() ?? 0,
        rejected: (j['rejected'] as num?)?.toInt() ?? 0,
        error: j['error'] as String?,
        failure: SyncFailure.fromJson(j['failure']),
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
    SyncFailure? failure;
    var refetchAll = false;
    final attempted = <String>{};

    // نتیجه‌ی سرور برای یک تراکنش را اعمال می‌کند.
    Future<void> apply(Map<String, Object?> row, Map<String, dynamic>? result) async {
      final id = row['transaction_id'] as String;
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
        await _reschedule(row, _itemError(status, result?['detail']));
        failed++;
      }
    }

    // ۱) ارسال.
    send:
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

      try {
        final results = await api.syncBatch(deviceId: deviceId, transactions: payloads);
        for (var i = 0; i < rows.length; i++) {
          await apply(rows[i], _resultFor(results, i, rows[i]['transaction_id'] as String, rows.length));
        }
      } catch (e) {
        final f = SyncFailure.of(e, 'send');
        failure ??= f;
        if (f.isNetwork || f.kind == 'auth' || rows.length == 1) {
          // شبکه: کل دسته با backoff دوباره (گم نمی‌شود).
          for (final row in rows) {
            await _reschedule(row, f.kind);
            failed++;
          }
          if (f.isNetwork || f.kind == 'auth') break send;
          continue;
        }
        // سرور کلِ دسته را رد کرد (مثلاً یک تراکنشِ خراب): تک‌تک بفرست تا بقیه گیر نکنند.
        for (var i = 0; i < rows.length; i++) {
          try {
            final r = await api.syncBatch(deviceId: deviceId, transactions: [payloads[i]]);
            await apply(rows[i], r.isEmpty ? null : r.first);
          } catch (e2) {
            final f2 = SyncFailure.of(e2, 'send');
            await _reschedule(rows[i], f2.status == null ? f2.kind : 'http_${f2.status}');
            failed++;
            if (f2.isNetwork) {
              failure = f2;
              break send;
            }
          }
        }
      }
    }

    // ۲ تا ۴) دریافت، کارت‌ها، بودجه‌ها — هر مرحله جدا؛ خطای یکی بقیه را نمی‌شکند
    // (مگر وصل نشدن، که بقیه هم بی‌فایده است).
    Future<void> stage(String name, Future<void> Function() run) async {
      if (failure?.isNetwork == true || failure?.kind == 'auth') return;
      try {
        await run();
      } catch (e) {
        final f = SyncFailure.of(e, name);
        if (failure == null || f.isNetwork) failure = f;
      }
    }

    await stage('pull', () async => pulled = await _pull(fromScratch: refetchAll));
    await stage('wallets', () => _syncWallets(fromScratch: refetchAll));
    await stage('budgets', () => _syncBudgets(fromScratch: refetchAll));

    final summary = SyncSummary(
      synced: synced,
      failed: failed,
      pulled: pulled,
      rejected: rejected,
      error: failure?.kind,
      failure: failure,
    );
    await _repo.setSetting(SettingKeys.lastSync, jsonEncode(summary.toJson(_now())));
    return summary;
  }

  /// کدِ خطای یک آیتم (برای outbox.last_error).
  String _itemError(String? status, Object? detail) {
    final d = SyncFailure._short(detail);
    return d == null ? (status ?? 'no_result') : '${status ?? 'error'}: $d';
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
    final pushFailure = await _pushItems(
      'wallets',
      await _repo.pendingWallets(),
      _walletPayload,
      (items) => api.syncWallets(wallets: items),
    );
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
    if (pushFailure != null) throw SyncItemsError(pushFailure);
  }

  /// هم‌گام‌سازی بودجه‌ها (مثلِ کیف‌ها؛ بین اعضای خانواده مشترک‌اند).
  Future<void> _syncBudgets({required bool fromScratch}) async {
    final pushFailure = await _pushItems(
      'budgets',
      await _repo.pendingBudgets(),
      _budgetPayload,
      (items) => api.syncBudgets(budgets: items),
    );
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
    if (pushFailure != null) throw SyncItemsError(pushFailure);
  }

  /// آپلودِ آیتم‌های pending (کیف/بودجه). سرورِ جدید نتیجه‌ی هر آیتم را جدا می‌دهد؛
  /// سرورِ قدیمی با یک آیتمِ خراب کلِ درخواست را رد می‌کرد → آن‌وقت تک‌تک. آیتمی که
  /// شناسه‌اش مالِ خانواده‌ی دیگری است (مثلاً بعد از عوض کردنِ حساب) شناسه‌ی تازه
  /// می‌گیرد؛ آیتمِ نامعتبر «ناموفق» می‌شود تا همگام‌سازی را برای همیشه گیر نیندازد.
  /// اولین خطای آیتم‌ها را برمی‌گرداند (null = همه موفق).
  Future<SyncFailure?> _pushItems(
    String table,
    List<Map<String, Object?>> pending,
    Map<String, dynamic> Function(Map<String, Object?>) payload,
    Future<List<Map<String, dynamic>>> Function(List<Map<String, dynamic>>) send,
  ) async {
    if (pending.isEmpty) return null;
    SyncFailure? first;
    try {
      final results = await send([for (final p in pending) payload(p)]);
      for (var i = 0; i < pending.length; i++) {
        final id = pending[i]['id'].toString();
        // (نه `first ??= await …`: آن بعد از اولین خطا بقیه را اصلاً اجرا نمی‌کند.)
        final f = await _applyItemResult(
            table, id, _resultFor(results, i, id, pending.length) ?? const {});
        first ??= f;
      }
      return first;
    } catch (e) {
      if (SyncFailure.of(e, table).kind != 'http') rethrow; // وصل نشد/نشست/باگ
    }
    for (final item in pending) {
      final id = item['id'].toString();
      try {
        final r = await send([payload(item)]);
        final f = await _applyItemResult(table, id, r.isEmpty ? const {} : r.first);
        first ??= f;
      } catch (e) {
        final f = SyncFailure.of(e, table);
        if (f.kind != 'http') rethrow;
        if (f.status == 404) {
          await _rekeyRow(table, id);
        } else {
          await _setRowStatus(table, id, 'failed');
          first ??= f;
        }
      }
    }
    return first;
  }

  /// نتیجه‌ی یک آیتم؛ سرورِ قدیمی خودِ آیتم را (بی‌status) برمی‌گرداند = موفق.
  Future<SyncFailure?> _applyItemResult(
      String table, String id, Map<String, dynamic> result) async {
    final status = result['status']?.toString();
    if (status == 'conflict') {
      await _rekeyRow(table, id);
      return null;
    }
    if (status == 'error') {
      await _setRowStatus(table, id, 'failed');
      return SyncFailure('http', table, status: 400, detail: SyncFailure._short(result['detail']));
    }
    await _setRowStatus(table, id, 'synced');
    return null;
  }

  Future<void> _setRowStatus(String table, String id, String status) =>
      db.update(table, {'sync_status': status}, where: 'id = ?', whereArgs: [id]);

  /// شناسه‌ی تازه (UUID) برای آیتمی که شناسه‌اش روی سرور مالِ خانواده‌ی دیگری است.
  Future<void> _rekeyRow(String table, String oldId) async {
    final newId = const Uuid().v4();
    await db.transaction((txn) async {
      await txn.update(table, {'id': newId, 'sync_status': 'pending'},
          where: 'id = ?', whereArgs: [oldId]);
      if (table == 'wallets') {
        await txn.update('transactions', {'pinned_wallet_id': newId},
            where: 'pinned_wallet_id = ?', whereArgs: [oldId]);
      }
    });
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
        'archived': (w['archived'] as int? ?? 0) == 1,
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
