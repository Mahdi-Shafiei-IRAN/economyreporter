import 'package:economy/core/sms/models.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/review/reconciliation_screen.dart';
import 'package:economy/features/review/review_screen.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/transaction_details_sheet.dart';
import 'package:economy/features/transactions/widgets/tx_widgets.dart';
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
    // یک تراکنش احتمالاً ناموفق (بازبینی) و یک عادی
    store.seed(parser.parse(sender: 'Digikala', body: 'خرید ناموفق مبلغ 100,000 ریال'),
        sender: 'Digikala');
    store.seed(parser.parse(sender: 'ملی', body: 'واریز مبلغ 5,000,000 ریال'),
        sender: 'ملی');
    await controller.load();
  });

  Widget app(Widget home) => MaterialApp(
        theme: buildAppTheme(Brightness.light),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: home,
      );

  // صفحه‌ی بلند تا همه‌ی کارت‌ها بدون اسکرول قابل ضربه باشند.
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1170, 4200);
    view.devicePixelRatio = 3;
  });
  tearDown(() =>
      TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!.reset());

  testWidgets('فقط موارد نیازمند بازبینی، با توضیح و دلیل و متن پیامک', (tester) async {
    await tester.pumpWidget(app(ReviewScreen(controller: controller)));
    await tester.pumpAndSettle();

    expect(controller.reviewItems, hasLength(1));
    expect(find.byKey(kReviewExplainKey), findsOneWidget);
    expect(find.text(reviewReasonLabel(ReviewReason.failed)), findsOneWidget);
    expect(find.text('خرید ناموفق مبلغ 100,000 ریال'), findsOneWidget);
    expect(find.byKey(kReviewEmptyKey), findsNothing);
  });

  testWidgets('«درسته، ثبت کن» آن را از صف خارج و وارد جمع می‌کند', (tester) async {
    await tester.pumpWidget(app(ReviewScreen(controller: controller)));
    await tester.pumpAndSettle();
    expect(controller.summary.expenseRial, 0);

    final id = controller.reviewItems.first.id;
    await tester.tap(find.byKey(Key('review-confirm-$id')));
    await tester.pumpAndSettle();

    expect(controller.needsReviewCount, 0);
    expect(find.byKey(kReviewEmptyKey), findsOneWidget);
    expect(controller.summary.expenseRial, 100000);
  });

  testWidgets('«نامعتبر است» پس از تأیید حذفش می‌کند', (tester) async {
    await tester.pumpWidget(app(ReviewScreen(controller: controller)));
    await tester.pumpAndSettle();

    final id = controller.reviewItems.first.id;
    await tester.tap(find.byKey(Key('review-delete-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kConfirmInvalidKey));
    await tester.pumpAndSettle();

    expect(controller.reviewItems, isEmpty);
    expect(find.byKey(kReviewEmptyKey), findsOneWidget);
    expect(await store.getAll(), hasLength(1)); // فقط واریز ماند
  });

  testWidgets('مبلغِ نامشخص: بدون مبلغ تأیید نمی‌شود، با مبلغ ثبت می‌شود', (tester) async {
    store.seed(parser.parse(sender: 'BankMellat', body: 'برداشت از کارت 1234 انجام شد'),
        sender: 'BankMellat');
    await controller.load();
    await tester.pumpWidget(app(ReviewScreen(controller: controller)));
    await tester.pumpAndSettle();

    final r = controller.reviewItems.firstWhere((t) => t.amountRial == null);
    await tester.tap(find.byKey(Key('review-confirm-${r.id}')));
    await tester.pumpAndSettle();
    expect(find.text('مبلغ را به تومان وارد کن'), findsOneWidget);

    await tester.enterText(find.byKey(Key('review-amount-${r.id}')), '25000');
    await tester.tap(find.byKey(Key('review-confirm-${r.id}')));
    await tester.pumpAndSettle();

    final saved = await store.getById(r.id);
    expect(saved!.amountRial, 250000);
    expect(saved.needsReview, isFalse);
  });

  group('ناهماهنگی مانده', () {
    setUp(() async {
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
      store.addRecord(rec('b', 'expense', 200000, 500000, 2));
      await controller.load();
    });

    testWidgets('ثبت دستیِ مبلغِ جاافتاده، شکاف را برطرف می‌کند', (tester) async {
      expect(controller.balanceGaps, hasLength(1));
      await tester.pumpWidget(app(ReconciliationScreen(controller: controller)));
      await tester.pumpAndSettle();
      expect(find.textContaining('احتمالاً برداشتی ثبت نشده'), findsOneWidget);

      await tester.tap(find.byKey(const Key('gap-add-a|b')));
      await tester.pumpAndSettle();

      expect(controller.balanceGaps, isEmpty);
      expect(find.byKey(kReconcileEmptyKey), findsOneWidget);
      final manual = (await store.getAll()).where((t) => t.source == 'manual').single;
      expect(manual.amountRial, 300000);
      expect(manual.kind, 'expense');
    });

    testWidgets('«نادیده بگیر» شکاف را پنهان می‌کند', (tester) async {
      await tester.pumpWidget(app(ReconciliationScreen(controller: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('gap-dismiss-a|b')));
      await tester.pumpAndSettle();
      expect(controller.balanceGaps, isEmpty);

      await controller.load(); // بعد از بارگذاری دوباره هم برنمی‌گردد
      expect(controller.balanceGaps, isEmpty);
    });
  });
}
