import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/review/review_screen.dart';
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
    // یک تراکنش نیازمند بازبینی (فرستنده‌ی ناشناخته) و یک عادی
    store.seed(parser.parse(sender: 'Digikala', body: 'خرید ناموفق مبلغ 100,000 ریال'),
        sender: 'Digikala');
    store.seed(parser.parse(sender: 'ملی', body: 'واریز مبلغ 5,000,000 ریال'),
        sender: 'ملی');
    await controller.load();
  });

  Widget app() => MaterialApp(home: ReviewScreen(controller: controller));

  testWidgets('فقط موارد نیازمند بازبینی نشان داده می‌شوند', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(controller.reviewItems, hasLength(1));
    expect(find.byKey(kReviewEmptyKey), findsNothing);
    expect(find.byType(Card), findsOneWidget);
  });

  testWidgets('تأیید یک مورد آن را از صف خارج می‌کند', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final id = controller.reviewItems.first.id;
    await tester.tap(find.byKey(Key('review-confirm-$id')));
    await tester.pumpAndSettle();

    expect(controller.needsReviewCount, 0);
    expect(find.byKey(kReviewEmptyKey), findsOneWidget);
  });

  testWidgets('حذف یک مورد آن را پاک می‌کند', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final id = controller.reviewItems.first.id;
    await tester.tap(find.byKey(Key('review-delete-$id')));
    await tester.pumpAndSettle();

    expect(controller.reviewItems, isEmpty);
    expect(find.byKey(kReviewEmptyKey), findsOneWidget);
  });
}
