/// فاز ۳: جزئیاتِ حساب و پنجره‌های اختلاف (سناریوهای ۳ تا ۶)، دسته‌ها، گزارشِ ماه و بودجه.
library;

import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/format/money_format.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/ledger/account_details_screen.dart';
import 'package:economy/features/ledger/account_form.dart';
import 'package:economy/features/ledger/entry_sheet.dart';
import 'package:economy/features/ledger/ledger_home_screen.dart';
import 'package:economy/features/ledger/ledger_controller.dart';
import 'package:economy/features/ledger/month_report_screen.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

void main() {
  const allowed = [AllowedSender(id: 's1', address: 'Bank Mellat', bankId: 'mellat')];
  final now = DateTime.utc(2026, 9, 24, 10);
  var clock = now;
  final t1 = DateTime.utc(2026, 9, 23, 7), t2 = DateTime.utc(2026, 9, 23, 8), t3 = DateTime.utc(2026, 9, 23, 9);

  IncomingSms mellat(String line, String balance, DateTime at) => IncomingSms(
      sender: 'Bank Mellat', body: 'حساب1000005596\n$line\nمانده$balance', receivedAt: at);

  setUpAll(initSqfliteFfiForTests);

  Future<LedgerController> setup(WidgetTester tester, List<IncomingSms> inbox) async {
    clock = now;
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    late LedgerController c;
    late Database db;
    await tester.runAsync(() async {
      db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
      await db.insert('wallets', {
        'id': 'm1',
        'owner_name': 'مهدی',
        'label': 'ملت',
        'bank_id': 'mellat',
        'account_ref': '1000005596',
        'created_at': now.toIso8601String(),
      });
      c = LedgerController(LedgerRepository(db, deviceId: 'dev', clock: () => clock),
          allowedSenders: () async => allowed, readInbox: () async => inbox, clock: () => clock);
      await c.setEnabled(true);
    });
    addTearDown(() => tester.runAsync(db.close));
    return c;
  }

  Widget app(Widget home) => MaterialApp(
        theme: buildAppTheme(Brightness.light),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: home,
      );

  Future<void> act(WidgetTester tester, LedgerController c, Future<void> Function() gesture) async {
    await tester.runAsync(() async {
      await gesture();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await c.settle();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  /// کارِ دیتابیس بیرون از ساعتِ جعلی (برای آماده کردنِ داده پیش از نمایش).
  Future<void> run(WidgetTester tester, Future<void> Function() body) async {
    await tester.runAsync(body);
    await tester.pumpAndSettle();
  }

  List<SmsItem> oldestFirst(LedgerController c) =>
      [...c.pending]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

  Widget details(LedgerController c, [String id = 'm1']) =>
      app(AccountDetailsScreen(controller: c, accountId: id));

  testWidgets('scenario 3: a rejected real SMS shows as a window; "record it" closes it', (tester) async {
    final c = await setup(tester, [
      mellat('برداشت100,000', '900,000', t1),
      mellat('برداشت200,000', '700,000', t2),
      mellat('برداشت50,000', '650,000', t3),
    ]);
    final items = oldestFirst(c);
    await run(tester, () async {
      await c.acceptSuggested(items[0]);
      await c.acceptSuggested(items[2]);
      await c.reject(items[1], RejectReason.notTx);
    });
    await tester.pumpWidget(details(c));
    expect(find.byKey(windowCardKey(0)), findsOneWidget);
    expect(find.text('۲۰٬۰۰۰ تومان برداشتِ ثبت‌نشده'), findsOneWidget);
    expect(find.textContaining('ردش کرده بودی'), findsOneWidget);

    await act(tester, c, () => tester.tap(find.byKey(windowAcceptSmsKey(items[1].key))));
    expect(find.byKey(windowCardKey(0)), findsNothing);
    expect(find.text('همه‌ی تراکنش‌ها با مانده‌های بانک می‌خوانند.'), findsOneWidget);
    expect(c.accounts.single.balance!.balanceRial, 650000);
  });

  testWidgets('scenario 4: a manual entry with the wrong kind is caught and flipped', (tester) async {
    final c = await setup(tester, [
      mellat('برداشت100,000', '900,000', t1),
      mellat('برداشت50,000', '750,000', t3),
    ]);
    await run(tester, () async {
      await c.acceptMany(c.readyToAccept);
      await c.addManual(accountId: 'm1', kind: EntryKind.income, amountRial: 100000, occurredAt: t2);
    });
    await tester.pumpWidget(details(c));
    final wrong = (await tester.runAsync(c.repo.entries))!.firstWhere((e) => e.source == EntrySource.manual);
    expect(find.byKey(windowFlipKey(wrong.id)), findsOneWidget);

    await act(tester, c, () => tester.tap(find.byKey(windowFlipKey(wrong.id))));
    expect(find.byKey(windowCardKey(0)), findsNothing);
    expect(c.accounts.single.balance!.balanceRial, 750000);
  });

  testWidgets('scenario 5: cash account — reconcile shows the gap, a noted adjustment closes it',
      (tester) async {
    final c = await setup(tester, const []);
    late String cashId;
    await run(tester, () async {
      cashId = (await c.createAccount(ownerName: 'مهدی', label: 'نقد', balanceRial: 10000000)).id;
      await c.addManual(
          accountId: cashId,
          kind: EntryKind.expense,
          amountRial: 1000000,
          occurredAt: now.add(const Duration(minutes: 1)));
    });
    await tester.pumpWidget(details(c, cashId));
    expect(find.text('۹۰۰٬۰۰۰ تومان'), findsOneWidget);
    clock = now.add(const Duration(minutes: 5)); // تطبیق بعد از خرج

    await tester.tap(find.byKey(kDetailsReconcileKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kBalanceFieldKey), '850000');
    await act(tester, c, () => tester.tap(find.byKey(kBalanceSaveKey)));
    expect(find.text('۵۰٬۰۰۰ تومان برداشتِ ثبت‌نشده'), findsOneWidget);

    await tester.tap(find.byKey(windowAdjustKey(0)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kAdjustSaveKey)); // بی‌یادداشت: قبول نمی‌شود
    await tester.pumpAndSettle();
    expect(find.text('بنویس بابتِ چیست'), findsOneWidget);
    await tester.enterText(find.byKey(kAdjustNoteKey), 'خرجِ جاافتاده');
    await act(tester, c, () => tester.tap(find.byKey(kAdjustSaveKey)));

    expect(find.byKey(windowCardKey(0)), findsNothing);
    expect(c.view(cashId)!.balance!.balanceRial, 8500000);
    final adj = (await tester.runAsync(c.repo.entries))!.firstWhere((e) => e.source == EntrySource.adjustment);
    expect(adj.note, 'خرجِ جاافتاده');
  });

  testWidgets('scenario 6: a wrong "balance now" shows at the next bank SMS (red, no pending)',
      (tester) async {
    final c = await setup(tester, const []);
    await run(tester, () async {
      await c.setBalanceNow('m1', 5000000); // واقعاً ۵٬۱۰۰٬۰۰۰
      await c.intake([mellat('برداشت100,000', '5,000,000', now.add(const Duration(hours: 1)))]);
      await c.acceptMany(c.readyToAccept);
    });
    await tester.pumpWidget(details(c));
    expect(find.text('۱۰٬۰۰۰ تومان واریزِ ثبت‌نشده'), findsOneWidget);
    expect(find.textContaining('شاید فقط پیامکی'), findsNothing);
  });

  testWidgets('missing transaction: the sheet is prefilled with the gap', (tester) async {
    final c = await setup(tester, [
      mellat('برداشت100,000', '900,000', t1),
      mellat('برداشت50,000', '650,000', t3),
    ]);
    await run(tester, () => c.acceptMany(c.readyToAccept).then((_) {}));
    await tester.pumpWidget(details(c));
    await tester.tap(find.byKey(windowAddMissingKey(0)));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '۲۰٬۰۰۰'), findsOneWidget);
    await act(tester, c, () => tester.tap(find.byKey(kEntrySaveKey)));
    expect(find.byKey(windowCardKey(0)), findsNothing);
  });

  testWidgets('edit an entry: categories, then the month report and a budget', (tester) async {
    final c = await setup(tester, [mellat('برداشت100,000', '900,000', t1)]);
    await run(tester, () => c.acceptMany(c.readyToAccept).then((_) {}));
    final e = (await tester.runAsync(c.repo.entries))!.single;
    final bread = c.categories.firstWhere((x) => x.name == 'نان');

    await tester.pumpWidget(details(c));
    await tester.tap(find.byKey(entryRowKey(e.id)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(entryCategoryKey(bread.id)));
    await act(tester, c, () => tester.tap(find.byKey(kEntrySaveKey)));
    expect(c.allocations[e.id]!.single.name, 'نان');

    await tester.pumpWidget(app(MonthReportScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.text('گزارشِ مهر ۱۴۰۵'), findsOneWidget);
    expect(find.byKey(reportCategoryKey('نان')), findsOneWidget);
    expect(find.byKey(kReportUncategorizedKey), findsNothing);

    await tester.tap(find.byKey(reportCategoryKey('نان')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kBudgetFieldKey), '5000');
    await act(tester, c, () => tester.tap(find.byKey(kBudgetSaveKey)));
    expect(find.textContaining('بیشتر از سقفِ'), findsOneWidget); // ۱۰هزار تومان > ۵هزار
  });

  testWidgets('delete an SMS entry from its sheet: the SMS becomes rejected', (tester) async {
    final c = await setup(tester, [mellat('برداشت100,000', '900,000', t1)]);
    await run(tester, () => c.acceptMany(c.readyToAccept).then((_) {}));
    final e = (await tester.runAsync(c.repo.entries))!.single;
    await tester.pumpWidget(details(c));
    await tester.tap(find.byKey(entryRowKey(e.id)));
    await tester.pumpAndSettle();
    await act(tester, c, () => tester.tap(find.byKey(kEntryDeleteKey)));
    await act(tester, c, () => tester.tap(find.text('حذف').last));
    expect(await tester.runAsync(c.repo.entries), isEmpty);
    expect((await tester.runAsync(() => c.repo.smsItem(e.smsKey!)))!.status, SmsStatus.rejected);
  });

  testWidgets("phase 5: the manager sees the family's accounts, read-only", (tester) async {
    final c = await setup(tester, [mellat('برداشت100,000', '900,000', t1)]);
    await run(tester, () async {
      await c.repo.db.insert('wallets', {
        'id': 'z1',
        'owner_name': 'زهرا',
        'owner_user_id': 'u2',
        'label': 'سامان',
        'bank_id': 'saman',
        'created_at': now.toIso8601String(),
      });
      await c.repo.applyRemoteCheckpoint({
        'id': 'zc1',
        'account_id': 'z1',
        'balance_rial': 700000,
        'at': t1.subtract(const Duration(hours: 1)).toIso8601String(),
        'client_updated_at': t1.toIso8601String(),
      });
      await c.repo.applyRemoteEntry({
        'id': 'ze1',
        'account_id': 'z1',
        'kind': 'expense',
        'amount_rial': 200000,
        'occurred_at': t1.toIso8601String(),
        'source': 'manual',
        'client_updated_at': t1.toIso8601String(),
      });
      c.people = () => (meName: 'مهدی', meUserId: 'u1', members: const []);
      await c.setBalanceNow('m1', 900000);
    });
    await tester.pumpWidget(app(LedgerHomeScreen(controller: c, autoSetup: false)));
    await tester.pumpAndSettle();
    expect(find.byKey(kLedgerFamilySectionKey), findsOneWidget);
    expect(find.text('جمعِ همه ${formatToman(1400000)}'), findsOneWidget); // ۹۰ + ۵۰ هزار تومان
    expect(find.textContaining('سامان'), findsWidgets);

    await tester.tap(find.textContaining('سامان').first);
    await tester.pumpAndSettle();
    expect(find.byType(AccountDetailsScreen), findsOneWidget);
    expect(find.text('حسابِ زهرا؛ فقط دیدنی.'), findsOneWidget);
    expect(find.byKey(kDetailsReconcileKey), findsNothing);
    await tester.tap(find.byKey(entryRowKey('ze1')));
    await tester.pumpAndSettle();
    expect(find.byKey(kEntrySaveKey), findsNothing); // برگه‌ی ویرایش باز نمی‌شود
  });
}
