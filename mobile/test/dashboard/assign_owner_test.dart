import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/dashboard/dashboard_screen.dart';
import 'package:economy/features/wallets/wallets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

/// «تعیین صاحب» برای کارتی که پیامک‌هایش شماره‌ی کارت/حساب ندارند.
void main() {
  final now = DateTime.utc(2026, 9, 11, 9);
  late FakeTransactionStore store;
  late DashboardController controller;

  setUp(() {
    store = FakeTransactionStore(clock: () => now);
    controller = DashboardController(store, clock: () => now);
    const body = 'بلو\nخرید 250,000 ریال\nمانده 1,000,000';
    store.seed(const SmsParser().parse(sender: 'Blu', body: body),
        sender: 'Blu', receivedAt: DateTime.utc(2026, 9, 10));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: DashboardScreen(controller: controller),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('کارتِ بی‌شماره: ذخیره می‌شود و تراکنش‌ها زیر همان شخص می‌روند',
      (tester) async {
    await pumpApp(tester);
    expect(find.text('تعیین صاحب'), findsOneWidget);

    await tester.tap(find.text('تعیین صاحب'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kWalletOwnerFieldKey), 'مامان');
    await tester.enterText(find.byKey(kWalletLabelFieldKey), 'حساب بلو');
    await tester.tap(find.byKey(kWalletSaveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(kWalletErrorKey), findsNothing);
    expect(find.byKey(const ValueKey('person-مامان')), findsOneWidget);
    expect(find.text('تعیین صاحب'), findsNothing);
  });

  testWidgets('پیامکِ بی‌بانک و بی‌شماره: به‌جای «تعیین صاحب» راهنمای فرستنده', (tester) async {
    const body = 'خرید مبلغ 990,000 ریال با کد تخفیف';
    store.seed(const SmsParser().parse(sender: 'Digikala', body: body),
        sender: 'Digikala', receivedAt: DateTime.utc(2026, 9, 10, 1));
    await pumpApp(tester);

    expect(find.text('تعیین صاحب'), findsOneWidget); // فقط برای کارتِ بلو
    expect(find.textContaining('بدون بانک'), findsOneWidget);
  });
}
