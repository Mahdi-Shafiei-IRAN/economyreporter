/// اسکرین‌شاتِ صفحه‌های نسخه‌ی ۲ با فونتِ واقعی (بازبینیِ چشمی بدونِ گوشی).
/// اجرا:  SHOTS_OUT=<پوشه> flutter test screenshot_test/ledger_shots_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/ledger/account_form.dart';
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
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test/helpers/db_test_helper.dart';

const _shotKey = Key('shot');
final _outDir = Platform.environment['SHOTS_OUT'] ?? 'build/screenshots';
final _now = DateTime.utc(2026, 9, 25, 9); // ۳ مهر ۱۴۰۵

Future<void> _loadFonts() async {
  final vazir = FontLoader(kAppFontFamily)
    ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'));
  await vazir.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  final iconsFile = [
    File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'),
    File('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf'),
  ].firstWhere((f) => f.existsSync());
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(iconsFile.readAsBytesSync().buffer.asByteData()));
  await icons.load();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  debugDisableShadows = false;
  tester.binding.buildOwner!.reassemble(tester.binding.rootElement!);
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
  debugDisableShadows = true;
  tester.binding.buildOwner!.reassemble(tester.binding.rootElement!);
  await tester.pumpAndSettle();
}

Widget _app(Widget home, {Brightness brightness = Brightness.light}) => RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(brightness),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: home,
      ),
    );

