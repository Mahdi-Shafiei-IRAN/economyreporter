/// کلاینت endpoint همگام‌سازی سرور. اینترفیس تزریق‌پذیر تا در تست fake شود.
library;

import 'package:dio/dio.dart';

/// یک صفحه از تغییرات خانواده که از سرور دریافت می‌شود.
class PullPage {
  final List<Map<String, dynamic>> results;

  /// نشانگر ادامه؛ دفعه‌ی بعد از همین‌جا دریافت می‌شود.
  final String? cursor;
  final bool hasMore;

  const PullPage({required this.results, this.cursor, this.hasMore = false});

  static const empty = PullPage(results: []);
}

abstract class RemoteTransactionApi {
  /// یک دسته تراکنش را می‌فرستد و لیست نتیجه‌ی هر آیتم را (به همان ترتیب)
  /// برمی‌گرداند: `{id, status}` که status یکی از
  /// created/updated/already_exists/forbidden/error است.
  Future<List<Map<String, dynamic>>> syncBatch({
    required String deviceId,
    required List<Map<String, dynamic>> transactions,
  });

  /// تغییرات تراکنش‌های خانواده بعد از [since] (همه‌ی اعضا).
  Future<PullPage> pull({String? since, int limit = 500});

  /// آپلود دسته‌ای کیف‌ها (کارت/حساب)؛ upsert با شناسه‌ی گوشی.
  Future<void> syncWallets({required List<Map<String, dynamic>> wallets});

  /// دریافت تغییرات کیف‌های خانواده بعد از [since].
  Future<PullPage> pullWallets({String? since});

  /// آپلود دسته‌ای بودجه‌ها؛ upsert با شناسه‌ی گوشی.
  Future<void> syncBudgets({required List<Map<String, dynamic>> budgets});

  /// دریافت تغییرات بودجه‌های خانواده بعد از [since].
  Future<PullPage> pullBudgets({String? since});
}

class DioRemoteTransactionApi implements RemoteTransactionApi {
  final Dio dio;

  DioRemoteTransactionApi(this.dio);

  @override
  Future<List<Map<String, dynamic>>> syncBatch({
    required String deviceId,
    required List<Map<String, dynamic>> transactions,
  }) async {
    final resp = await dio.post(
      '/sync/transactions/',
      data: {'device_id': deviceId, 'transactions': transactions},
    );
    final results = (resp.data['results'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return results;
  }

  @override
  Future<PullPage> pull({String? since, int limit = 500}) async {
    final resp = await dio.get(
      '/sync/transactions/',
      queryParameters: {if (since != null) 'since': since, 'limit': limit},
    );
    return _pageFrom(resp.data);
  }

  @override
  Future<void> syncWallets({required List<Map<String, dynamic>> wallets}) async {
    await dio.post('/wallets/sync/', data: {'wallets': wallets});
  }

  @override
  Future<PullPage> pullWallets({String? since}) async {
    final resp = await dio.get(
      '/wallets/sync/',
      queryParameters: {if (since != null) 'since': since},
    );
    return _pageFrom(resp.data);
  }

  @override
  Future<void> syncBudgets({required List<Map<String, dynamic>> budgets}) async {
    await dio.post('/budgets/sync/', data: {'budgets': budgets});
  }

  @override
  Future<PullPage> pullBudgets({String? since}) async {
    final resp = await dio.get(
      '/budgets/sync/',
      queryParameters: {if (since != null) 'since': since},
    );
    return _pageFrom(resp.data);
  }

  PullPage _pageFrom(Object? data) {
    final map = Map<String, dynamic>.from(data as Map);
    return PullPage(
      results: ((map['results'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      cursor: map['cursor'] as String?,
      hasMore: map['has_more'] == true,
    );
  }
}
