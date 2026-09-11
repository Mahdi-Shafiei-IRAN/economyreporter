import 'dart:io';

import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/reports/pdf_report.dart';
import 'package:economy/features/reports/report_data.dart';
import 'package:economy/features/reports/report_screen.dart';
import 'package:economy/features/transactions/data/period.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import '../helpers/fake_transaction_store.dart';

TransactionRecord _t(
  String id, {
  required String kind,
  required int amount,
  required DateTime at,
  String? owner,
  String? wallet,
  List<Allocation> allocations = const [],
  bool review = false,
}) =>
    TransactionRecord(
      id: id,
      kind: kind,
      amountRial: amount,
      ownerName: owner,
      walletLabel: wallet,
      cardLast4: '1234',
      bankId: 'mellat',
      allocations: allocations,
      needsReview: review,
      transactionDate: at,
      createdAt: at,
      updatedAt: at,
    );

void main() {
  final items = [
    _t('1', kind: 'expense', amount: 300000, at: DateTime.utc(2026, 9, 10, 9), owner: 'بابا',
        wallet: 'کارت حقوق', allocations: const [Allocation('میوه', 200000), Allocation('نان', 100000)]),
    _t('2', kind: 'expense', amount: 100000, at: DateTime.utc(2026, 9, 10, 12), owner: 'مامان',
        wallet: 'کارت خانه'),
    _t('3', kind: 'income', amount: 5000000, at: DateTime.utc(2026, 8, 23, 6), owner: 'بابا',
        wallet: 'کارت حقوق'),
    _t('4', kind: 'expense', amount: 999, at: DateTime.utc(2026, 9, 10), review: true),
  ];

  group('داده‌ی گزارش', () {
    test('ستون‌های روزانه‌ی ماه (منتظر بازبینی حساب نمی‌شود)', () {
      final buckets = buildBuckets(const Period.month(1405, 6), items);
      expect(buckets, hasLength(31));
      expect(buckets[18].expenseRial, 400000); // ۱۹ شهریور
      expect(buckets[0].incomeRial, 5000000); // ۱ شهریور
      expect(buckets[18].fullLabel, '۱۹ شهریور');
    });

    test('ستون‌های ماهانه برای «همه‌ی زمان‌ها»', () {
      final buckets = buildBuckets(const Period.all(), items);
      expect(buckets, hasLength(12));
      expect(buckets.last.fullLabel, 'شهریور ۱۴۰۵');
      expect(buckets.last.expenseRial, 400000);
    });

    test('تفکیک افراد و دسته‌ها', () {
      final people = breakdown(items, (t) => t.ownerName ?? '?');
      expect(people.map((e) => e.label), ['بابا', 'مامان']);
      expect(people.first.expenseRial, 300000);
      expect(people.first.incomeRial, 5000000);

      final cats = categoryBreakdown(items);
      expect(cats.map((e) => e.label), ['میوه', 'نان']);
    });
  });

  test('PDF با فونت فارسی ساخته می‌شود', () async {
    final bytes = File('assets/fonts/Vazirmatn-Regular.ttf').readAsBytesSync();
    final font = pw.Font.ttf(bytes.buffer.asByteData());
    final data = ReportData.from(
      period: const Period.month(1405, 6),
      items: items,
      now: DateTime.utc(2026, 9, 11, 9),
    );
    expect(data.fileName, 'family-report-1405-06.pdf');

    final pdf = await PdfReport.build(data, font: font);
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    expect(pdf.length, greaterThan(5000));

    // برای بررسی چشمی: PDF_OUT=<مسیر> flutter test test/reports
    final out = Platform.environment['PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(pdf);
  });

  group('صفحه‌ی گزارش', () {
    const parser = SmsParser();
    final now = DateTime.utc(2026, 9, 11, 9);
    late FakeTransactionStore store;
    late DashboardController controller;

    setUp(() {
      store = FakeTransactionStore(clock: () => now);
      controller = DashboardController(store, clock: () => now);
    });

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 4200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await controller.load();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(Brightness.light),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: ReportScreen(controller: controller),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('بازه‌ی خالی راهنما دارد', (tester) async {
      await pump(tester);
      expect(find.byKey(kReportEmptyKey), findsOneWidget);
    });

    testWidgets('نمودارها نمایش داده می‌شوند و دسته‌ها پس از دسته‌بندی', (tester) async {
      store.seed(
        parser.parse(sender: 'BankMellat', body: 'خرید مبلغ 90,000 ریال از کارت 1234'),
        sender: 'BankMellat',
        receivedAt: DateTime.utc(2026, 9, 10),
      );
      await pump(tester);

      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byKey(kReportPeopleKey), findsOneWidget);
      expect(find.byKey(kReportCardsKey), findsOneWidget);
      expect(find.textContaining('هنوز هزینه‌ای در این بازه دسته‌بندی نشده'), findsOneWidget);

      final id = (await store.getAll()).single.id;
      await controller.categorize(id, ['c2']);
      await tester.pumpAndSettle();
      expect(find.byType(PieChart), findsOneWidget);
    });
  });
}
