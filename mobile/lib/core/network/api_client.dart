/// کلاینت HTTP (Dio) با interceptor برای الصاق توکن و تازه‌سازی خودکار روی 401.
library;

import 'package:dio/dio.dart';

import '../auth/token_store.dart';

enum _Refresh { ok, rejected, failed }

class ApiClient {
  final Dio dio;
  final TokenStore tokenStore;

  /// سرور دیگر این نشست را نمی‌پذیرد (کاربر حذف/غیرفعال شده یا توکن باطل است) →
  /// اپ باید به صفحه‌ی ورود برگردد. در قطعی شبکه صدا زده نمی‌شود.
  void Function()? onSessionExpired;

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
    if (!is401 || skipAuth) return handler.next(err);

    if (alreadyRetried) {
      // با توکنِ تازه هم رد شد (مثلاً کاربر در پنل حذف شده).
      onSessionExpired?.call();
      return handler.next(err);
    }

    switch (await _tryRefresh()) {
      case _Refresh.ok:
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
      case _Refresh.rejected:
        onSessionExpired?.call();
        return handler.next(err);
      case _Refresh.failed:
        return handler.next(err);
    }
  }

  Future<_Refresh> _tryRefresh() async {
    final refresh = await tokenStore.readRefresh();
    if (refresh == null) return _Refresh.rejected;
    try {
      final resp = await dio.post(
        '/auth/refresh/',
        data: {'refresh': refresh},
        options: Options(extra: {'skipAuth': true}),
      );
      final access = resp.data['access'] as String?;
      if (access == null) return _Refresh.failed;
      // simplejwt با ROTATE_REFRESH_TOKENS، refresh جدید هم می‌دهد.
      final newRefresh = resp.data['refresh'] as String? ?? refresh;
      await tokenStore.saveTokens(access: access, refresh: newRefresh);
      return _Refresh.ok;
    } on DioException catch (e) {
      // سرور جواب داد و refresh را نپذیرفت → نشست باطل؛ بی‌جواب (شبکه) → فقط شکست.
      final code = e.response?.statusCode;
      return (code == 400 || code == 401) ? _Refresh.rejected : _Refresh.failed;
    } catch (_) {
      return _Refresh.failed;
    }
  }
}
