/// اسکرین‌شاتِ صفحه‌ها با فونت واقعی (برای بازبینی چشمی UI بدون گوشی).
///
/// اجرا:  SHOTS_OUT=<پوشه> flutter test screenshot_test
/// (جزو تست‌های عادی نیست؛ خروجی PNG می‌سازد.)
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:economy/core/family/family_api.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/dashboard/dashboard_screen.dart';
import 'package:economy/features/review/reconciliation_screen.dart';
import 'package:economy/features/review/review_screen.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:economy/features/wallets/data/wallet.dart';
import 'package:economy/features/wallets/wallets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/helpers/fake_transaction_store.dart';

const _shotKey = Key('shot');
final _outDir = Platform.environment['SHOTS_OUT'] ?? 'build/screenshots';
final _now = DateTime.utc(2026, 9, 11, 9); // ۲۰ شهریور ۱۴۰۵

Future<void> _loadFonts() async {
  final vazir = FontLoader(kAppFontFamily)
    ..addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'));
  await vazir.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  final iconsFile = File('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(iconsFile.readAsBytesSync().buffer.asByteData()));
  await icons.load();
}

Future<FakeTransactionStore> _sampleStore() async {
  const parser = SmsParser();
  final store = FakeTransactionStore(clock: () => _now, categorizeFrom: DateTime.utc(2026, 8, 22, 20, 30));
  store.settings[SettingKeys.meUserId] = 'u-me';
  store.settings[SettingKeys.meName] = 'مهدی';
  store.settings[SettingKeys.familyMembers] = FamilyMember.encodeList(const [
    FamilyMember(id: 'u-me', name: 'مهدی'),
    FamilyMember(id: 'u-father', name: 'بابا'),
  ]);
  await store.addWallet(const Wallet(
      id: '', ownerName: 'بابا', ownerUserId: 'u-father', label: 'کارت حقوق', bankId: 'mellat', cardLast4: '1234'));
  await store.addWallet(const Wallet(
      id: '', ownerName: 'مامان', label: 'کارت خانه', bankId: 'saman', cardLast4: '5678'));
  await store.addWallet(const Wallet(
      id: '', ownerName: 'مهدی', ownerUserId: 'u-me', label: 'کارت دانشجویی', bankId: 'blu', cardLast4: '9012'));

  void sms(String sender, String body, DateTime at) =>
      store.seed(parser.parse(sender: sender, body: body), sender: sender, receivedAt: at);

  sms('Mellat', 'بانک ملت\nواریز حقوق به کارت 1234\nمبلغ: 185,000,000 ریال\nمانده: 227,300,000 ریال\n1405/06/01 09:00',
      DateTime.utc(2026, 8, 23, 5, 30));
  sms('Mellat', 'بانک ملت\nخرید از کارت 1234\nمبلغ: 1,850,000 ریال\nپذیرنده: فروشگاه رفاه\nمانده: 225,450,000 ریال\n1405/06/19 18:42',
      DateTime.utc(2026, 9, 10, 15, 12));
  sms('Saman', 'سامان\nبرداشت از کارت 5678\nمبلغ 620,000 ریال\nبابت: نانوایی و میوه\n1405/06/18 11:15',
      DateTime.utc(2026, 9, 9, 7, 45));
  sms('Saman', 'سامان\nخرید از کارت 5678\nمبلغ 2,400,000 ریال\nپذیرنده: داروخانه\n1405/06/20 10:30',
      DateTime.utc(2026, 9, 11, 7, 0));
  sms('Mellat', 'بانک ملت\nخرید ناموفق از کارت 1234 مبلغ 3,400,000 ریال - موجودی کافی نیست\n1405/06/19 21:03',
      DateTime.utc(2026, 9, 10, 17, 33));
  sms('Pasargad', 'پاسارگاد\nخرید با کارت 4321\nمبلغ: 240,000 ریال\nپذیرنده: اسنپ\n1405/06/17 08:30',
      DateTime.utc(2026, 9, 8, 5, 0));
  sms('Blu', 'بلو\nخرید از کارت 9012 مبلغ 95,000 تومان\nپذیرنده: کافه\n1405/06/20 10:05',
      DateTime.utc(2026, 9, 11, 6, 35));
  sms('Saman', 'سامان\nخرید ناموفق از کارت 5678\nمبلغ 1,200,000 ریال\nرمز نامعتبر\n1405/06/20 08:10',
      DateTime.utc(2026, 9, 11, 4, 40));

  // تراکنشی که روی گوشی بابا ثبت شده (از سرور آمده) — برای من فقط دیدنی.
  store.addRecord(TransactionRecord(
    id: 'remote-1',
    kind: 'expense',
    amountRial: 4200000,
    counterparty: 'تعمیرگاه',
    ownerUserId: 'u-father',
    ownerName: 'بابا',
    walletLabel: 'کارت حقوق',
    bankId: 'mellat',
    cardLast4: '1234',
    origin: 'remote',
    syncStatus: 'synced',
    transactionDate: DateTime.utc(2026, 9, 7, 13, 20),
    createdAt: DateTime.utc(2026, 9, 7),
    updatedAt: DateTime.utc(2026, 9, 7),
    allocations: const [Allocation('حمل‌ونقل', 4200000)],
  ));

  final all = await store.getAll();
  final bread = all.firstWhere((t) => t.counterparty == 'نانوایی و میوه');
  await store.categorize(bread.id, ['c1', 'c2']);
  return store;
}

Widget _app(Widget home, {Brightness brightness = Brightness.light}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(brightness),
      builder: (context, child) => RepaintBoundary(
        key: _shotKey,
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: home,
    );

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  // در تست به‌جای سایه خط سیاه کشیده می‌شود؛ برای تصویر واقعی، فقط هنگام عکس
  // سایه‌ها روشن و همه‌چیز دوباره نقاشی می‌شود (قبل از پایان تست برمی‌گردد).
  debugDisableShadows = false;
  _repaintAll(tester);
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
  _repaintAll(tester);
  await tester.pumpAndSettle();
}

/// همه‌ی درخت را کثیف می‌کند تا فریم بعدی با تنظیم جدیدِ سایه نقاشی شود.
/// (منتظرِ reassembleApplication نمی‌مانیم؛ در ساعتِ جعلیِ تست فریم خودبه‌خود
/// نمی‌آید و آن await قفل می‌شد.)
void _repaintAll(WidgetTester tester) {
  final root = tester.binding.rootElement;
  if (root != null) tester.binding.buildOwner!.reassemble(root);
}

void _phone(WidgetTester tester, {double height = 1500}) {
  tester.view.physicalSize = Size(393 * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFonts();
  });

  Future<DashboardController> controller() async {
    final c = DashboardController(await _sampleStore(), clock: () => _now);
    await c.load();
    return c;
  }

  testWidgets('home people light', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(DashboardScreen(controller: await controller())));
    await _shot(tester, '01_home_people_light');
  });

  testWidgets('home people dark', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(DashboardScreen(controller: await controller()),
        brightness: Brightness.dark));
    await _shot(tester, '02_home_people_dark');
  });

  testWidgets('home all + selection', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(DashboardScreen(controller: await controller())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('همه با هم'));
    await _shot(tester, '03_home_all_light');

    await tester.longPress(find.text('داروخانه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نانوایی و میوه'));
    await _shot(tester, '04_home_selection_light');
  });

  testWidgets('details own + readonly', (tester) async {
    _phone(tester, height: 1500);
    await tester.pumpWidget(_app(DashboardScreen(controller: await controller())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('نانوایی و میوه'));
    await _shot(tester, '05_details_own_light');

    await tester.tapAt(const Offset(200, 40)); // بستن برگه
    await tester.pumpAndSettle();
    await tester.tap(find.text('تعمیرگاه'));
    await _shot(tester, '06_details_readonly_light');
  });

  testWidgets('review', (tester) async {
    _phone(tester, height: 1100);
    await tester.pumpWidget(_app(ReviewScreen(controller: await controller())));
    await _shot(tester, '07_review_light');
  });

  testWidgets('report', (tester) async {
    _phone(tester, height: 2100);
    await tester.pumpWidget(_app(DashboardScreen(controller: await controller())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kNavReportKey));
    await _shot(tester, '08_report_light');
  });

  testWidgets('settings', (tester) async {
    _phone(tester, height: 1900);
    await tester.pumpWidget(_app(DashboardScreen(controller: await controller())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kNavSettingsKey));
    await _shot(tester, '09_settings_light');
  });

  testWidgets('reconciliation', (tester) async {
    _phone(tester, height: 1000);
    final store = await _sampleStore();
    TransactionRecord rec(String id, String kind, int amount, int balance, DateTime at) =>
        TransactionRecord(
          id: id,
          kind: kind,
          amountRial: amount,
          balanceAfterRial: balance,
          bankId: 'mellat',
          cardLast4: '1234',
          ownerName: 'بابا',
          ownerUserId: 'u-father',
          walletLabel: 'کارت حقوق',
          counterparty: 'فروشگاه',
          transactionDate: at,
          createdAt: at,
          updatedAt: at,
        );
    store.addRecord(rec('g1', 'expense', 500000, 30000000, DateTime.utc(2026, 9, 5, 8)));
    store.addRecord(rec('g2', 'expense', 200000, 26800000, DateTime.utc(2026, 9, 6, 9)));
    final c = DashboardController(store, clock: () => _now);
    await c.load();
    await tester.pumpWidget(_app(ReconciliationScreen(controller: c)));
    await _shot(tester, '10_reconcile_light');
  });

  testWidgets('wallets', (tester) async {
    _phone(tester, height: 1000);
    await tester.pumpWidget(_app(WalletsScreen(controller: await controller())));
    await _shot(tester, '11_wallets_light');
  });
}
