/// طرح ۱۲.۹: صفحه‌ی اصلیِ داشبوردی — ماه، اعضا، کارت‌ها، خالص، دو نما، و فقط‌دیدنی بودنِ مالِ بقیه.
library;

import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/family/family_api.dart';
import 'package:economy/core/format/money_format.dart';
import 'package:economy/core/ledger/dashboard.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/ledger/account_details_screen.dart';
import 'package:economy/features/ledger/entry_sheet.dart';
import 'package:economy/features/ledger/ledger_controller.dart';
import 'package:economy/features/ledger/ledger_home_screen.dart';
import 'package:economy/features/ledger/month_report_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

void main() {
  final now = DateTime.utc(2026, 9, 24, 10); // ۲ مهر ۱۴۰۵
  setUpAll(initSqfliteFfiForTests);

  late Map<String, String> ids;

  Future<LedgerController> setup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.reset);
    late LedgerController c;
    late Database db;
    await tester.runAsync(() async {
      db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
      Future<void> wallet(String id, String owner, String? userId, String label, String? bank, String? last4) =>
          db.insert('wallets', {
            'id': id,
            'owner_name': owner,
            'owner_user_id': userId,
            'label': label,
            'bank_id': bank,
            'card_last4': last4,
            'created_at': now.toIso8601String(),
          });
      await wallet('m1', 'مهدی', 'u1', 'ملت', 'mellat', '5596');
      await wallet('m2', 'مهدی', 'u1', 'نقد', null, null);
      await wallet('z1', 'زهرا', 'u2', 'سامان', 'saman', '1234');
      final repo = LedgerRepository(db, deviceId: 'dev', clock: () => now);
      c = LedgerController(repo,
          allowedSenders: () async => const [], readInbox: () async => const [], clock: () => now);
      c.people = () => (meName: 'مهدی', meUserId: 'u1', members: const []);
      await c.setEnabled(true);
      // تاریخِ شروع از سرور: اولِ شهریور (زودتر از این گوشی).
      await repo.applyRemoteSettings({'start_date': '2026-08-22T20:30:00Z'});
      await repo.addCheckpoint(accountId: 'm1', balanceRial: 1000000, at: DateTime.utc(2026, 9, 1));
      Future<String> add(String acc, EntryKind k, int amount, DateTime at, String note) async =>
          (await repo.addEntry(accountId: acc, kind: k, amountRial: amount, occurredAt: at, note: note)).id;
      ids = {
        'bread': await add('m1', EntryKind.expense, 100000, DateTime.utc(2026, 9, 23, 7), 'نان'),
        'salary': await add('m1', EntryKind.income, 300000, DateTime.utc(2026, 9, 24, 8), 'حقوق'),
        'cash': await add('m2', EntryKind.expense, 20000, DateTime.utc(2026, 9, 24, 9), 'کرایه'),
        'old': await add('m1', EntryKind.expense, 50000, DateTime.utc(2026, 9, 10), 'شهریوری'),
      };
      await repo.applyRemoteCheckpoint({
        'id': 'zc1',
        'account_id': 'z1',
        'balance_rial': 700000,
        'at': '2026-09-22T00:00:00Z',
        'client_updated_at': '2026-09-22T00:00:00Z',
      });
      await repo.applyRemoteEntry({
        'id': 'ze1',
        'account_id': 'z1',
        'kind': 'expense',
        'amount_rial': 200000,
        'occurred_at': '2026-09-23T10:00:00Z',
        'source': 'manual',
        'note': 'خریدِ زهرا',
        'client_updated_at': '2026-09-23T10:00:00Z',
      });
      await c.load();
    });
    addTearDown(() => tester.runAsync(db.close));
    return c;
  }

  Widget app(Widget home) => MaterialApp(
        theme: buildAppTheme(Brightness.light),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: home,
      );

  String net(WidgetTester tester) => tester.widget<Text>(find.byKey(kHomeNetKey)).data!;
  String balance(WidgetTester tester) => tester.widget<Text>(find.byKey(kHomeBalanceKey)).data!;

  testWidgets('balance big, month net small; by member and by month', (tester) async {
    final c = await setup(tester);
    await tester.pumpWidget(app(LedgerHomeScreen(controller: c, autoSetup: false)));
    await tester.pumpAndSettle();

    // همه: بزرگ = موجودیِ الان (ملت ۱٬۱۵۰ + سامان ۵۰۰ هزار ریال؛ نقد نامعلوم)،
    // کوچک = خالص: درآمد ۳۰۰ − هزینه (۱۰۰ + ۲۰ + ۲۰۰).
    expect(find.text('مهر ۱۴۰۵'), findsOneWidget);
    expect(balance(tester), formatToman(1650000));
    expect(find.text('موجودیِ الان (همه)'), findsOneWidget);
    expect(find.textContaining('بدونِ ۱ کارتی که موجودی‌اش'), findsOneWidget);
    expect(net(tester), '−${formatToman(20000)}');
    expect(find.text('خالصِ مهر ۱۴۰۵'), findsOneWidget);
    expect(find.byKey(homePersonSectionKey(kMePersonKey)), findsOneWidget);
    expect(find.byKey(homePersonSectionKey('u2')), findsOneWidget);
    expect(find.text('۳ تراکنش • ۲ کارت/حساب'), findsOneWidget); // مهدی
    expect(find.text('۱ تراکنش • ۱ کارت/حساب'), findsOneWidget); // زهرا

    // تراشه‌ها فقط نامِ افراد است، نه کارت‌ها.
    expect(find.text('همه‌ی کارت‌ها'), findsNothing);
    await tester.tap(find.byKey(homePersonChipKey('u2')));
    await tester.pumpAndSettle();
    expect(balance(tester), formatToman(500000));
    expect(net(tester), '−${formatToman(200000)}');
    expect(find.text('موجودیِ الان (زهرا)'), findsOneWidget);
    expect(find.byKey(homePersonSectionKey(kMePersonKey)), findsNothing);

    await tester.tap(find.byKey(homePersonChipKey(kMePersonKey)));
    await tester.pumpAndSettle();
    expect(balance(tester), formatToman(1150000));
    expect(net(tester), '+${formatToman(180000)}');

    // ماهِ قبل (شهریور)، و مرزها.
    await tester.tap(find.byKey(kHomePersonAllKey));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.byKey(kHomeMonthNextKey)).onPressed, isNull);
    await tester.tap(find.byKey(kHomeMonthPrevKey));
    await tester.pumpAndSettle();
    expect(find.text('شهریور ۱۴۰۵'), findsOneWidget);
    expect(net(tester), '−${formatToman(50000)}');
    expect(tester.widget<IconButton>(find.byKey(kHomeMonthPrevKey)).onPressed, isNull); // قبل از شروع نه

    // لمسِ خلاصه ← گزارشِ همان ماه.
    await tester.tap(find.byKey(kLedgerMonthCardKey));
    await tester.pumpAndSettle();
    expect(find.byType(MonthReportScreen), findsOneWidget);
    expect(find.text('گزارشِ شهریور ۱۴۰۵'), findsOneWidget);
  });

  testWidgets('day by day: Iran days with owner and card; only my entries open for editing', (tester) async {
    final c = await setup(tester);
    await tester.pumpWidget(app(LedgerHomeScreen(controller: c, autoSetup: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('روز به روز'));
    await tester.pumpAndSettle();
    expect(find.byKey(homeDayKey(DateTime.utc(2026, 9, 23, 20, 30))), findsOneWidget); // ۲ مهر
    expect(find.byKey(homeDayKey(DateTime.utc(2026, 9, 22, 20, 30))), findsOneWidget); // ۱ مهر
    expect(find.textContaining('زهرا • سامان ۱۲۳۴'), findsOneWidget);

    await tester.tap(find.byKey(homeEntryKey('ze1')));
    await tester.pumpAndSettle();
    expect(find.byKey(kEntrySaveKey), findsNothing); // مالِ زهرا: فقط دیدنی

    await tester.tap(find.byKey(homeEntryKey(ids['bread']!)));
    await tester.pumpAndSettle();
    expect(find.byKey(kEntrySaveKey), findsOneWidget);
  });

  testWidgets('members and cards: a card opens to its month entries and to its details', (tester) async {
    final c = await setup(tester);
    await tester.pumpWidget(app(LedgerHomeScreen(controller: c, autoSetup: false)));
    await tester.pumpAndSettle();

    expect(find.byKey(homeEntryKey(ids['salary']!)), findsNothing);
    await tester.tap(find.byKey(homeCardRowKey('m1')));
    await tester.pumpAndSettle();
    expect(find.byKey(homeEntryKey(ids['salary']!)), findsOneWidget);
    expect(find.byKey(homeEntryKey(ids['old']!)), findsNothing); // شهریوری در مهر نیست

    // جمع کردنِ یک عضو.
    final zahra = find.descendant(of: find.byKey(homePersonSectionKey('u2')), matching: find.text('زهرا'));
    await tester.tap(zahra);
    await tester.pumpAndSettle();
    expect(find.byKey(homeCardRowKey('z1')), findsNothing);
    await tester.tap(zahra);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(homeCardDetailsKey('z1')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountDetailsScreen), findsOneWidget);
    expect(find.text('حسابِ زهرا؛ فقط دیدنی.'), findsOneWidget);
  });

  testWidgets("the manager sees every family member, even one who has no card yet", (tester) async {
    final c = await setup(tester);
    await tester.runAsync(() async {
      await c.repo.db.insert('settings', {'key': 'my_role', 'value': 'owner'});
      await c.load();
    });
    c.people = () => (
          meName: 'مهدی',
          meUserId: 'u1',
          members: const [
            FamilyMember(id: 'u1', name: 'مهدی'),
            FamilyMember(id: 'u2', name: 'زهرا'),
            FamilyMember(id: 'u3', name: 'بابا'),
          ],
        );
    await tester.pumpWidget(app(LedgerHomeScreen(controller: c, autoSetup: false)));
    await tester.pumpAndSettle();
    expect(find.byKey(homePersonChipKey('u3')), findsOneWidget);
    await tester.tap(find.byKey(homePersonChipKey('u3')));
    await tester.pumpAndSettle();
    expect(find.textContaining('«بابا» هنوز کارتی ندارد'), findsOneWidget);
    expect(balance(tester), 'نامعلوم');
  });
}
