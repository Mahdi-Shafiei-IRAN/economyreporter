/// طرح ۱۲.۱۰ روی صفحه: افزودنِ دستیِ فرستنده، وضعیتِ هر فرستنده، و حذفِ کارت با پرسش.
library;

import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/sms/raw_sms.dart';
import 'package:economy/core/store/app_store.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/ledger/account_card.dart';
import 'package:economy/features/ledger/account_details_screen.dart';
import 'package:economy/features/ledger/banks_view.dart';
import 'package:economy/features/ledger/ledger_controller.dart';
import 'package:economy/features/ledger/ledger_settings_screen.dart';
import 'package:economy/features/ledger/sender_ops.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28, 10);
  final t1 = DateTime.utc(2026, 9, 23, 7);
  setUpAll(initSqfliteFfiForTests);

  final inbox = [
    RawSms(sender: 'Bank Mellat', body: 'حساب1000005596\nبرداشت100,000\nمانده900,000', receivedAt: t1),
    // بانکی که پارسر تراکنش نمی‌شناسد؛ در پیشنهادها نیست.
    RawSms(sender: '+98300077', body: 'بانک آینده: موجودی حساب شما تغییر کرد', receivedAt: t1),
  ];

  Future<LedgerController> setup(WidgetTester tester) async {
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
        'owner_user_id': 'u1',
        'label': 'ملت',
        'bank_id': 'mellat',
        'account_ref': '1000005596',
        'created_at': now.toIso8601String(),
      });
      final store = AppStore(db);
      c = LedgerController(LedgerRepository(db, deviceId: 'dev', clock: () => now),
          allowedSenders: store.allowedSenders,
          readInbox: () async => [
                for (final r in inbox) IncomingSms(sender: r.sender, body: r.body, receivedAt: r.receivedAt!),
              ],
          clock: () => now,
          people: () => (meName: 'مهدی', meUserId: 'u1', members: const []),
          senders: ledgerSenderOps(store,
              readInbox: () async => inbox, me: () async => (meName: 'مهدی', meUserId: 'u1')));
      await c.setEnabled(true);
      await c.allowSender('Bank Mellat', 'mellat');
      await c.setBalanceNow('m1', 900000);
      await c.acceptMany(c.readyToAccept);
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

  testWidgets('senders: each chosen one says where its SMS went; an unrecognised one can be added by hand',
      (tester) async {
    final c = await setup(tester);
    await tester.pumpWidget(app(LedgerBanksScreen(controller: c)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    final mellat = c.banks.single;
    expect(find.textContaining('کارت: ملت ۵۵۹۶'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(bankStatusKey(mellat.id))).data, contains('۱ ثبت'));
    expect(find.text('+98300077'), findsNothing); // پارسر نشناخت → در پیشنهادها نیست

    await tester.tap(find.byKey(kBankManualAddKey));
    await tester.pump(); // برگه ساخته شود و خواندنِ صندوق شروع شود
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    // خالی ← خطا؛ تکراری ← خطا.
    await tester.tap(find.byKey(kBankManualSaveKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kBankManualErrorKey), findsOneWidget);
    await tester.enterText(find.byKey(kBankManualAddressKey), 'Bank Mellat');
    await tester.tap(find.byKey(kBankManualSaveKey));
    await tester.pumpAndSettle();
    expect(find.text('این فرستنده از قبل انتخاب شده'), findsOneWidget);

    // انتخاب از فرستنده‌های صندوق.
    await tester.tap(find.byKey(inboxSenderKey('+98300077')));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(kBankManualAddressKey)).controller!.text, '+98300077');
    await act(tester, c, () => tester.tap(find.byKey(kBankManualSaveKey)));

    expect(c.banks.map((b) => b.address), containsAll(['Bank Mellat', '+98300077']));
    expect(c.pending.where((i) => i.sender == '+98300077'), hasLength(1)); // پیامکش خوانده شد
    final added = c.banks.firstWhere((b) => b.address == '+98300077');
    expect(tester.widget<Text>(find.byKey(bankStatusKey(added.id))).data, contains('۱ پیامک'));
  });

  testWidgets('deleting a card from its menu asks first, then removes it with its entries', (tester) async {
    final c = await setup(tester);
    expect(c.entryCountOf('m1'), 1);
    await tester.pumpWidget(app(LedgerCardsSettingsScreen(controller: c)));
    await tester.pumpAndSettle();

    // منو انتخابش را در همان zone می‌دهد که باز شده؛ پس باز کردنش هم در act.
    await act(tester, c, () => tester.tap(find.byKey(ledgerAccountMenuKey('m1'))));
    await act(tester, c, () => tester.tap(find.text('حذفِ کارت و تراکنش‌هایش')));
    expect(find.textContaining('کارت با ۱ تراکنش'), findsOneWidget);
    await act(tester, c, () => tester.tap(find.text('انصراف')));
    expect(c.accounts, hasLength(1)); // انصراف: چیزی حذف نشد

    // منو انتخابش را در همان zone می‌دهد که باز شده؛ پس باز کردنش هم در act.
    await act(tester, c, () => tester.tap(find.byKey(ledgerAccountMenuKey('m1'))));
    await act(tester, c, () => tester.tap(find.text('حذفِ کارت و تراکنش‌هایش')));
    await act(tester, c, () => tester.tap(find.byKey(kDeleteAccountConfirmKey)));
    expect(c.accounts, isEmpty);
    expect(await tester.runAsync(() => c.repo.entries()), isEmpty);
    expect(find.byKey(ledgerAccountCardKey('m1')), findsNothing);
  });

  testWidgets('the account page has a delete button for my own card', (tester) async {
    final c = await setup(tester);
    await tester.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => AccountDetailsScreen(controller: c, accountId: 'm1'))),
          child: const Text('open'),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await act(tester, c, () => tester.tap(find.byKey(kDetailsDeleteKey)));
    await act(tester, c, () => tester.tap(find.byKey(kDeleteAccountConfirmKey)));
    expect(c.accounts, isEmpty);
    expect(find.byType(AccountDetailsScreen), findsNothing); // برگشت به صفحه‌ی قبل
    expect((await tester.runAsync(() => c.repo.smsItems()))!.single.status, SmsStatus.rejected);
  });
}
