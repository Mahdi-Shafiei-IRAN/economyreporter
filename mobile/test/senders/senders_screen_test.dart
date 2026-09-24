import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/senders/senders_screen.dart';
import 'package:economy/features/transactions/transaction_details_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

void main() {
  final now = DateTime.utc(2026, 9, 11, 9); // ۲۰ شهریور ۱۴۰۵
  late FakeTransactionStore store;
  late DashboardController controller;

  setUp(() async {
    store = FakeTransactionStore(clock: () => now);
    controller = DashboardController(store, clock: () => now)
      ..readInbox = () async => [
            RawSms(
                sender: 'BankMellat',
                body: 'خرید مبلغ 50,000 ریال از کارت 1234',
                receivedAt: now),
            RawSms(
                sender: 'Digikala',
                body: 'خرید مبلغ 990,000 ریال با کد تخفیف',
                receivedAt: now),
          ];
    // پیش از تعیین فرستنده‌ها، پیامک فروشگاه اشتباهی هزینه ثبت شده بود.
    const body = 'خرید مبلغ 990,000 ریال با کد تخفیف';
    store.seed(const SmsParser().parse(sender: 'Digikala', body: body),
        sender: 'Digikala', receivedAt: now);
    await controller.load();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.light),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: SendersScreen(controller: controller),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> drainSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('فهرست خالی هشدار می‌دهد و پیشنهادها از پیامک‌های گوشی می‌آیند',
      (tester) async {
    await pump(tester);

    expect(find.byKey(kSendersEmptyKey), findsOneWidget);
    expect(find.byKey(const ValueKey('candidate-BankMellat')), findsOneWidget);
    expect(find.byKey(const ValueKey('candidate-Digikala')), findsOneWidget);
    expect(find.text('احتمالاً بانک ملت'), findsOneWidget);
  });

  testWidgets('«مجاز کن»: فرستنده به فهرست می‌رود و صندوق دوباره خوانده می‌شود',
      (tester) async {
    var reimported = 0;
    controller.onSendersChanged = () async => reimported++;
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('allow-BankMellat')));
    await tester.pumpAndSettle();
    // دیالوگِ انتخاب بانک (پیش‌فرض: بانکِ حدس‌زده‌شده = ملت) را تأیید کن.
    await tester.tap(find.byKey(const Key('bank-pick-confirm')));
    await tester.pumpAndSettle();

    expect(controller.allowedSenders.single.address, 'BankMellat');
    expect(controller.allowedSenders.single.bankId, 'mellat');
    expect(reimported, 1);
    expect(find.byKey(const ValueKey('allowed-BankMellat')), findsOneWidget);
    expect(find.byKey(const ValueKey('candidate-BankMellat')), findsNothing);
    expect(find.byKey(kSendersEmptyKey), findsNothing);
    await drainSnackBar(tester);
  });

  testWidgets('«بانک نیست»: تراکنش‌های اشتباهیِ آن فرستنده حذف و از جمع بیرون می‌روند',
      (tester) async {
    await pump(tester);
    expect(controller.summary.expenseRial, 990000);

    await tester.tap(find.byKey(const ValueKey('reject-Digikala')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kConfirmInvalidKey));
    await tester.pumpAndSettle();

    expect(await store.getAll(), isEmpty);
    expect(controller.summary.expenseRial, 0);
    expect(find.byKey(const ValueKey('reject-Digikala')), findsNothing);
    await drainSnackBar(tester);
  });

  testWidgets('افزودن دستی با حدس بانک از نام فرستنده', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(kSendersAddKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kSenderAddressFieldKey), 'Saman');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kSenderSaveKey));
    await tester.pumpAndSettle();

    expect(controller.allowedSenders.single.address, 'Saman');
    expect(controller.allowedSenders.single.bankId, 'saman');
  });

  testWidgets('خواندنِ دوباره‌ی همه‌ی پیامک‌ها + برداشتنِ فرستنده همراهِ تراکنش‌هایش',
      (tester) async {
    await controller.addAllowedSender('BankMellat', bankId: 'mellat');
    store.seed(
        const SmsParser().parse(
            sender: 'BankMellat', body: 'خرید مبلغ 50,000 ریال از کارت 1234', bankId: 'mellat'),
        sender: 'BankMellat',
        receivedAt: now);
    var rescans = 0;
    controller.importWholeInbox = () async {
      rescans++;
      return 3;
    };
    await controller.load();
    await pump(tester);

    expect(
        find.descendant(
            of: find.byKey(const ValueKey('allowed-BankMellat')),
            matching: find.textContaining('۱ تراکنش')),
        findsOneWidget);
    await tester.tap(find.byKey(kSendersRescanKey));
    await tester.pumpAndSettle();
    expect(rescans, 1);
    expect(find.textContaining('۳ تراکنشِ تازه'), findsOneWidget);
    await drainSnackBar(tester);

    await tester.tap(find.byTooltip('برداشتن از فهرست'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sender-remove-with-tx')));
    await tester.pumpAndSettle();
    expect(controller.allowedSenders, isEmpty);
    expect(controller.transactionsOfSender('BankMellat'), isEmpty);
  });
}
