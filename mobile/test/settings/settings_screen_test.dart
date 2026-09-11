import 'dart:convert';

import 'package:economy/core/sync/sync_service.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/settings/settings_screen.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

void main() {
  final now = DateTime.utc(2026, 9, 11, 9); // ۲۰ شهریور ۱۴۰۵
  late FakeTransactionStore store;
  late DashboardController controller;

  setUp(() async {
    store = FakeTransactionStore(
        clock: () => now, categorizeFrom: DateTime.utc(2026, 9, 22, 20, 30));
    controller = DashboardController(store, clock: () => now);
    await controller.load();
  });

  Future<void> pump(WidgetTester tester, {Future<String> Function()? onSync}) async {
    tester.view.physicalSize = const Size(1170, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: SettingsScreen(controller: controller, onSync: onSync),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('شروع دسته‌بندی نشان داده و قابل تغییر است', (tester) async {
    await pump(tester);
    expect(find.textContaining('۱ مهر ۱۴۰۵'), findsOneWidget);

    await tester.tap(find.byKey(kCategorizeFromTileKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('از اول شهریور ۱۴۰۵ (همین ماه)'));
    await tester.pumpAndSettle();

    expect(controller.categorizeFrom, DateTime.utc(2026, 8, 22, 20, 30));
    expect(find.textContaining('۱ شهریور ۱۴۰۵'), findsOneWidget);
  });

  testWidgets('وضعیت آخرین همگام‌سازی با پیام قابل‌فهم', (tester) async {
    store.settings[SettingKeys.lastSync] = jsonEncode(
      const SyncSummary(synced: 0, failed: 107, error: 'network').toJson(now),
    );
    await controller.load();
    await pump(tester);

    expect(find.textContaining('سرور در دسترس نبود'), findsOneWidget);
    expect(find.textContaining('۱۰۷ تراکنش در صف ماند'), findsOneWidget);
  });

  testWidgets('همگام‌سازی دستی نتیجه را نشان می‌دهد', (tester) async {
    await pump(tester, onSync: () async => 'همگام‌سازی انجام شد: ۲ ارسال، ۰ دریافت');

    await tester.ensureVisible(find.byKey(kSyncNowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kSyncNowKey));
    await tester.pumpAndSettle();
    expect(find.text('همگام‌سازی انجام شد: ۲ ارسال، ۰ دریافت'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('فرستنده‌های پیامک بانک و نمایش متن پیامک', (tester) async {
    await pump(tester);
    expect(find.textContaining('هیچ فرستنده‌ای مجاز نشده'), findsOneWidget);

    await tester.tap(find.byKey(kShowSmsToggleKey));
    await tester.pumpAndSettle();
    expect(controller.showSmsText, isFalse);
    expect(store.settings[SettingKeys.showSmsText], '0');

    await tester.tap(find.byKey(kSettingsSendersKey));
    await tester.pumpAndSettle();
    expect(find.text('فقط پیامک بانک‌ها ثبت شود'), findsOneWidget);
  });
}
