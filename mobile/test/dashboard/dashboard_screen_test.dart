import 'package:economy/core/format/money_format.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/categories/categorize_screen.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/dashboard/dashboard_screen.dart';
import 'package:economy/features/reports/report_screen.dart';
import 'package:economy/features/review/review_screen.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/transactions/data/tx_query.dart';
import 'package:economy/features/transactions/edit_transaction_sheet.dart';
import 'package:economy/features/transactions/transaction_details_sheet.dart';
import 'package:economy/features/transactions/widgets/period_bar.dart';
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

  setUp(() {
    store = FakeTransactionStore(clock: () => now);
    controller = DashboardController(store, clock: () => now);
  });

  void seed(String sender, String body, DateTime at) => store.seed(
        parser.parse(sender: sender, body: body),
        sender: sender,
        receivedAt: at,
      );

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

  List<int?> tileAmounts(WidgetTester tester) => tester
      .widgetList<TransactionTile>(find.byType(TransactionTile))
      .map((t) => t.record.amountRial)
      .toList();

  Future<void> drainSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  Future<void> addViaFab(WidgetTester tester, String sender, String body) async {
    await tester.tap(find.byKey(kAddSmsFabKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kSmsSenderFieldKey), sender);
    await tester.enterText(find.byKey(kSmsBodyFieldKey), body);
    await tester.tap(find.byKey(kSmsSaveButtonKey));
    await tester.pumpAndSettle();
  }

  testWidgets('حالت خالی: جمع صفر و تاریخ دقیقِ «از … تا …» معلوم است', (tester) async {
    await pumpApp(tester);

    expect(find.byKey(kEmptyStateKey), findsOneWidget);
    expect(textOf(tester, kIncomeValueKey), formatToman(0));
    expect(textOf(tester, kExpenseValueKey), formatToman(0));
    expect(textOf(tester, kBalanceValueKey), formatToman(0));
    expect(textOf(tester, kRangeLabelKey), 'از ۱ شهریور ۱۴۰۵ تا ۳۱ شهریور ۱۴۰۵');
  });

  testWidgets('نمای پله‌ای: شخص ← کارت ← تراکنش، و جمع درست', (tester) async {
    await store.addWallet(const Wallet(
        id: '', ownerName: 'بابا', label: 'کارت حقوق', cardLast4: '1234'));
    seed('ملی', 'واریز مبلغ 10,000,000 ریال به کارت 1234', DateTime.utc(2026, 9, 10, 8));
    seed('BankMellat', 'خرید مبلغ 3,000,000 ریال از کارت 1234', DateTime.utc(2026, 9, 10, 9));
    seed('BankMellat', 'خرید مبلغ 500,000 ریال از کارت 9999', DateTime.utc(2026, 9, 10, 10));

    await pumpApp(tester);

    expect(textOf(tester, kIncomeValueKey), formatToman(10000000));
    expect(textOf(tester, kExpenseValueKey), formatToman(3500000));
    expect(textOf(tester, kBalanceValueKey), formatToman(6500000));

    expect(find.byKey(const ValueKey('person-بابا')), findsOneWidget);
    expect(find.byKey(const ValueKey('person-$kUnknownPerson')), findsOneWidget);
    expect(find.text('کارت حقوق'), findsOneWidget);
    expect(find.text('کارت‌های بی‌صاحب'), findsOneWidget);
    expect(find.text('تعیین صاحب'), findsOneWidget);
    expect(find.byType(TransactionTile), findsNWidgets(3));
  });

  testWidgets('نمای «همه»: پیش‌فرض بر اساس تاریخ با سرتیتر روز، و ترتیب بر اساس مبلغ',
      (tester) async {
    seed('BankMellat', 'خرید مبلغ 200,000 ریال از کارت 1234', DateTime.utc(2026, 9, 10, 9));
    seed('BankMellat', 'خرید مبلغ 900,000 ریال از کارت 1234', DateTime.utc(2026, 9, 8, 9));
    seed('BankMellat', 'خرید مبلغ 50,000 ریال از کارت 1234', DateTime.utc(2026, 9, 11, 7));

    await pumpApp(tester);
    await tester.tap(find.text('همه با هم'));
    await tester.pumpAndSettle();

    expect(tileAmounts(tester), [50000, 200000, 900000]); // جدیدترین اول
    expect(find.text('پنجشنبه ۱۹ شهریور ۱۴۰۵'), findsOneWidget);

    await tester.tap(find.byKey(kSortButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بیشترین مبلغ'));
    await tester.pumpAndSettle();
    expect(tileAmounts(tester), [900000, 200000, 50000]);

    await tester.tap(find.byKey(kSortButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('قدیمی‌ترین'));
    await tester.pumpAndSettle();
    expect(tileAmounts(tester), [900000, 200000, 50000]);
  });

  testWidgets('ماه قبل: بازه و تراکنش‌ها عوض می‌شوند', (tester) async {
    seed('BankMellat', 'خرید مبلغ 70,000 ریال از کارت 1234', DateTime.utc(2026, 8, 15)); // مرداد
    seed('BankMellat', 'خرید مبلغ 30,000 ریال از کارت 1234', DateTime.utc(2026, 9, 10));

    await pumpApp(tester);
    expect(tileAmounts(tester), [30000]);

    await tester.tap(find.byKey(kPeriodPrevKey));
    await tester.pumpAndSettle();
    expect(textOf(tester, kRangeLabelKey), 'از ۱ مرداد ۱۴۰۵ تا ۳۱ مرداد ۱۴۰۵');
    expect(tileAmounts(tester), [70000]);
  });

  testWidgets('فیلتر نوع: فقط درآمد', (tester) async {
    seed('ملی', 'واریز مبلغ 1,000,000 ریال', DateTime.utc(2026, 9, 10, 8));
    seed('BankMellat', 'خرید مبلغ 400,000 ریال از کارت 1234', DateTime.utc(2026, 9, 10, 9));

    await pumpApp(tester);
    await tester.tap(find.byKey(kFilterButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فقط درآمد'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نمایش'));
    await tester.pumpAndSettle();

    expect(tileAmounts(tester), [1000000]);
    expect(textOf(tester, kExpenseValueKey), formatToman(0));
    expect(find.textContaining('فیلترشده'), findsOneWidget);
  });

  testWidgets('افزودن پیامک از طریق FAB جمع را به‌روز می‌کند', (tester) async {
    await pumpApp(tester);
    await addViaFab(tester, 'BankMellat', 'برداشت مبلغ 2,000,000 ریال از کارت 1234');

    expect(textOf(tester, kExpenseValueKey), formatToman(2000000));
    expect(find.byType(TransactionTile), findsOneWidget);
    expect(find.text('تراکنش ثبت شد.'), findsOneWidget);
    await drainSnackBar(tester);
  });

  testWidgets('افزودن پیامک تکراری رکورد دوم نمی‌سازد', (tester) async {
    await pumpApp(tester);
    const body = 'برداشت مبلغ 900,000 ریال از کارت 1234';
    await addViaFab(tester, 'BankMellat', body);
    await addViaFab(tester, 'BankMellat', body);

    expect(find.byType(TransactionTile), findsOneWidget);
    expect(find.text('این پیامک قبلاً ثبت شده بود.'), findsOneWidget);
    await drainSnackBar(tester);
  });

  testWidgets('تراکنش ناموفق: در جمع نمی‌آید و تراشه‌ی بازبینی صفحه‌اش را باز می‌کند',
      (tester) async {
    seed('BankMellat', 'خرید ناموفق مبلغ 100,000 ریال از کارت 1234', DateTime.utc(2026, 9, 10));

    await pumpApp(tester);
    expect(textOf(tester, kExpenseValueKey), formatToman(0));
    expect(find.text('${toPersianDigits('1')} نیازمند بازبینی'), findsOneWidget);

    await tester.tap(find.byKey(kReviewChipKey));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewScreen), findsOneWidget);
    expect(find.byKey(kReviewExplainKey), findsOneWidget);
  });

  testWidgets('ویرایش از برگه‌ی جزئیات، جمع را به‌روز می‌کند', (tester) async {
    seed('BankMellat', 'خرید مبلغ 3,000,000 ریال از کارت 1234', DateTime.utc(2026, 9, 10));

    await pumpApp(tester);
    await tester.tap(find.byType(TransactionTile));
    await tester.pumpAndSettle();
    expect(find.byKey(kDetailsSheetKey), findsOneWidget);

    await tester.tap(find.byKey(kDetailsEditKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kEditAmountKey), '500000');
    await tester.tap(find.byKey(kEditSaveKey));
    await tester.pumpAndSettle();

    expect(textOf(tester, kExpenseValueKey), formatToman(5000000));
  });

  group('فقط صاحب کارت ویرایش می‌کند', () {
    setUp(() {
      store.settings[SettingKeys.meUserId] = 'u-me';
      store.addRecord(TransactionRecord(
        id: 'r1',
        kind: 'expense',
        amountRial: 100000,
        ownerUserId: 'u-father',
        ownerName: 'بابا',
        origin: 'remote',
        transactionDate: DateTime.utc(2026, 9, 10),
        createdAt: DateTime.utc(2026, 9, 10),
        updatedAt: DateTime.utc(2026, 9, 10),
      ));
    });

    testWidgets('برگه‌ی جزئیات فقط دیدنی است', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byType(TransactionTile));
      await tester.pumpAndSettle();

      expect(find.byKey(kDetailsReadOnlyKey), findsOneWidget);
      expect(find.byKey(kDetailsEditKey), findsNothing);
      expect(find.byKey(kDetailsDeleteKey), findsNothing);
      expect(find.textContaining('فقط بابا'), findsOneWidget);
    });

    testWidgets('انتخاب نمی‌شود و پیام توضیحی می‌آید', (tester) async {
      await pumpApp(tester);
      await tester.longPress(find.byType(TransactionTile));
      await tester.pumpAndSettle();

      expect(controller.selectionMode, isFalse);
      expect(find.textContaining('فقط بابا'), findsOneWidget);
      await drainSnackBar(tester);
    });
  });

  testWidgets('انتخاب چندتایی و «نامعتبر» گروهی', (tester) async {
    seed('BankMellat', 'خرید مبلغ 10,000 ریال از کارت 1234', DateTime.utc(2026, 9, 10, 8));
    seed('BankMellat', 'خرید مبلغ 20,000 ریال از کارت 1234', DateTime.utc(2026, 9, 10, 9));

    await pumpApp(tester);
    await tester.longPress(find.byType(TransactionTile).first);
    await tester.pumpAndSettle();
    expect(find.byKey(kSelectionBarKey), findsOneWidget);
    expect(textOf(tester, kSelectionCountKey), '۱ مورد انتخاب شد');

    await tester.tap(find.byType(TransactionTile).last);
    await tester.pumpAndSettle();
    expect(textOf(tester, kSelectionCountKey), '۲ مورد انتخاب شد');

    await tester.tap(find.byKey(kSelectionDeleteKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kConfirmInvalidKey));
    await tester.pumpAndSettle();

    expect(find.byType(TransactionTile), findsNothing);
    expect(textOf(tester, kExpenseValueKey), formatToman(0));
    await drainSnackBar(tester);
  });

  testWidgets('دسته‌بندی گروهی از انتخاب چندتایی', (tester) async {
    seed('BankMellat', 'خرید مبلغ 10,000 ریال از کارت 1234', DateTime.utc(2026, 9, 10, 8));
    seed('BankMellat', 'خرید مبلغ 20,000 ریال از کارت 1234', DateTime.utc(2026, 9, 10, 9));

    await pumpApp(tester);
    await tester.longPress(find.byType(TransactionTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TransactionTile).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kSelectionCategorizeKey));
    await tester.pumpAndSettle();

    expect(find.byType(CategorizeScreen), findsOneWidget);
    await tester.tap(find.text('میوه'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kCategorizeSaveKey));
    await tester.pumpAndSettle();

    final all = await store.getAll();
    expect(all.every((t) => t.isCategorized), isTrue);
    expect(controller.selectionMode, isFalse);
    expect(find.text('میوه'), findsNWidgets(2)); // برچسب دسته روی هر دو ردیف
  });

  testWidgets('تراشه‌ی ناهماهنگی مانده هنگام وجود شکاف', (tester) async {
    TransactionRecord rec(String id, String kind, int amount, int balance, int minute) {
      final at = DateTime.utc(2026, 9, 10, 12, minute);
      return TransactionRecord(
        id: id,
        cardLast4: '1234',
        kind: kind,
        amountRial: amount,
        balanceAfterRial: balance,
        transactionDate: at,
        createdAt: at,
        updatedAt: at,
      );
    }

    store.addRecord(rec('a', 'income', 0, 1000000, 0));
    store.addRecord(rec('b', 'expense', 200000, 500000, 1)); // انتظار 800000

    await pumpApp(tester);
    expect(find.byKey(kReconcileChipKey), findsOneWidget);
  });

  testWidgets('زبانه‌های گزارش و تنظیمات', (tester) async {
    seed('BankMellat', 'خرید مبلغ 30,000 ریال از کارت 1234', DateTime.utc(2026, 9, 10));
    await pumpApp(tester);

    await tester.tap(find.byKey(kNavReportKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kReportBarsKey), findsOneWidget);
    expect(find.byKey(kReportPeopleKey), findsOneWidget);

    await tester.tap(find.byKey(kNavSettingsKey));
    await tester.pumpAndSettle();
    expect(find.text('تنظیمات و ابزارها'), findsOneWidget);
  });
}
