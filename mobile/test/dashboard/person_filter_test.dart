import 'package:economy/core/format/money_format.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/dashboard/dashboard_screen.dart';
import 'package:economy/features/senders/senders_screen.dart';
import 'package:economy/features/transactions/transaction_details_sheet.dart';
import 'package:economy/features/transactions/widgets/summary_card.dart';
import 'package:economy/features/transactions/widgets/tx_widgets.dart';
import 'package:economy/features/wallets/data/wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

void main() {
  const parser = SmsParser();
  final now = DateTime.utc(2026, 9, 11, 9); // ۲۰ شهریور ۱۴۰۵

  late FakeTransactionStore store;
  late DashboardController controller;

  setUp(() async {
    store = FakeTransactionStore(clock: () => now);
    controller = DashboardController(store, clock: () => now);
    await store.addWallet(const Wallet(
        id: '', ownerName: 'بابا', label: 'کارت حقوق', cardLast4: '1234'));
    await store.addWallet(const Wallet(
        id: '', ownerName: 'مامان', label: 'کارت خانه', cardLast4: '5678'));
    void seed(String body, DateTime at) => store.seed(
        parser.parse(sender: 'BankMellat', body: body),
        sender: 'BankMellat',
        receivedAt: at);
    seed('واریز مبلغ 10,000,000 ریال به کارت 1234', DateTime.utc(2026, 9, 10, 8));
    seed('خرید مبلغ 3,000,000 ریال از کارت 1234', DateTime.utc(2026, 9, 10, 9));
    seed('خرید مبلغ 2,000,000 ریال از کارت 5678', DateTime.utc(2026, 9, 10, 10));
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

  String textOf(WidgetTester tester, Key key) => tester.widget<Text>(find.byKey(key)).data!;

  testWidgets('انتخاب «بابا»: خالصِ بالای صفحه و فهرست فقط مال بابا (در هر دو نما)',
      (tester) async {
    await pumpApp(tester);
    expect(textOf(tester, kBalanceValueKey), formatToman(5000000));

    await tester.tap(find.byKey(const ValueKey('person-chip-بابا')));
    await tester.pumpAndSettle();

    expect(textOf(tester, kSummaryTitleKey), 'خالص بابا • شهریور ۱۴۰۵');
    expect(textOf(tester, kIncomeValueKey), formatToman(10000000));
    expect(textOf(tester, kExpenseValueKey), formatToman(3000000));
    expect(textOf(tester, kBalanceValueKey), formatToman(7000000));
    expect(find.byKey(const ValueKey('person-مامان')), findsNothing);
    expect(find.byType(TransactionTile), findsNWidgets(2));

    await tester.tap(find.text('همه با هم'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionTile), findsNWidgets(2));
    expect(textOf(tester, kBalanceValueKey), formatToman(7000000));

    await tester.tap(find.byKey(const ValueKey('person-chip-all')));
    await tester.pumpAndSettle();
    expect(textOf(tester, kBalanceValueKey), formatToman(5000000));
    expect(find.byType(TransactionTile), findsNWidgets(3));
  });

  testWidgets('متن پیامک روی هر تراکنش دیده می‌شود و در تنظیمات خاموش می‌شود',
      (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('BankMellat: خرید مبلغ 3,000,000 ریال'), findsOneWidget);

    await controller.setShowSmsText(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('BankMellat: خرید مبلغ 3,000,000 ریال'), findsNothing);
  });

  testWidgets('تا فرستنده‌ی بانکی مشخص نشده، تراشه‌ی راهنما صفحه‌اش را باز می‌کند',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(kSendersChipKey));
    await tester.pumpAndSettle();
    expect(find.byType(SendersScreen), findsOneWidget);
  });

  testWidgets('جزئیات: متن کامل پیامک، و حذفِ تراکنش اشتباهی', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byType(TransactionTile).first);
    await tester.pumpAndSettle();
    expect(find.byKey(kDetailsSmsKey), findsOneWidget);

    await tester.tap(find.byKey(kDetailsDeleteKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kConfirmInvalidKey));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionTile), findsNWidgets(2));
  });
}
