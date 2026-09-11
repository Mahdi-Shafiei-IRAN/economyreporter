import 'package:dio/dio.dart';
import 'package:economy/core/auth/auth_repository.dart';
import 'package:economy/core/network/api_client.dart';
import 'package:economy/features/auth/auth_controller.dart';
import 'package:economy/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

import '../helpers/in_memory_token_store.dart';

void main() {
  const baseUrl = 'http://test/api/v1';

  ({AuthController controller, InMemoryTokenStore store, DioAdapter adapter}) build() {
    final dio = Dio(BaseOptions(baseUrl: baseUrl));
    final adapter = DioAdapter(dio: dio);
    final store = InMemoryTokenStore();
    final api = ApiClient(baseUrl: baseUrl, tokenStore: store, dioOverride: dio);
    final controller = AuthController(AuthRepository(api, store));
    return (controller: controller, store: store, adapter: adapter);
  }

  Widget wrap(AuthController c) => MaterialApp(home: LoginScreen(controller: c));

  testWidgets('ورود با شماره موبایل و رمز وضعیت را authenticated می‌کند', (tester) async {
    final ctx = build();
    ctx.adapter.onPost(
      '/auth/login/',
      (server) => server.reply(200, {'access': 'a', 'refresh': 'r'}),
      data: {'phone': '09121234567', 'password': 'secret'},
    );

    await tester.pumpWidget(wrap(ctx.controller));
    await tester.enterText(find.byKey(kPhoneFieldKey), '09121234567');
    await tester.enterText(find.byKey(kPasswordFieldKey), 'secret');
    await tester.tap(find.byKey(kLoginButtonKey));
    await tester.pumpAndSettle();

    expect(ctx.controller.authenticated, isTrue);
    expect(ctx.store.access, 'a');
    expect(find.byKey(kLoginErrorKey), findsNothing);
  });

  testWidgets('شماره با ارقام فارسی هم پذیرفته می‌شود', (tester) async {
    final ctx = build();
    ctx.adapter.onPost(
      '/auth/login/',
      (server) => server.reply(200, {'access': 'a', 'refresh': 'r'}),
      data: {'phone': '09121234567', 'password': 'secret'},
    );

    await tester.pumpWidget(wrap(ctx.controller));
    await tester.enterText(find.byKey(kPhoneFieldKey), ' ۰۹۱۲۱۲۳۴۵۶۷ ');
    await tester.enterText(find.byKey(kPasswordFieldKey), 'secret');
    await tester.tap(find.byKey(kLoginButtonKey));
    await tester.pumpAndSettle();

    expect(ctx.controller.authenticated, isTrue);
  });

  testWidgets('ورود ناموفق پیام خطا نشان می‌دهد', (tester) async {
    final ctx = build();
    ctx.adapter.onPost(
      '/auth/login/',
      (server) => server.reply(401, {'detail': 'no'}),
      data: {'phone': '09121234567', 'password': 'wrong'},
    );

    await tester.pumpWidget(wrap(ctx.controller));
    await tester.enterText(find.byKey(kPhoneFieldKey), '09121234567');
    await tester.enterText(find.byKey(kPasswordFieldKey), 'wrong');
    await tester.tap(find.byKey(kLoginButtonKey));
    await tester.pumpAndSettle();

    expect(ctx.controller.authenticated, isFalse);
    expect(find.text('شماره موبایل یا رمز عبور اشتباه است'), findsOneWidget);
  });

  testWidgets('خروج اجباری (نشست نامعتبر یا حساب قدیمی) با پیام روی صفحه‌ی ورود',
      (tester) async {
    final ctx = build();
    ctx.store.access = 'a';
    ctx.store.refresh = 'r';
    await ctx.controller.bootstrap();
    expect(ctx.controller.authenticated, isTrue);

    await ctx.controller.expireSession('ورود حالا با شماره موبایل است؛ دوباره وارد شو.');

    expect(ctx.controller.authenticated, isFalse);
    expect(ctx.store.access, isNull);
    await tester.pumpWidget(wrap(ctx.controller));
    expect(find.text('ورود حالا با شماره موبایل است؛ دوباره وارد شو.'), findsOneWidget);
  });
}