void _phone(WidgetTester tester, {double height = 1400}) {
  tester.view.physicalSize = Size(393 * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

const _allowed = [
  AllowedSender(id: 's1', address: 'Bank Mellat', bankId: 'mellat'),
  AllowedSender(id: 's2', address: 'B.Pasargad', bankId: 'pasargad'),
];

IncomingSms _sms(String sender, String body, DateTime at) =>
    IncomingSms(sender: sender, body: body, receivedAt: at);

/// دو حساب (ملت با «موجودیِ الان»، پاسارگاد بی‌موجودی) و پیامک‌های منتظرِ جورواجور.
Future<LedgerController> _controller(WidgetTester tester) async {
  late LedgerController c;
  await tester.runAsync(() async {
    final db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    for (final (id, owner, label, bank, ref) in const [
      ('m1', 'مهدی', 'ملت حقوق', 'mellat', '1000000009'),
      ('p1', 'زهرا', 'پاسارگاد', 'pasargad', '777.888.10000001.1'),
    ]) {
      await db.insert('wallets', {
        'id': id,
        'owner_name': owner,
        'label': label,
        'bank_id': bank,
        'account_ref': ref,
        'created_at': _now.toIso8601String(),
      });
    }
    final inbox = [
      _sms('Bank Mellat', 'حساب1000000009\nواریز45,000,000\nمانده71,250,000\n05/07/01-08:00',
          DateTime.utc(2026, 9, 23, 4, 30)),
      _sms('Bank Mellat', 'حساب1000000009\nبرداشت1,250,000\nمانده70,000,000\n05/07/02-12:10',
          DateTime.utc(2026, 9, 24, 8, 40)),
      _sms('Bank Mellat', 'حساب2000000001\nبرداشت500,000\nمانده3,400,000\n05/07/02-18:05',
          DateTime.utc(2026, 9, 24, 14, 35)),
      _sms('B.Pasargad', '777.888.10000001.1\n-7,400,000\n07/03_10:55\nمانده: 95,812,229',
          DateTime.utc(2026, 9, 25, 7, 25)),
      _sms('Bank Mellat', 'رمز پویا: 482913\nمبلغ 1,000,000 ریال\nاعتبار 120 ثانیه',
          DateTime.utc(2026, 9, 25, 8)),
    ];
    c = LedgerController(LedgerRepository(db, deviceId: 'dev', clock: () => _now),
        allowedSenders: () async => _allowed,
        readInbox: () async => inbox,
        clock: () => _now,
        people: () => (meName: 'مهدی', meUserId: 'u1', members: const []),
        senders: SenderOps(
          candidates: () async => [
            const SenderCandidate(
                address: '+98300089',
                bankId: 'tejarat',
                inboxCount: 23,
                stored: [],
                sample: 'بانک تجارت\nبرداشت از حساب 1234567\nمبلغ 2,500,000 ریال\nمانده 18,300,000'),
            const SenderCandidate(
                address: 'Digikala',
                inboxCount: 4,
                stored: [],
                sample: 'خرید شما به مبلغ 1,290,000 ریال ثبت شد. کد تخفیف: DK20'),
          ],
          allow: (_, __) async {},
          dismiss: (_) async {},
          remove: (_) async {},
        ));
    await c.setEnabled(true);
    await c.setBalanceNow('m1', 70000000);
    final first = c.pending.firstWhere((i) => i.suggestion.amountRial == 45000000);
    await c.acceptSuggested(first);
  });
  return c;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    initSqfliteFfiForTests();
    await _loadFonts();
  });

  testWidgets('ledger home light', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(LedgerHomeScreen(
        controller: await _controller(tester), onOpenSettings: () {}, autoSetup: false)));
    await _shot(tester, 'v2_01_home_light');
  });

  testWidgets('ledger home dark', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(
        LedgerHomeScreen(controller: await _controller(tester), onOpenSettings: () {}, autoSetup: false),
        brightness: Brightness.dark));
    await _shot(tester, 'v2_02_home_dark');
  });

  testWidgets('setup step 1 banks', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(LedgerSetupScreen(controller: await _controller(tester))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await _shot(tester, 'v2_07_setup_banks');
  });

  testWidgets('setup step 2 accounts', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(LedgerSetupScreen(controller: await _controller(tester))));
    await tester.tap(find.byKey(kSetupNextKey));
    await _shot(tester, 'v2_08_setup_accounts');
  });

  testWidgets('v2 settings', (tester) async {
    _phone(tester, height: 1100);
    await tester.pumpWidget(_app(LedgerSettingsScreen(
        controller: await _controller(tester), onCheckUpdate: () async => '', onLogout: () {})));
    await _shot(tester, 'v2_09_settings');
  });

  testWidgets('guide', (tester) async {
    _phone(tester, height: 1100);
    await tester.pumpWidget(_app(const LedgerGuideScreen()));
    await _shot(tester, 'v2_10_guide');
  });

  testWidgets('pending', (tester) async {
    _phone(tester, height: 1900);
    await tester.pumpWidget(_app(PendingScreen(controller: await _controller(tester))));
    await _shot(tester, 'v2_03_pending');
  });

  testWidgets('pending selecting', (tester) async {
    _phone(tester, height: 1900);
    await tester.pumpWidget(_app(PendingScreen(controller: await _controller(tester))));
    await tester.tap(find.byKey(kPendingSelectReadyKey));
    await _shot(tester, 'v2_04_pending_selecting');
  });

  testWidgets('entry sheet', (tester) async {
    _phone(tester);
    final c = await _controller(tester);
    await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
            body: Center(
                child: FilledButton(
                    onPressed: () => showEntrySheet(context, c, item: c.pendingActive.first),
                    child: const Text('open')))))));
    await tester.tap(find.text('open'));
    await _shot(tester, 'v2_05_entry_sheet');
  });

  testWidgets('account form', (tester) async {
    _phone(tester);
    final c = await _controller(tester);
    final unknown = c.pending.firstWhere((i) => i.suggestion.unknownAccountNumber);
    await tester.pumpWidget(_app(Builder(
        builder: (context) => Scaffold(
            body: Center(
                child: FilledButton(
                    onPressed: () => showAccountForm(context, c, prefill: c.prefillFrom(unknown)),
                    child: const Text('open')))))));
    await tester.tap(find.text('open'));
    await _shot(tester, 'v2_06_account_form');
  });
}
