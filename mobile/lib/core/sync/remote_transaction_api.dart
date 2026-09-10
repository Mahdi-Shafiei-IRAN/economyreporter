/// کلاینت endpoint همگام‌سازی سرور. اینترفیس تزریق‌پذیر تا در تست fake شود.
library;

import 'package:dio/dio.dart';

abstract class RemoteTransactionApi {
  /// یک دسته تراکنش را می‌فرستد و لیست نتیجه‌ی هر آیتم را برمی‌گرداند
  /// (`{id, status}` که status یکی از created/already_exists/error است).
  Future<List<Map<String, dynamic>>> syncBatch({
    required String deviceId,
    required List<Map<String, dynamic>> transactions,
  });
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
}
