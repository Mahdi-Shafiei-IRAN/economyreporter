/// همگام‌سازیِ کیف‌ها (حساب‌ها) و بودجه‌ها با سرورِ خانواده. دفترِ نسخه‌ی ۲ (تراکنش، نقطه، تصمیم) را
/// `LedgerSyncService` می‌فرستد؛ تراکنش‌های نسخه‌ی ۱ دیگر فرستاده یا گرفته نمی‌شوند (طرح ۱۲.۸).
///
/// هر مرحله جداست و خطای یکی بقیه را نمی‌شکند (مگر وصل نشدن). یک آیتمِ خراب بقیه را نگه نمی‌دارد.
library;

import 'dart:io';

import 'package:dio/dio.dart';

import '../store/app_store.dart';
import 'remote_sync_api.dart';

/// یک خطای همگام‌سازی، با نوع و مرحله.
class SyncFailure {
  /// `network` (به سرور وصل نشد) | `http` (سرور جواب داد ولی خطا) | `auth` | `app`.
  final String kind;

  /// `wallets` | `budgets`.
  final String stage;

  /// کدِ HTTP (برای `http`).
  final int? status;

  /// توضیحِ کوتاه (پیامِ سرور یا نوعِ خطا).
  final String? detail;

  const SyncFailure(this.kind, this.stage, {this.status, this.detail});

  bool get isNetwork => kind == 'network';

  /// فقط وصل‌نشدن «شبکه» است؛ جوابِ خطادارِ سرور و باگِ برنامه نه.
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
          return SyncFailure('http', stage, status: code, detail: short(e.response?.data));
        default:
          final inner = e.error;
          if (inner is SocketException || inner is HandshakeException || inner is HttpException) {
            return SyncFailure('network', stage, detail: inner.runtimeType.toString());
          }
          return SyncFailure('app', stage, detail: short(inner ?? e.message));
      }
    }
    if (e is SocketException || e is HttpException) {
      return SyncFailure('network', stage, detail: e.runtimeType.toString());
    }
    return SyncFailure('app', stage, detail: short(e));
  }

  static String? short(Object? v) {
    if (v == null) return null;
    final s = v.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return null;
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }
}

/// بعضی آیتم‌های یک مرحله را سرور نپذیرفت؛ بقیه‌ی مرحله انجام شد.
class SyncItemsError implements Exception {
  final SyncFailure failure;
  const SyncItemsError(this.failure);
}

class SyncSummary {
  /// null یعنی بی‌خطا.
  final SyncFailure? failure;

  const SyncSummary({this.failure});

  static const ok = SyncSummary();

  bool get offline => failure?.isNetwork ?? false;
}

class SyncService {
  final AppStore store;
  final RemoteSyncApi api;

  Future<SyncSummary>? _running;

  SyncService({required this.store, required this.api});

  /// اگر همگام‌سازیِ دیگری در جریان باشد، همان را برمی‌گرداند (اجرای هم‌زمان نه).
  Future<SyncSummary> sync() {
    final running = _running;
    if (running != null) return running;
    final future = _doSync();
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<SyncSummary> _doSync() async {
    SyncFailure? failure;
    Future<void> stage(String name, Future<void> Function() run) async {
      if (failure?.isNetwork == true || failure?.kind == 'auth') return;
      try {
        await run();
      } catch (e) {
        final f = SyncFailure.of(e, name);
        if (failure == null || f.isNetwork) failure = f;
      }
    }

    await stage(
        'wallets',
        () => _syncTable('wallets', SettingKeys.walletCursor, store.pendingWallets, _walletPayload,
            (items) => api.syncWallets(wallets: items), api.pullWallets, store.applyRemoteWallet));
    await stage(
        'budgets',
        () => _syncTable('budgets', SettingKeys.budgetCursor, store.pendingBudgets, _budgetPayload,
            (items) => api.syncBudgets(budgets: items), api.pullBudgets, store.applyRemoteBudget));
    return SyncSummary(failure: failure);
  }

  /// آپلودِ ردیف‌های pending، سپس دریافتِ تغییراتِ خانواده (نقش را سرور اعمال می‌کند).
  Future<void> _syncTable(
    String table,
    String cursorKey,
    Future<List<Map<String, Object?>>> Function() pending,
    Map<String, dynamic> Function(Map<String, Object?>) payload,
    Future<List<Map<String, dynamic>>> Function(List<Map<String, dynamic>>) send,
    Future<PullPage> Function({String? since}) pull,
    Future<void> Function(Map<String, dynamic>) apply,
  ) async {
    final pushFailure = await _pushItems(table, await pending(), payload, send);
    var cursor = await store.getSetting(cursorKey);
    for (var guard = 0; guard < 100; guard++) {
      final page = await pull(since: cursor);
      for (final item in page.results) {
        await apply(item);
      }
      if (page.cursor != null) cursor = page.cursor;
      if (!page.hasMore || page.results.isEmpty) break;
    }
    if (cursor != null) await store.setSetting(cursorKey, cursor);
    if (pushFailure != null) throw SyncItemsError(pushFailure);
  }

  /// سرورِ جدید نتیجه‌ی هر آیتم را جدا می‌دهد؛ سرورِ قدیمی با یک آیتمِ خراب کلِ درخواست را رد می‌کرد
  /// → آن‌وقت تک‌تک. آیتمی که شناسه‌اش مالِ خانواده‌ی دیگری است شناسه‌ی تازه می‌گیرد؛ آیتمِ نامعتبر
  /// «ناموفق» می‌شود تا همگام‌سازی را برای همیشه گیر نیندازد. اولین خطا (null = همه موفق).
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
        final f = await _applyItemResult(table, id, _resultFor(results, i, id, pending.length) ?? const {});
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
          await store.rekeyRow(table, id);
        } else {
          await store.setRowStatus(table, id, 'failed');
          first ??= f;
        }
      }
    }
    return first;
  }

  /// نتیجه‌ی یک آیتم؛ سرورِ قدیمی خودِ آیتم را (بی‌status) برمی‌گرداند = موفق.
  Future<SyncFailure?> _applyItemResult(String table, String id, Map<String, dynamic> result) async {
    final status = result['status']?.toString();
    if (status == 'conflict') {
      await store.rekeyRow(table, id);
      return null;
    }
    if (status == 'error') {
      await store.setRowStatus(table, id, 'failed');
      return SyncFailure('http', table, status: 400, detail: SyncFailure.short(result['detail']));
    }
    await store.setRowStatus(table, id, 'synced');
    return null;
  }

  /// سرور نتایج را به همان ترتیب برمی‌گرداند؛ وگرنه با شناسه پیدا می‌شود.
  Map<String, dynamic>? _resultFor(List<Map<String, dynamic>> results, int index, String id, int sent) {
    if (results.length == sent) return results[index];
    for (final r in results) {
      if (r['id']?.toString() == id) return r;
    }
    return null;
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
}
