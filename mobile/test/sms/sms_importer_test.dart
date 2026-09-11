import 'package:economy/core/sms/sms_importer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

void main() {
  late FakeTransactionStore store;
  late SmsImporter importer;

  setUp(() {
    store = FakeTransactionStore();
    importer = SmsImporter(store);
  });

  test('فقط تراکنش‌های واقعی وارد می‌شوند؛ OTP و نامرتبط رد می‌شوند', () async {
    final messages = [
      const RawSms(
        sender: 'BankMellat',
        body: 'برداشت مبلغ 2,500,000 ریال از کارت 1234 مانده 43,000,000 ریال',
      ),
      const RawSms(sender: 'BankMellat', body: 'رمز پویا: 84512 اعتبار 60 ثانیه'),
      const RawSms(sender: 'Ad', body: 'فروش ویژه تخفیف!'),
      const RawSms(
        sender: 'ملی',
        body: 'واریز مبلغ 10,000,000 ریال به حساب شما',
      ),
    ];

    final result = await importer.importAll(messages);

    expect(result.created, 2); // فقط دو تراکنش واقعی
    expect(result.skipped, 2); // OTP + تبلیغ
    expect(await store.getAll().then((l) => l.length), 2);
  });

  test('پیامک تکراری دوباره ذخیره نمی‌شود', () async {
    final at = DateTime.utc(2026, 6, 1, 10, 0);
    final sms = RawSms(
      sender: 'BankMellat',
      body: 'برداشت مبلغ 500,000 ریال از کارت 1234',
      receivedAt: at,
    );
    expect(await importer.importOne(sms), isTrue);
    expect(await importer.importOne(sms), isFalse); // تکراری
    expect(await store.getAll().then((l) => l.length), 1);
  });
}
