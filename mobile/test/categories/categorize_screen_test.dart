import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/categories/categorize_screen.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

void main() {
  const parser = SmsParser();

  late FakeTransactionStore store;
  late DashboardController controller;

  setUp(() async {
    store = FakeTransactionStore();
    controller = DashboardController(store);
    store.seed(
      parser.parse(
          sender: 'BankMellat', body: 'خرید مبلغ 90,000 ریال از کارت 1234'),
      sender: 'BankMellat',
    );
    await controller.load();
  });

  testWidgets('تیک‌زدن چند دسته و ذخیره، تراکنش را دسته‌بندی می‌کند',
      (tester) async {
    final record = controller.transactions.first;
    await tester.pumpWidget(MaterialApp(
      home: CategorizeScreen(controller: controller, record: record),
    ));
    await tester.pumpAndSettle();

    // ابتدا دسته‌بندی‌نشده است
    expect(controller.uncategorizedCount, 1);

    await tester.tap(find.text('سبزیجات'));
    await tester.tap(find.text('میوه'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(kCategorizeSaveKey));
    await tester.pumpAndSettle();

    // بعد از ذخیره، دیگر دسته‌بندی‌نشده نیست
    expect(controller.uncategorizedCount, 0);
    final totals = await store.categoryTotals();
    expect(totals.fold<int>(0, (a, t) => a + t.amountRial), 90000);
  });

  testWidgets('بدون انتخاب دسته، دکمه‌ی ذخیره غیرفعال است', (tester) async {
    final record = controller.transactions.first;
    await tester.pumpWidget(MaterialApp(
      home: CategorizeScreen(controller: controller, record: record),
    ));
    await tester.pumpAndSettle();

    final saveButton =
        tester.widget<FilledButton>(find.byKey(kCategorizeSaveKey));
    expect(saveButton.onPressed, isNull); // غیرفعال
  });
}
