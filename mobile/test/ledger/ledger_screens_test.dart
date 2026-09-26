import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/ledger/account_card.dart';
import 'package:economy/features/ledger/account_form.dart';
import 'package:economy/features/ledger/accounts_view.dart';
import 'package:economy/features/ledger/banks_view.dart';
import 'package:economy/features/ledger/entry_sheet.dart';
import 'package:economy/features/ledger/guide_screen.dart';
import 'package:economy/features/ledger/ledger_controller.dart';
import 'package:economy/features/ledger/ledger_home_screen.dart';
import 'package:economy/features/ledger/ledger_settings_screen.dart';
import 'package:economy/features/ledger/pending_screen.dart';
import 'package:economy/features/ledger/setup_screen.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:economy/features/senders/data/sender_candidates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

void main() {
  const allowed = [AllowedSender(id: 's1', address: 'Bank Mellat', bankId: 'mellat')];
  final now = DateTime.utc(2026, 9, 24, 10);
  final t1 = DateTime.utc(2026, 9, 23, 7), t2 = DateTime.utc(2026, 9, 23, 8);

  IncomingSms mellat(String account, String line, String balance, DateTime at) => IncomingSms(
      sender: 'Bank Mellat', body: 'حساب$account\n$line\nمانده$balance', receivedAt: at);

  setUpAll(initSqfliteFfiForTests);

  /// دیتابیسِ تازه با حسابِ ملت و دو پیامکِ این ماه، نسخه‌ی ۲ روشن.
  Future<LedgerController> setup(WidgetTester tester, {List<IncomingSms>? inbox}) async {
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
      final sms = inbox ??
          [
            mellat('1000005596', 'برداشت100,000', '900,000', t1),
            mellat('1000005596', 'واریز300,000', '1,200,000', t2),
          ];
      c = LedgerController(LedgerRepository(db, deviceId: 'dev', clock: () => now),
          allowedSenders: () async => allowed, readInbox: () async => sms, clock: () => now);
      await c.setEnabled(true);
    });
    addTearDown(() => tester.runAsync(db.close));
    return c;
  }

  Widget app(Widget home) => MaterialApp(
        theme: buildAppTheme(Brightness.light),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: home,
      );

  /// لمس/کشیدنی که به دیتابیس می‌رسد بیرون از ساعتِ جعلیِ تست اجرا می‌شود (وگرنه آینده‌های
  /// sqflite هرگز تمام نمی‌شوند)؛ بعد صفحه دوباره ساخته می‌شود.
  Future<void> act(WidgetTester tester, LedgerController c, Future<void> Function() gesture) async {
    await tester.runAsync(() async {
      await gesture();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await c.settle();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
  }

  /// کشیدن: Dismissible برای صدا زدنِ confirmDismiss فریم می‌خواهد؛ پس فریم (ساعتِ جعلی) و
  /// انتظارِ واقعی (پاسخِ دیتابیس) یکی‌درمیان.
  Future<void> swipe(WidgetTester tester, LedgerController c, Finder card, Offset by) async {
    await tester.drag(card, by);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      if (i > 12 && c.isIdle) break;
    }
    await tester.pumpAndSettle();
  }

  Future<List<Entry>> entries(WidgetTester tester, LedgerController c) async =>
      (await tester.runAsync(c.repo.entries))!;

  Future<SmsStatus> status(WidgetTester tester, LedgerController c, String key) async =>
      (await tester.runAsync(() => c.repo.smsItem(key)))!.status;

  List<SmsItem> oldestFirst(LedgerController c) =>
      [...c.pending]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));

  testWidgets('home: next step goes from "balance now" to pending SMS', (tester) async {
    final c = await setup(tester);
    await tester.pumpWidget(app(LedgerHomeScreen(controller: c, autoSetup: false)));
    expect(find.text('قدمِ بعدی: موجودیِ الانِ ۱ حساب'), findsOneWidget);

    await tester.tap(find.byKey(ledgerSetBalanceKey('m1')));
    await tester.pumpAndSettle();
    expect(find.text('۱۲۰٬۰۰۰'), findsOneWidget); // ۱٬۲۰۰٬۰۰۰ ریال
    await act(tester, c, () => tester.tap(find.byKey(kBalanceSaveKey)));

    expect(c.accounts.single.balance!.balanceRial, 1200000);
    expect(find.text('۱۲۰٬۰۰۰ تومان'), findsWidgets);
    expect(find.byKey(ledgerSetBalanceKey('m1')), findsNothing);
    expect(find.text('قدمِ بعدی: ۲ پیامکِ منتظرِ تأیید'), findsOneWidget);

    await tester.tap(find.byKey(kLedgerNextStepKey));
    await tester.pumpAndSettle();
    expect(find.byType(PendingScreen), findsOneWidget);
  });

  testWidgets('pending: accept, not-a-transaction, and nothing auto-recorded', (tester) async {
    final c = await setup(tester);
    await tester.pumpWidget(app(PendingScreen(controller: c)));
    expect(await entries(tester, c), isEmpty);

    final items = oldestFirst(c);
    await act(tester, c, () => tester.tap(find.byKey(pendingAcceptKey(items[0].key))));
    await act(tester, c, () => tester.tap(find.byKey(pendingNotTxKey(items[1].key))));

    expect(find.byKey(kPendingEmptyKey), findsOneWidget);
    expect((await entries(tester, c)).single.amountRial, 100000);
    expect(await status(tester, c, items[1].key), SmsStatus.rejected);
  });

  testWidgets('pending: select the problem-free ones, then accept them by hand', (tester) async {
    final c = await setup(tester);
    await tester.pumpWidget(app(PendingScreen(controller: c)));
    await tester.tap(find.byKey(kPendingSelectReadyKey));
    await tester.pumpAndSettle();
    expect(find.text('۲ انتخاب‌شده'), findsOneWidget);
    expect(await entries(tester, c), isEmpty); // انتخاب ≠ ثبت

    await act(tester, c, () => tester.tap(find.byKey(kPendingAcceptSelectedKey)));
    expect(await entries(tester, c), hasLength(2));
    expect(c.pendingCount, 0);
  });

  testWidgets('pending: swipe right accepts, swipe left rejects (RTL)', (tester) async {
    final c = await setup(tester);
    await tester.pumpWidget(app(PendingScreen(controller: c)));
    final items = oldestFirst(c);

    await swipe(tester, c, find.byKey(pendingCardKey(items[0].key)), const Offset(600, 0));
    expect(await status(tester, c, items[0].key), SmsStatus.accepted);

    await swipe(tester, c, find.byKey(pendingCardKey(items[1].key)), const Offset(-600, 0));
    expect(await status(tester, c, items[1].key), SmsStatus.rejected);
    expect(await entries(tester, c), hasLength(1));
  });

  testWidgets('edit and accept: changed amount and note are saved, bank balance kept', (tester) async {
    final c = await setup(tester);
    await tester.pumpWidget(app(PendingScreen(controller: c)));
    final item = oldestFirst(c).first;
    await tester.tap(find.byKey(pendingEditKey(item.key)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(kEntryAmountKey), '۱۲٬۰۰۰');
    await tester.enterText(find.byKey(kEntryNoteKey), 'نانوایی');
    await act(tester, c, () => tester.tap(find.byKey(kEntrySaveKey)));

    final e = (await entries(tester, c)).single;
    expect(e.amountRial, 120000);
    expect(e.note, 'نانوایی');
    expect(e.bankBalanceAfter, 900000);
  });

  testWidgets('manual entry from home needs kind and amount', (tester) async {
    final c = await setup(tester);
    await tester.pumpWidget(app(LedgerHomeScreen(controller: c, autoSetup: false)));
    await tester.tap(find.byKey(kLedgerAddFabKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kEntrySaveKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kEntryErrorKey), findsOneWidget);

    await tester.tap(find.text('برداشت / هزینه'));
    await tester.enterText(find.byKey(kEntryAmountKey), '50000');
    await act(tester, c, () => tester.tap(find.byKey(kEntrySaveKey)));
    final e = (await entries(tester, c)).single;
    expect(e.source, EntrySource.manual);
    expect(e.amountRial, 500000);
    expect(c.monthExpense, 500000);
  });

  testWidgets('unknown account number: the found account is accepted with its last balance',
      (tester) async {
    final c = await setup(tester, inbox: [mellat('2000000001', 'برداشت50,000', '450,000', t1)]);
    await tester.pumpWidget(app(PendingScreen(controller: c)));
    final item = c.pending.single;
    await tester.tap(find.byKey(pendingNewAccountKey(item.key)));
    await tester.pumpAndSettle();
    final cand = c.accountCandidates.single;
    expect(find.text('بانک ملت • حساب ۲۰۰۰۰۰۰۰۰۱'), findsOneWidget);
    await tester.tap(find.byKey(candidateAcceptKey(cand.key)));
    await tester.pumpAndSettle();
    expect(find.text('۴۵٬۰۰۰'), findsOneWidget);
    await act(tester, c, () => tester.tap(find.byKey(kCandidateSaveKey)));

    final a = c.accounts.firstWhere((v) => v.account.accountRef == '2000000001');
    expect(a.balance!.balanceRial, 450000);
    expect(a.account.label, 'بانک ملت');
    expect(c.pending.single.suggestion.accountId, a.account.id);
    expect(c.accountCandidates, isEmpty);
  });

  testWidgets('first run: the 3-step guide opens by itself and can be finished', (tester) async {
    var allowedNow = <AllowedSender>[];
    late LedgerController c;
    late Database db;
    await tester.runAsync(() async {
      db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
      final sms = [mellat('2000000001', 'برداشت50,000', '450,000', t1)];
      c = LedgerController(LedgerRepository(db, deviceId: 'dev', clock: () => now),
          allowedSenders: () async => allowedNow,
          readInbox: () async => sms,
          clock: () => now,
          senders: SenderOps(
            candidates: () async => allowedNow.isEmpty
                ? const [SenderCandidate(address: 'Bank Mellat', bankId: 'mellat', inboxCount: 1)]
                : const [],
            allow: (address, bankId) async =>
                allowedNow = [AllowedSender(id: 's1', address: address, bankId: bankId)],
            dismiss: (_) async {},
            remove: (_) async {},
          ));
      await c.setEnabled(true);
    });
    addTearDown(() => tester.runAsync(db.close));

    await tester.pumpWidget(app(LedgerHomeScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.byType(LedgerSetupScreen), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    // قدمِ ۱: بانک است.
    // دیالوگ هم باید بیرون از ساعتِ جعلی باز شود تا ادامه‌ی کار (نوشتن در دیتابیس) اجرا شود.
    await act(tester, c, () => tester.tap(find.byKey(bankAllowKey('Bank Mellat'))));
    await act(tester, c, () => tester.tap(find.byKey(kBankPickSaveKey)));
    expect(c.pending, hasLength(1));

    // قدمِ ۲: حسابِ پیداشده.
    await tester.tap(find.byKey(kSetupNextKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(candidateAcceptKey(c.accountCandidates.single.key)));
    await tester.pumpAndSettle();
    await act(tester, c, () => tester.tap(find.byKey(kCandidateSaveKey)));
    expect(c.activeAccounts.single.balance!.balanceRial, 450000);

    // قدمِ ۳: پیامک‌ها.
    await tester.tap(find.byKey(kSetupNextKey));
    await tester.pumpAndSettle();
    expect(find.text('۱ پیامکِ این ماه منتظرِ تأییدِ توست.'), findsOneWidget);
    await act(tester, c, () => tester.tap(find.byKey(kSetupNextKey)));
    expect(c.setupDone, isTrue);
    expect(find.byType(PendingScreen), findsOneWidget);
  });

  testWidgets('v2 settings show only v2 things (no old review/diagnostics tools)', (tester) async {
    final c = await setup(tester);
    await tester.pumpWidget(app(LedgerSettingsScreen(controller: c, onLogout: () {})));
    expect(find.byKey(kLedgerSettingsGuideKey), findsOneWidget);
    expect(find.byKey(kLedgerSettingsBanksKey), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing); // کلیدِ برگشت به نسخه‌ی ۱ حذف شد
    for (final old in ['بازبینی پیامک‌های مبهم', 'عیب‌یابی موجودی و پیامک‌ها', 'کارت‌ها و حساب‌ها',
      'منتظر دسته‌بندی', 'همگام‌سازی الان']) {
      expect(find.text(old), findsNothing, reason: old);
    }
    await tester.tap(find.byKey(kLedgerSettingsGuideKey));
    await tester.pumpAndSettle();
    expect(find.byType(LedgerGuideScreen), findsOneWidget);
  });

}
