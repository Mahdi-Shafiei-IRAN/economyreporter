import 'dart:convert';

import 'package:economy/core/diagnostics/device_health.dart';
import 'package:economy/core/family/health_api.dart';
import 'package:economy/core/sms/sms_fingerprint.dart';
import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/features/dashboard/dashboard_controller.dart';
import 'package:economy/features/transactions/data/transaction_record.dart';
import 'package:economy/features/transactions/data/transaction_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

class _FakeHealthApi implements HealthApi {
  final reports = <(String, DeviceHealthReport)>[];

  @override
  Future<void> report({required String deviceId, required DeviceHealthReport report}) async =>
      reports.add((deviceId, report));

  @override
  Future<List<RemoteDeviceHealth>> family() async => const [];
}

/// «از کجا بفهمم برنامه روی گوشیِ بقیه درست کار می‌کند؟» — هر گوشی سلامتِ خودش را حساب
/// می‌کند و (بی‌متن و بی‌شماره) برای مدیرِ خانواده می‌فرستد.
void main() {
  var now = DateTime.utc(2026, 9, 25, 9);
  const mellat = 'Bank Mellat';
  RawSms sms(String body, int daysAgo) =>
      RawSms(sender: mellat, body: body, receivedAt: now.subtract(Duration(days: daysAgo)));
  final deposit = sms('حساب4900000002\nواریز485\nمانده1,040,193\n05/06/15-10:39', 10);
  final withdraw = sms('حساب4900000002\nبرداشت1,000\nمانده1,039,193\n05/06/20-10:00', 5);
  final interest =
      sms('واریز سود کوتاه مدت\nحساب4900000002\nمبلغ4,033\n05/07/01', 2);

  late FakeTransactionStore store;
  late DashboardController c;
  late List<RawSms> inbox;
  late _FakeHealthApi api;

  setUp(() async {
    now = DateTime.utc(2026, 9, 25, 9);
    store = FakeTransactionStore(clock: () => now);
    await store.setSetting(SettingKeys.deviceId, 'dev-zahra');
    await store.addAllowedSender(mellat, bankId: 'mellat');
    inbox = [deposit, withdraw];
    api = _FakeHealthApi();
    c = DashboardController(store, clock: () => now)
      ..readInbox = (() async => inbox)
      ..healthApi = api
      ..appVersion = '1.0.22';
  });

  test('همه‌ی پیامک‌ها شمرده شده → سالم', () async {
    await SmsImporter(store).importAll(inbox);
    await c.load();
    final h = await c.deviceHealth();
    expect(h.level, HealthLevel.ok);
    expect(h.issues, isEmpty);
    expect(h.banks.single.name, 'بانک ملت');
    expect([h.banks.single.sms, h.banks.single.counted], [2, 2]);
    expect(h.accounts.single.balanceRial, 1039193);
  });

  test('گوشیِ کاربرِ دوم: نسخه‌ی سرورِ بی‌شماره و پیامکِ درستِ حذف‌شده → نیاز به بررسی', () async {
    inbox = [deposit, withdraw, interest];
    await SmsImporter(store).importAll([withdraw]);
    // بعد از نصبِ دوباره: واریز از سرور برگشته، بدونِ شماره و متن…
    store.addRecord(TransactionRecord(
      id: 'srv-1',
      kind: 'income',
      bankId: 'mellat',
      amountRial: 485,
      balanceAfterRial: 1040193,
      transactionDate: deposit.receivedAt,
      origin: 'remote',
      smsSender: mellat,
      smsBody: deposit.body,
      smsReceivedAt: deposit.receivedAt,
      sourceMessageHash:
          smsFingerprint(sender: mellat, body: deposit.body, receivedAt: deposit.receivedAt),
      createdAt: now,
      updatedAt: now,
    ));
    // …و سودِ ۱ مهر روی نصبِ قبلی حذف شده بود.
    final out = await SmsImporter(store).importAll([interest]);
    expect(out.created, 1);
    final id = (await store.getAll()).firstWhere((t) => t.amountRial == 4033).id;
    await store.deleteTransaction(id);
    await c.load();

    final h = await c.deviceHealth();
    expect(h.level, HealthLevel.warn);
    expect([for (final i in h.issues) i.code], containsAll(['deleted_valid', 'no_id']));
    expect(h.issues.firstWhere((i) => i.code == 'deleted_valid').text, contains('۱ پیامکِ درست'));
  });

  test('بدونِ مجوزِ پیامک یا بدونِ بانکِ انتخاب‌شده → مشکل', () async {
    c.readInbox = () async => throw StateError('no permission');
    await c.load();
    final h = await c.deviceHealth();
    expect(h.level, HealthLevel.bad);
    expect(h.issues.first.code, 'no_permission');
  });

  test('بانکی که هیچ پیامکش شمرده نمی‌شود دیده می‌شود (مثلِ پاسارگاد پیش از ۱٫۰٫۱۹)', () async {
    await store.addAllowedSender('B.Bank', bankId: 'pasargad');
    inbox = [
      for (var i = 0; i < 3; i++)
        RawSms(
            sender: 'B.Bank',
            body: 'برداشت مبلغ ${i + 1},000 ریال انجام شد',
            receivedAt: now.subtract(Duration(hours: i + 1))),
    ];
    await SmsImporter(store).importAll(inbox);
    await c.load();
    final h = await c.deviceHealth();
    expect(h.issues.map((i) => i.code), contains('bank_silent'));
    expect(h.issues.firstWhere((i) => i.code == 'bank_silent').text, contains('بانک پاسارگاد'));
  });

  test('گزارش هیچ متنِ پیامک، شماره‌ی حساب یا سرشماره‌ای ندارد و برمی‌گردد', () async {
    inbox = [deposit, withdraw, interest];
    await SmsImporter(store).importAll(inbox);
    await c.load();
    final h = await c.deviceHealth();
    final json = jsonEncode(h.toJson());
    expect(json, isNot(contains('4900000002')));
    expect(json, isNot(contains('0002')));
    expect(json, isNot(contains(mellat)));
    expect(json, isNot(contains('مانده1,040,193')));
    final back = DeviceHealthReport.fromJson(jsonDecode(json) as Map<String, dynamic>);
    expect(back.level, h.level);
    expect(back.banks.single.counted, h.banks.single.counted);
    expect(back.appVersion, '1.0.22');
  });

  test('گزارش به سرور: بارِ اول، بعد حداکثر هر ۶ ساعت (مگر اجباری)', () async {
    await SmsImporter(store).importAll(inbox);
    await c.load();
    expect(await c.reportHealthIfDue(), isTrue);
    expect(api.reports.single.$1, 'dev-zahra');
    expect(await c.reportHealthIfDue(), isFalse);
    now = now.add(const Duration(hours: 7));
    expect(await c.reportHealthIfDue(), isTrue);
    expect(await c.reportHealthIfDue(force: true), isTrue);
    expect(api.reports, hasLength(3));
  });
}
