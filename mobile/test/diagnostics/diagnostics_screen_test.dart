import 'package:economy/core/format/money_format.dart';
import 'package:economy/core/sms/sms_importer.dart';
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
    await SmsImporter(store).importAll(inbox);

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

  testWidgets('زبانه‌ی موجودی: اختلافِ کارتِ خلاصه با بانک', (tester) async {
    await tester.pumpWidget(app(DiagnosticsScreen(controller: controller)));
    await tester.pumpAndSettle();

    final diff = tester.widget<Text>(find.byKey(kDiagBalanceDiffKey));
    expect(diff.data, formatToman(4000000));
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
    expect(find.text('قانون جدید: رد — شماره حساب/کارت ندارد'), findsOneWidget);
    expect(find.textContaining('با قانونِ پیشنهادی ۱ پیامک'), findsOneWidget);

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
}
