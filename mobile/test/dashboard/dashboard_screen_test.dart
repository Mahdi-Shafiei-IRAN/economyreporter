import 'package:economy/core/format/money_format.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/dashboard/dashboard_screen.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/edit_transaction_sheet.dart';
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

  testWidgets('نشان بازبینی تعداد موارد را نشان می‌دهد', (tester) async {
    store.seed(parser.parse(sender: 'Digikala', body: 'خرید مبلغ 100,000 ریال'),
        sender: 'Digikala');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(kReviewActionKey),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ویرایش تراکنش از طریق ضربه روی ردیف جمع را به‌روز می‌کند',
      (tester) async {
    store.seed(
        parser.parse(
            sender: 'BankMellat', body: 'خرید مبلغ 3,000,000 ریال از کارت 1234'),
        sender: 'BankMellat');

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    // مبلغ را به ۵۰۰٬۰۰۰ تومان (۵٬۰۰۰٬۰۰۰ ریال) تغییر بده
    await tester.enterText(find.byKey(kEditAmountKey), '500000');
    await tester.tap(find.byKey(kEditSaveKey));
    await tester.pumpAndSettle();

    expect(textOfKey(tester, kExpenseValueKey), formatToman(5000000));
  });

  testWidgets('بنر تطبیق مانده هنگام وجود گپ نشان داده می‌شود', (tester) async {
    final at = DateTime.utc(2026, 1, 1, 12, 0);
    store.addRecord(TransactionRecord(
      id: 'a',
      cardLast4: '1234',
      kind: 'income',
      amountRial: 0,
      balanceAfterRial: 1000000,
      transactionDate: at,
      createdAt: at,
      updatedAt: at,
    ));
    store.addRecord(TransactionRecord(
      id: 'b',
      cardLast4: '1234',
      kind: 'expense',
      amountRial: 200000,
      balanceAfterRial: 500000, // انتظار 800000 → گپ
      transactionDate: at.add(const Duration(minutes: 1)),
      createdAt: at,
      updatedAt: at,
    ));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(kReconcileBannerKey), findsOneWidget);
  });
}
