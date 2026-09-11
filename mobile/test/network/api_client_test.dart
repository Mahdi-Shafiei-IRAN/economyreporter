import 'package:dio/dio.dart';
import 'package:economy/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers/in_memory_token_store.dart';

/// وقتی سرور نشست را نمی‌پذیرد (کاربر حذف/غیرفعال شد) اپ باید به صفحه‌ی ورود برگردد؛
/// ولی قطعی شبکه نباید کاربر را بیرون کند.
void main() {
  const baseUrl = 'http://test/api/v1';

  late Dio dio;
  late DioAdapter adapter;
  late InMemoryTokenStore store;
  late int expired;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: baseUrl));
    adapter = DioAdapter(dio: dio);
    store = InMemoryTokenStore()
      ..access = 'old'
      ..refresh = 'r';
    final api = ApiClient(baseUrl: baseUrl, tokenStore: store, dioOverride: dio);
    expired = 0;
    api.onSessionExpired = () => expired++;
  });

  test('refresh رد شد (کاربر غیرفعال یا توکن باطل) → خروج', () async {
    adapter.onGet('/auth/me/', (server) => server.reply(401, {'detail': 'x'}));
    adapter.onPost(
      '/auth/refresh/',
      (server) => server.reply(401, {'detail': 'token not valid'}),
      data: {'refresh': 'r'},
    );

    await expectLater(dio.get('/auth/me/'), throwsA(isA<DioException>()));
    expect(expired, 1);
  });

  test('با توکنِ تازه هم ۴۰۱ (کاربر در پنل حذف شده) → خروج', () async {
    adapter.onGet('/auth/me/', (server) => server.reply(401, {'detail': 'User not found'}));
    adapter.onPost(
      '/auth/refresh/',
      (server) => server.reply(200, {'access': 'new', 'refresh': 'r2'}),
      data: {'refresh': 'r'},
    );

    await expectLater(dio.get('/auth/me/'), throwsA(isA<DioException>()));
    expect(expired, 1);
  });

  test('قطعی شبکه هنگام refresh → کاربر بیرون نمی‌رود', () async {
    adapter.onGet('/auth/me/', (server) => server.reply(401, {'detail': 'x'}));
    adapter.onPost(
      '/auth/refresh/',
      (server) => server.throws(
        0,
        DioException.connectionError(
          requestOptions: RequestOptions(path: '/auth/refresh/'),
          reason: 'offline',
        ),
      ),
      data: {'refresh': 'r'},
    );

    await expectLater(dio.get('/auth/me/'), throwsA(isA<DioException>()));
    expect(expired, 0);
    expect(store.access, 'old');
  });
}
