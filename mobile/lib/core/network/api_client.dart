/// کلاینت HTTP (Dio) با interceptor برای الصاق توکن و تازه‌سازی خودکار روی 401.
library;

import 'package:dio/dio.dart';

import '../auth/token_store.dart';

class ApiClient {
  final Dio dio;
  final TokenStore tokenStore;

  ApiClient({
    required String baseUrl,
    required this.tokenStore,
    Dio? dioOverride,
  }) : dio = dioOverride ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              contentType: 'application/json',
            )) {
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipAuth'] != true) {
      final token = await tokenStore.readAccess();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final is401 = err.response?.statusCode == 401;
    final alreadyRetried = err.requestOptions.extra['retried'] == true;
    final skipAuth = err.requestOptions.extra['skipAuth'] == true;

    if (is401 && !alreadyRetried && !skipAuth && await _tryRefresh()) {
      final options = err.requestOptions;
      options.extra['retried'] = true;
      final token = await tokenStore.readAccess();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      try {
        final response = await dio.fetch(options);
        return handler.resolve(response);
      } on DioException catch (e) {
        return handler.next(e);
      }
    }
    handler.next(err);
  }

  Future<bool> _tryRefresh() async {
    final refresh = await tokenStore.readRefresh();
    if (refresh == null) return false;
    try {
      final resp = await dio.post(
        '/auth/refresh/',
        data: {'refresh': refresh},
        options: Options(extra: {'skipAuth': true}),
      );
      final access = resp.data['access'] as String?;
      if (access == null) return false;
      // simplejwt با ROTATE_REFRESH_TOKENS، refresh جدید هم می‌دهد.
      final newRefresh = resp.data['refresh'] as String? ?? refresh;
      await tokenStore.saveTokens(access: access, refresh: newRefresh);
      return true;
    } catch (_) {
      return false;
    }
  }
}
