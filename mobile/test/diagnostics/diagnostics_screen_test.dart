import 'package:economy/core/format/money_format.dart';
import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/diagnostics/diagnostics_screen.dart';
import 'package:economy/features/settings/settings_screen.dart';
import 'package:economy/features/transactions/data/period.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/transactions/widgets/summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

// ۱ مهر ۱۴۰۵، ظهر.
final _now = DateTime.utc(2026, 9, 23, 12);

const _digipayBody =
    'پرداخت بدهی و شارژ اعتبار دیجی‌پی\nاعتبار قابل مصرف: ۵۰٬۰۰۰٬۰۰۰ ریال';

TransactionRecord _mellat(String id,
        {required String kind, required int amount, required int balance, required DateTime at}) =>
    TransactionRecord(
      id: id,
      bankId: 'mellat',
      kind: kind,
      amountRial: amount,
      balanceAfterRial: balance,
      accountRef: '1000000009',
      transactionDate: at,
      createdAt: at,
      updatedAt: at,
    );

void main() {
  late FakeTransactionStore store;
  late DashboardController controller;
  late List<RawSms> inbox;

  setUp(() async {
    store = FakeTransactionStore(clock: () => _now);
    await store.addAllowedSender('DigiPay');
    // موجودیِ اولِ مهر: ۱۰ میلیون ریال (شهریور)
    store.addRecord(_mellat('o',
        kind: 'income', amount: 1, balance: 10000000, at: DateTime.utc(2026, 9, 10)));
    // واریزی که «برداشت» ثبت شده: مانده بالا رفته
    store.addRecord(_mellat('x',
        kind: 'expense', amount: 2000000, balance: 12000000, at: DateTime.utc(2026, 9, 23, 8)));
    inbox = [RawSms(sender: 'DigiPay', body: _digipayBody, receivedAt: _now)];
    // ثبتِ قدیمی (پیش از قانونِ «شماره حساب/کارت»)، مثلِ داده‌ی فعلیِ گوشی.
    await store.saveParsed(const SmsParser().parse(sender: 'DigiPay', body: _digipayBody),
        sender: 'DigiPay', receivedAt: _now);

    controller = DashboardController(store, clock: () => _now);
    controller.readInbox = () async => inbox;
    await controller.load();

    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1170, 4200);
    view.devicePixelRatio = 3;
  });
  tearDown(() =>
      TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!.reset());

  Widget app(Widget home) => MaterialApp(
        theme: buildAppTheme(Brightness.light),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: home,
      );

  test('جدولِ موجودی همان عددِ کارتِ خلاصه را توضیح می‌دهد', () {
    expect(controller.period, const Period.month(1405, 7));
    final b = controller.balanceBreakdown();
    expect(b.openingRial, controller.openingBalance);
    expect(b.expectedClosingRial, controller.closingBalance);
    // ۱۰م − ۲م − ۵۰م(دیجی‌پی، بدون مانده) در برابرِ ۱۲م طبق بانک + −۵۰م دیجی‌پی
    expect(b.diffRial, 4000000);
  });

  test('کارتِ خلاصه: موجودی طبقِ بانک و مغایرت از همان جدولِ عیب‌یابی', () {
    final b = controller.balanceBreakdown();
    expect(controller.bankBalance, b.bankClosingRial);
    expect(controller.balanceDiscrepancy, 4000000);
    controller.setPerson('کسی که نیست');
    expect(controller.balanceDiscrepancy, 0);
  });

  testWidgets('زبانه‌ی موجودی: اختلافِ کارتِ خلاصه با بانک', (tester) async {
    await tester.pumpWidget(app(DiagnosticsScreen(controller: controller)));
    await tester.pumpAndSettle();

    // کارتِ «وضعیتِ کلیِ این گوشی» بالای صفحه است؛ بقیه با اسکرول.
    final list = find
        .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .first;
    await tester.scrollUntilVisible(find.byKey(kDiagBalanceDiffKey), 300, scrollable: list);
    final diff = tester.widget<Text>(find.byKey(kDiagBalanceDiffKey));
    expect(diff.data, formatToman(4000000));
    for (var i = 0; i < 20 && find.textContaining('بدون شماره کارت/حساب').evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('بدون شماره کارت/حساب'), findsWidgets);
  });

  testWidgets('زبانه‌ی زنجیره: واریزِ برداشت‌خوانده‌شده «نوع برعکس» است', (tester) async {
    await tester.pumpWidget(app(DiagnosticsScreen(controller: controller, initialTab: 1)));
    await tester.pumpAndSettle();

    expect(find.textContaining('نوع برعکس ثبت شده — '), findsOneWidget);
    expect(find.textContaining('بانک می‌گوید واریز بوده'), findsOneWidget);
  });

  testWidgets('زبانه‌ی پیامک‌ها: دیجی‌پی شمرده شده ولی قانونِ جدید ردش می‌کند', (tester) async {
    await tester.pumpWidget(app(DiagnosticsScreen(controller: controller, initialTab: 2)));
    await tester.pumpAndSettle();

    expect(find.text(_digipayBody), findsOneWidget);
    expect(find.text('شمرده شد'), findsOneWidget);
    expect(find.text('قانون: رد — شماره حساب/کارت ندارد'), findsOneWidget);
    expect(find.textContaining('۱ تراکنشِ ثبت‌شده با قانون نمی‌خواند'), findsOneWidget);

    await tester.tap(find.text('شمرده‌شده').last);
    await tester.pumpAndSettle();
    expect(find.text(_digipayBody), findsOneWidget);

    await tester.tap(find.text('ردشده/ثبت‌نشده'));
    await tester.pumpAndSettle();
    expect(find.text(_digipayBody), findsNothing);
  });

  testWidgets('کپیِ گزارش: متنِ پوشانده‌شده در کلیپ‌بورد', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(app(DiagnosticsScreen(controller: controller)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kDiagCopyKey));
    await tester.pumpAndSettle();

    expect(copied, isNotNull);
    expect(copied, contains('== موجودی'));
    expect(copied, contains('نوع برعکس ثبت شده'));
    expect(copied, contains('رد: شماره حساب/کارت ندارد'));
    expect(copied, isNot(contains('1000000009')));
    expect(find.textContaining('گزارش کپی شد'), findsOneWidget);
  });

  testWidgets('از تنظیمات باز می‌شود و تعداد موارد ناجور را نشان می‌دهد', (tester) async {
    await tester.pumpWidget(app(SettingsScreen(controller: controller)));
    await tester.pumpAndSettle();

    final tile = find.byKey(kSettingsDiagnosticsKey);
    await tester.scrollUntilVisible(tile, 200);
    expect(
        find.descendant(of: tile, matching: find.text('۱')), findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(DiagnosticsScreen), findsOneWidget);
  });

  testWidgets('کارت خلاصه: «چرا این عدد؟» فقط با onExplain', (tester) async {
    var tapped = 0;
    Widget card({VoidCallback? onExplain}) => app(Scaffold(
          body: SummaryCard(
            summary: const FinanceSummary(incomeRial: 0, expenseRial: 0),
            period: const Period.month(1405, 7),
            count: 0,
            openingBalance: 10,
            onExplain: onExplain,
          ),
        ));
    await tester.pumpWidget(card());
    expect(find.byKey(kSummaryExplainKey), findsNothing);

    await tester.pumpWidget(card(onExplain: () => tapped++));
    await tester.tap(find.byKey(kSummaryExplainKey));
    expect(tapped, 1);
  });

  testWidgets('درستش کن (زنجیره): نوعِ برعکس با یک دکمه اصلاح می‌شود', (tester) async {
    await tester.pumpWidget(app(DiagnosticsScreen(controller: controller, initialTab: 1)));
    await tester.pumpAndSettle();
    expect(find.textContaining('نوع برعکس ثبت شده — '), findsOneWidget);

    await tester.tap(find.byKey(const Key('diag-fix-x')));
    await tester.pumpAndSettle();
    expect(controller.cachedById('x')!.kind, 'income');
    // ignore: avoid_print
    expect(find.textContaining('نوع برعکس ثبت شده — '), findsNothing);
    expect(find.text('نوع اصلاح شد'), findsOneWidget);
  });

  testWidgets('درستش کن (موجودی): اعمالِ قانون‌ها، بعد برگرداندن از «پیامک‌ها»', (tester) async {
    await tester.pumpWidget(app(DiagnosticsScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.textContaining('هنوز اجرا نشده'), findsOneWidget);

    await tester.tap(find.byKey(kDiagRepairKey));
    await tester.pumpAndSettle();
    expect(controller.lastRepair!.removed, 1);
    expect(find.textContaining('۱ تراکنشِ بی‌شماره'), findsOneWidget);
    // دیجی‌پی دیگر در جمع نیست: اختلاف فقط همان نوعِ برعکس است.
    expect(controller.balanceBreakdown().diffRial, 4000000);

    await tester.tap(find.text('پیامک‌ها'));
    await tester.pumpAndSettle();
    expect(find.text('حذف شده'), findsOneWidget);
    final id = controller.deletedSms.single.id;
    await tester.tap(find.byKey(Key('diag-sms-fix-$id')));
    await tester.pumpAndSettle();
    expect(controller.cachedById(id), isNotNull);
    expect(find.text('حذف (خلافِ قانون)'), findsOneWidget);
  });

  testWidgets('درستش کن (پیامک‌ها): «این تراکنش است؛ ثبت کن» برای پیامکِ ردشده', (tester) async {
    final refund = RawSms(
        sender: 'DigiPay',
        body: 'بازگشت پول\nمبلغ 31,000 ریال به دیجی‌کارت شما واریز شد.',
        receivedAt: _now.add(const Duration(minutes: 5)));
    inbox = [...inbox, refund];
    await tester.pumpWidget(app(DiagnosticsScreen(controller: controller, initialTab: 2)));
    await tester.pumpAndSettle();
    expect(find.text('رد: شماره حساب/کارت ندارد'), findsOneWidget);

    await tester.tap(find.byKey(
        Key('diag-sms-fix-DigiPay|${refund.receivedAt!.millisecondsSinceEpoch}')));
    await tester.pumpAndSettle();
    expect(
        controller.itemsIn(const Period.all()).where((t) => t.amountRial == 31000), hasLength(1));
  });

  testWidgets('باز و بسته کردنِ جزئیاتِ تراکنش از عیب‌یابی خطا نمی‌دهد', (tester) async {
    await tester.pumpWidget(app(DiagnosticsScreen(controller: controller, initialTab: 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('نوع برعکس ثبت شده — '));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(DiagnosticsScreen))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(DiagnosticsScreen), findsOneWidget);
  });

  testWidgets('«برگرداندنِ همه»: حذف‌شده‌هایی که با قانون می‌خوانند، یک‌جا', (tester) async {
    await store.addAllowedSender('Bank Mellat', bankId: 'mellat');
    final mellat = [
      for (var i = 0; i < 3; i++)
        RawSms(
            sender: 'Bank Mellat',
            body: 'حساب4900000002\nواریز${(i + 1) * 1000}\nمانده${50000 + i * 1000}',
            receivedAt: _now.subtract(Duration(hours: i + 1))),
    ];
    inbox = [...inbox, ...mellat];
    await SmsImporter(store).importAll(mellat);
    await controller.load();
    // مثلِ «بردار و تراکنش‌هایش را حذف کن» در نسخه‌های قبل (بی‌سابقه).
    for (final t in controller.transactionsOfSender('Bank Mellat')) {
      await store.deleteTransaction(t.id);
    }
    await controller.load();

    await tester.pumpWidget(app(DiagnosticsScreen(controller: controller, initialTab: 2)));
    await tester.pumpAndSettle();
    // دیجی‌پیِ بی‌شماره (خلافِ قانون) جزوشان نیست.
    expect(find.textContaining('برگرداندنِ ۳ پیامکِ حذف‌شده'), findsOneWidget);
    await tester.tap(find.byKey(kDiagRestoreAllKey));
    await tester.pumpAndSettle();
    expect(controller.transactionsOfSender('Bank Mellat'), hasLength(3));
    expect(find.byKey(kDiagRestoreAllKey), findsNothing);
  });
}
