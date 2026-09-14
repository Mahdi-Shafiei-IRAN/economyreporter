import 'package:economy/core/dashboard/dashboard_summary.dart';
import 'package:economy/core/dashboard/remote_dashboard_api.dart';
import 'package:economy/core/format/money_format.dart';
import 'package:economy/features/family/family_dashboard_screen.dart';
import 'package:economy/features/transactions/data/period.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDashboardApi implements RemoteDashboardApi {
  final DashboardSummary? summary;
  final bool throwError;
  DateTime? lastFrom;
  DateTime? lastTo;
  _FakeDashboardApi({this.summary, this.throwError = false});

  @override
  Future<DashboardSummary> fetchSummary({DateTime? from, DateTime? to}) async {
    lastFrom = from;
    lastTo = to;
    if (throwError) throw Exception('server error');
    return summary!;
  }
}

void main() {
  final now = DateTime.utc(2026, 9, 14, 9); // شهریور ۱۴۰۵
  Widget app(RemoteDashboardApi api, {Period? period}) => MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: FamilyDashboardScreen(
          api: api,
          initialPeriod: period ?? Period.containing(now),
          now: now,
        ),
      );

  testWidgets('خلاصه‌ی سرور نمایش داده می‌شود', (tester) async {
    final api = _FakeDashboardApi(
      summary: const DashboardSummary(
        incomeRial: 10000000,
        expenseRial: 3000000,
        balanceRial: 7000000,
        members: [MemberExpense(id: 'u1', name: 'علی', expensesRial: 3000000)],
        categories: [CategoryExpense(name: 'خوراک', amountRial: 3000000)],
        cards: [CardExpense(cardLast4: '1234', amountRial: 3000000)],
      ),
    );

    await tester.pumpWidget(app(api));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(kFamilyIncomeKey)).data,
        formatToman(10000000));
    expect(tester.widget<Text>(find.byKey(kFamilyExpenseKey)).data,
        formatToman(3000000));
    expect(tester.widget<Text>(find.byKey(kFamilyBalanceKey)).data,
        formatToman(7000000));
    expect(find.text('علی'), findsOneWidget);
    expect(find.text('خوراک'), findsOneWidget);
    expect(find.text('کارت 1234'), findsOneWidget);
  });

  testWidgets('بازه‌ی انتخاب‌شده به سرور فرستاده می‌شود (نه کلِ زمان‌ها)', (tester) async {
    final api = _FakeDashboardApi(
      summary: const DashboardSummary(
        incomeRial: 0, expenseRial: 0, balanceRial: 0,
        members: [], categories: [], cards: [],
      ),
    );
    await tester.pumpWidget(app(api, period: const Period.month(1405, 6)));
    await tester.pumpAndSettle();
    expect(api.lastFrom, isNotNull);
    expect(api.lastTo, isNotNull);
    // مرداد (ماه قبل) نباید در بازه باشد
    expect(api.lastFrom!.isBefore(api.lastTo!), isTrue);
  });

  testWidgets('خطای سرور پیام خطا نشان می‌دهد', (tester) async {
    await tester.pumpWidget(app(_FakeDashboardApi(throwError: true)));
    await tester.pumpAndSettle();
    expect(find.byKey(kFamilyErrorKey), findsOneWidget);
  });
}
