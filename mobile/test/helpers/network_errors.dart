/// خطاهای واقعیِ Dio برای fakeها (همان چیزی که روی گوشی رخ می‌دهد).
library;

import 'package:dio/dio.dart';

/// وصل نشدن به سرور (اینترنت قطع/سرور خاموش).
DioException networkDown() => DioException(
      requestOptions: RequestOptions(path: '/'),
      type: DioExceptionType.connectionError,
    );

/// سرور جواب داد ولی با خطا (مثلاً ۴۰۰/۴۰۴/۵۰۰).
DioException httpError(int status, [Object? data]) {
  final req = RequestOptions(path: '/');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: req, statusCode: status, data: data),
  );
}
