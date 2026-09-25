import 'package:economy/core/diagnostics/device_health.dart';
import 'package:economy/core/family/health_api.dart';
import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/core/theme/app_theme.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/diagnostics/diagnostics_screen.dart';
import 'package:economy/features/diagnostics/health_view.dart';
import 'package:economy/features/settings/settings_screen.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

class _FakeHealthApi implements HealthApi {
  final List<RemoteDeviceHealth> devices;
  final reported = <DeviceHealthReport>[];
  _FakeHealthApi(this.devices);

  @override
  Future<void> report({required String deviceId, required DeviceHealthReport report}) async =>
      reported.add(report);

  @override
  Future<List<RemoteDeviceHealth>> family() async => devices;
}

void main() {
  final now = DateTime.utc(2026, 9, 25, 9);
  late FakeTransactionStore store;
  late DashboardController c;
  late _FakeHealthApi api;

  RemoteDeviceHealth zahra({required Duration ago, List<HealthIssue> issues = const []}) =>
      RemoteDeviceHealth(
        userId: 'u2',
        userName: 'ZAHRA',
        deviceId: 'dev-zahra',
        appVersion: '1.0.22',
        level: DeviceHealthReport(at: now, issues: issues).level,
        receivedAt: now.subtract(ago),
        report: DeviceHealthReport(
          at: now.subtract(ago),
          appVersion: '1.0.22',
          issues: issues,
          banks: const [BankHealth(name: 'بانک ملت', sms: 5, counted: 3)],
          accounts: const [
            AccountHealth(title: 'بانک ملت • حساب', transactions: 3, problems: 0, balanceRial: 1040193),
          ],
        ),
      );

  setUp(() async {
    store = FakeTransactionStore(clock: () => now);
    await store.setSetting(SettingKeys.deviceId, 'dev-mahdi');
    await store.addAllowedSender('Bank Mellat', bankId: 'mellat');
    final inbox = [
      RawSms(
          sender: 'Bank Mellat',
          body: 'حساب4900000002\nواریز485\nمانده1,040,193',
          receivedAt: now.subtract(const Duration(days: 1))),
    ];
    await SmsImporter(store).importAll(inbox);
    api = _FakeHealthApi([]);
    c = DashboardController(store, clock: () => now)
      ..readInbox = (() async => inbox)
      ..healthApi = api;
    await c.load();
  });

  Widget app(Widget home) => MaterialApp(
        theme: buildAppTheme(Brightness.light),
        builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: home,
      );

  testWidgets('مدیر گوشیِ زهرا را می‌بیند: وضعیت، دلیل و «کجا درستش کنم»', (tester) async {
    api.devices.add(zahra(ago: const Duration(hours: 3), issues: const [
      HealthIssue(HealthLevel.warn, 'deleted_valid',
          '۲ پیامکِ درست (شماره‌ی حساب + مبلغ + نوع) حذف شده و شمرده نمی‌شود.',
          hint: 'عیب‌یابی / پیامک‌ها / «برگرداندنِ …»'),
    ]));
    await tester.pumpWidget(app(DevicesHealthScreen(controller: c)));
    await tester.pumpAndSettle();

    expect(find.text('این گوشی'), findsOneWidget);
    expect(find.text('سالم'), findsOneWidget);
    expect(find.text('ZAHRA'), findsOneWidget);
    expect(find.text('نیاز به بررسی'), findsOneWidget);
    expect(find.textContaining('۲ پیامکِ درست'), findsOneWidget);
    expect(find.textContaining('کجا: عیب‌یابی'), findsOneWidget);
    expect(find.textContaining('۳ ساعت پیش'), findsOneWidget);
    expect(find.textContaining('این گزارش قدیمی است'), findsNothing);
    // وضعیتِ همین گوشی هم فرستاده شد.
    expect(api.reported, hasLength(1));
  });

  testWidgets('گزارشِ قدیمی علامت می‌خورد؛ بدونِ گوشیِ دیگر راهنمایی می‌شود', (tester) async {
    await tester.pumpWidget(app(DevicesHealthScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.textContaining('هنوز گزارشی از گوشیِ دیگری نیامده'), findsOneWidget);

    api.devices.add(zahra(ago: const Duration(days: 4)));
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(find.textContaining('این گزارش قدیمی است'), findsOneWidget);
  });

  testWidgets('تنظیمات ← «سلامتِ برنامه روی گوشی‌ها»', (tester) async {
    await tester.pumpWidget(app(SettingsScreen(controller: c)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(kSettingsDevicesHealthKey), 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(kSettingsDevicesHealthKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kSettingsDevicesHealthKey));
    await tester.pumpAndSettle();
    expect(find.byType(DevicesHealthScreen), findsOneWidget);
  });

  testWidgets('عیب‌یابی بالای صفحه حکمِ کلیِ این گوشی را نشان می‌دهد', (tester) async {
    await tester.pumpWidget(app(DiagnosticsScreen(controller: c)));
    await tester.pumpAndSettle();
    expect(find.byKey(kHealthCardKey), findsOneWidget);
    expect(find.text('وضعیتِ کلیِ این گوشی'), findsOneWidget);
    expect(api.reported, hasLength(1));
  });
}
