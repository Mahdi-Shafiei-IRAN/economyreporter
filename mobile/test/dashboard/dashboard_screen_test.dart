import 'package:economy/core/format/money_format.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/dashboard/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

void main() {
  const parser = SmsParser();

  late FakeTransactionStore store;
  late DashboardController controller;

  setUp(() {
    store = FakeTransactionStore();
    controller = DashboardController(store);
  });

  Widget app() => MaterialApp(home: DashboardScreen(controller: controller));

  String textOfKey(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).data!;

  Future<void> addViaFab(WidgetTester tester, String sender, String body) async {
    await tester.tap(find.byKey(kAddSmsFabKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kSmsSenderFieldKey), sender);
    await tester.enterText(find.byKey(kSmsBodyFieldKey), body);
    await tester.tap(find.byKey(kSmsSaveButtonKey));
    await tester.pumpAndSettle();
  }

  testWidgets('حالت خالی: پیام خالی و جمع صفر', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(kEmptyStateKey), findsOneWidget);
    expect(textOfKey(tester, kIncomeValueKey), formatToman(0));
    expect(textOfKey(tester, kExpenseValueKey), formatToman(0));
    expect(textOfKey(tester, kBalanceValueKey), formatToman(0));
  });

  testWidgets('جمع و لیست با داده‌ی اولیه', (tester) async {
    store.seed(parser.parse(sender: 'ملی', body: 'واریز مبلغ 10,000,000 ریال'),
        sender: 'ملی');
    store.seed(
        parser.parse(
            sender: 'BankMellat', body: 'خرید مبلغ 3,000,000 ریال از کارت 1234'),
        sender: 'BankMellat');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(textOfKey(tester, kIncomeValueKey), formatToman(10000000));
    expect(textOfKey(tester, kExpenseValueKey), formatToman(3000000));
    expect(textOfKey(tester, kBalanceValueKey), formatToman(7000000));

    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.textContaining('بانک ملت'), findsOneWidget);
    expect(find.textContaining('کارت 1234'), findsOneWidget);
    expect(find.byKey(kEmptyStateKey), findsNothing);
  });

  testWidgets('افزودن پیامک از طریق FAB جمع و لیست را به‌روز می‌کند', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await addViaFab(tester, 'BankMellat', 'برداشت مبلغ 2,000,000 ریال از کارت 1234');

    expect(textOfKey(tester, kExpenseValueKey), formatToman(2000000));
    expect(textOfKey(tester, kBalanceValueKey), formatToman(-2000000));
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('تراکنش ثبت شد.'), findsOneWidget);

    // تخلیه‌ی تایمر اسنک‌بار تا تست تایمر معلق ندهد
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('افزودن پیامک تکراری رکورد دوم نمی‌سازد', (tester) async {
    const sender = 'BankMellat';
    const body = 'برداشت مبلغ 900,000 ریال از کارت 1234';

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // افزودن اول → یک تراکنش
    await addViaFab(tester, sender, body);
    expect(find.byType(ListTile), findsOneWidget);

    // افزودن دوم با همان محتوا و همان ساعتِ FakeAsync → باید تکراری تشخیص داده شود
    await addViaFab(tester, sender, body);
    expect(find.byType(ListTile), findsOneWidget); // هنوز فقط یک تراکنش

    // تخلیه‌ی تایمرهای اسنک‌بار
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
