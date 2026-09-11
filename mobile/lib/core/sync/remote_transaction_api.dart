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
    final data = Map<String, dynamic>.from(resp.data as Map);
    return PullPage(
      results: ((data['results'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      cursor: data['cursor'] as String?,
      hasMore: data['has_more'] == true,
    );
  }
}
