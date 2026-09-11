import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/wallets/wallets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

void main() {
  late FakeTransactionStore store;
  late DashboardController controller;

  setUp(() async {
    store = FakeTransactionStore();
    controller = DashboardController(store);
    await controller.load();
  });

  testWidgets('افزودن کیف از طریق فرم', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: WalletsScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kWalletsEmptyKey), findsOneWidget);

    await tester.tap(find.byKey(kWalletAddFabKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(kWalletOwnerFieldKey), 'بابا');
    await tester.enterText(find.byKey(kWalletLabelFieldKey), 'کارت حقوق');
    await tester.enterText(find.byKey(kWalletCardFieldKey), '1234');
    await tester.tap(find.byKey(kWalletSaveKey));
    await tester.pumpAndSettle();

    expect(controller.wallets, hasLength(1));
    expect(find.text('بابا • کارت حقوق'), findsOneWidget);
  });
}
