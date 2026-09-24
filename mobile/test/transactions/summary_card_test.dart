import 'package:economy/core/format/money_format.dart';
import 'package:economy/features/transactions/data/period.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/transactions/widgets/summary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
      locale: const Locale('fa'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('موجودی نهایی = موجودی اول دوره + درآمد − هزینه', (tester) async {
    // اول‌دوره ۵م، درآمد ۳م، هزینه ۱م → نهایی باید ۷م باشد (هم‌خوان).
    await tester.pumpWidget(_wrap(const SummaryCard(
      summary: FinanceSummary(incomeRial: 3000000, expenseRial: 1000000),
      period: Period.month(1405, 6),
      count: 5,
      openingBalance: 5000000,
    )));

    expect(find.text(formatToman(7000000)), findsOneWidget); // موجودی نهایی
    expect(find.byKey(kOpeningValueKey), findsOneWidget);
    expect(find.textContaining('موجودی نهایی'), findsOneWidget);
    expect(find.text(formatToman(3000000)), findsOneWidget); // درآمد
    expect(find.text(formatToman(1000000)), findsOneWidget); // هزینه
  });

  testWidgets('بدون مانده: فقط خالص (بدون خطِ اول‌دوره)', (tester) async {
    await tester.pumpWidget(_wrap(const SummaryCard(
      summary: FinanceSummary(incomeRial: 3000000, expenseRial: 1000000),
      period: Period.month(1405, 6),
      count: 5,
      openingBalance: null,
    )));
    expect(find.byKey(kOpeningValueKey), findsNothing);
    expect(find.text(formatToman(2000000)), findsOneWidget); // خالص = ۳م − ۱م
    expect(find.textContaining('خالص'), findsOneWidget);
  });

  testWidgets('با مانده‌ی بانک: عددِ اصلی طبقِ بانک است و مغایرت برچسب دارد', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_wrap(SummaryCard(
      summary: const FinanceSummary(incomeRial: 3000000, expenseRial: 1000000),
      period: const Period.month(1405, 6),
      count: 5,
      openingBalance: 5000000,
      bankBalance: 6500000, // بانک ۶٫۵م می‌گوید، تراکنش‌ها ۷م
      discrepancy: -500000,
      onExplain: () => tapped++,
    )));
    expect(find.text(formatToman(6500000)), findsOneWidget);
    expect(find.text(formatToman(7000000)), findsNothing);
    expect(find.textContaining('طبق مانده‌ی بانک'), findsOneWidget);
    expect(find.textContaining('مغایرت با تراکنش‌ها: ${formatToman(-500000)}'), findsOneWidget);

    await tester.tap(find.byKey(kSummaryDiscrepancyKey));
    expect(tapped, 1);
  });

  testWidgets('مغایرتِ صفر برچسب ندارد', (tester) async {
    await tester.pumpWidget(_wrap(const SummaryCard(
      summary: FinanceSummary(incomeRial: 0, expenseRial: 0),
      period: Period.month(1405, 6),
      count: 0,
      openingBalance: 5000000,
      bankBalance: 5000000,
      discrepancy: 0,
    )));
    expect(find.byKey(kSummaryDiscrepancyKey), findsNothing);
  });
}
