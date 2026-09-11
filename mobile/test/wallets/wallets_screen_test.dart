import 'package:economy/core/family/family_api.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/wallets/data/wallet.dart';
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

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: WalletsScreen(controller: controller),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('افزودن کارت از طریق فرم', (tester) async {
    await pump(tester);
    expect(find.byKey(kWalletsEmptyKey), findsOneWidget);

    await tester.tap(find.byKey(kWalletAddFabKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kWalletOwnerFieldKey), 'بابا');
    await tester.enterText(find.byKey(kWalletLabelFieldKey), 'کارت حقوق');
    await tester.enterText(find.byKey(kWalletCardFieldKey), '1234');
    await tester.tap(find.byKey(kWalletSaveKey));
    await tester.pumpAndSettle();

    expect(controller.wallets, hasLength(1));
    expect(find.text('بابا'), findsOneWidget); // سرتیتر صاحب
    expect(find.text('کارت حقوق'), findsOneWidget);
  });

  testWidgets('فرم ناقص پیام خطا می‌دهد (بی‌صدا رد نمی‌شود)', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(kWalletAddFabKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kWalletOwnerFieldKey), 'بابا');
    await tester.enterText(find.byKey(kWalletLabelFieldKey), 'کارت');
    await tester.tap(find.byKey(kWalletSaveKey));
    await tester.pumpAndSettle();

    expect(find.byKey(kWalletErrorKey), findsOneWidget);
    expect(controller.wallets, isEmpty);
  });

  testWidgets('صاحب کارت از اعضای خانواده انتخاب می‌شود', (tester) async {
    store.settings[SettingKeys.meUserId] = 'u-me';
    store.settings[SettingKeys.familyMembers] = FamilyMember.encodeList(const [
      FamilyMember(id: 'u-me', name: 'مهدی'),
      FamilyMember(id: 'u-father', name: 'بابا'),
    ]);
    await controller.load();
    await pump(tester);

    await tester.tap(find.byKey(kWalletAddFabKey));
    await tester.pumpAndSettle();
    expect(find.text('مهدی (من)'), findsOneWidget);
    await tester.tap(find.text('بابا'));
    await tester.pumpAndSettle();
    expect(find.byKey(kWalletOwnerFieldKey), findsNothing); // نام از عضو می‌آید

    await tester.enterText(find.byKey(kWalletLabelFieldKey), 'کارت حقوق');
    await tester.enterText(find.byKey(kWalletCardFieldKey), '1234');
    await tester.tap(find.byKey(kWalletSaveKey));
    await tester.pumpAndSettle();

    final w = controller.wallets.single;
    expect(w.ownerName, 'بابا');
    expect(w.ownerUserId, 'u-father');
    expect(find.text('عضو اپ'), findsOneWidget);
  });

  testWidgets('ویرایش کارت', (tester) async {
    await store.addWallet(
        const Wallet(id: '', ownerName: 'مامان', label: 'کارت خانه', cardLast4: '5555'));
    await controller.load();
    await pump(tester);

    await tester.tap(find.text('کارت خانه'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kWalletLabelFieldKey), 'کارت خرید');
    await tester.tap(find.byKey(kWalletSaveKey));
    await tester.pumpAndSettle();

    expect(controller.wallets.single.label, 'کارت خرید');
    expect(find.text('کارت خرید'), findsOneWidget);
  });

  testWidgets('کارت تازه پیش‌فرض مال خود کاربر است', (tester) async {
    store.settings[SettingKeys.meUserId] = 'u-me';
    store.settings[SettingKeys.familyMembers] = FamilyMember.encodeList(const [
      FamilyMember(id: 'u-me', name: 'مهدی'),
      FamilyMember(id: 'u-father', name: 'بابا'),
    ]);
    await controller.load();
    await pump(tester);

    await tester.tap(find.byKey(kWalletAddFabKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kWalletOwnerFieldKey), findsNothing); // «من» انتخاب است
    await tester.enterText(find.byKey(kWalletLabelFieldKey), 'کارت من');
    await tester.enterText(find.byKey(kWalletCardFieldKey), '4321');
    await tester.tap(find.byKey(kWalletSaveKey));
    await tester.pumpAndSettle();

    final w = controller.wallets.single;
    expect(w.ownerUserId, 'u-me');
    expect(w.ownerName, 'مهدی');
  });
}
