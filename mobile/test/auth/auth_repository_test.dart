import 'package:dio/dio.dart';
import 'package:economy/core/auth/auth_repository.dart';
import 'package:economy/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers/in_memory_token_store.dart';

void main() {
  const baseUrl = 'http://test/api/v1';

  late Dio dio;
  late DioAdapter adapter;
  late InMemoryTokenStore store;
  late AuthRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: baseUrl));
    adapter = DioAdapter(dio: dio);
    store = InMemoryTokenStore();
    final api = ApiClient(baseUrl: baseUrl, tokenStore: store, dioOverride: dio);
    repo = AuthRepository(api, store);
  });

  test('login توکن‌ها را ذخیره می‌کند', () async {
    adapter.onPost(
      '/auth/login/',
      (server) => server.reply(200, {'access': 'a', 'refresh': 'r'}),
      data: {'email': 'a@x.com', 'password': 'p'},
    );
    await repo.login(email: 'a@x.com', password: 'p');
    expect(store.access, 'a');
    expect(store.refresh, 'r');
  });

  test('me پروفایل را برمی‌گرداند', () async {
    store.access = 'a';
    adapter.onGet(
      '/auth/me/',
      (server) => server.reply(200, {
        'id': 'u1',
        'email': 'a@x.com',
        'full_name': 'علی',
      }),
    );
    final user = await repo.me();
    expect(user.email, 'a@x.com');
    expect(user.fullName, 'علی');
  });

  test('register پروفایل را برمی‌گرداند', () async {
    adapter.onPost(
      '/auth/register/',
      (server) => server.reply(201, {
        'id': 'u1',
        'email': 'a@x.com',
        'full_name': 'علی',
      }),
      data: {'email': 'a@x.com', 'password': 'StrongPass123', 'full_name': 'علی'},
    );
    final user = await repo.register(
      email: 'a@x.com',
      password: 'StrongPass123',
      fullName: 'علی',
    );
    expect(user.email, 'a@x.com');
  });

  test('پاسخ 401 باعث تلاش برای تازه‌سازی توکن می‌شود', () async {
    store.access = 'old';
    store.refresh = 'r';
    adapter.onGet('/auth/me/', (server) => server.reply(401, {'detail': 'x'}));
    adapter.onPost(
      '/auth/refresh/',
      (server) => server.reply(200, {'access': 'new', 'refresh': 'r2'}),
      data: {'refresh': 'r'},
    );

    await expectLater(repo.me(), throwsA(isA<DioException>()));
    // رفرش رخ داده و توکن به‌روز شده است
    expect(store.access, 'new');
    expect(store.refresh, 'r2');
  });
}
