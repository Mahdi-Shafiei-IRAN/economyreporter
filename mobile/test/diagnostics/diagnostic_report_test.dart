import 'package:economy/core/diagnostics/balance_breakdown.dart';
import 'package:economy/core/diagnostics/balance_chain.dart';
import 'package:economy/core/diagnostics/diagnostic_report.dart';
import 'package:economy/core/diagnostics/sms_diagnosis.dart';
import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/features/transactions/data/period.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_transaction_store.dart';

void main() {
  group('maskSensitive', () {
    test('شماره حساب چسبیده به «حساب» پوشانده می‌شود ولی مبلغ و مانده نه', () {
      expect(
        maskSensitive('حساب1000000009\nبرداشت1,250,000\nمانده8,750,000'),
        'حساب******0009\nبرداشت1,250,000\nمانده8,750,000',
      );
    });

    test('شماره کارتِ کامل/ماسک‌شده و ارقام فارسی', () {
      expect(maskSensitive('کارت: ۶۰۳۷۹۹۷۵۱۲۳۴۵۶۷۸ خرید'), 'کارت: ************5678 خرید');
      expect(maskSensitive('کارت 6037-99**-****-5678'), 'کارت ****-****-****-5678');
    });

    test('۴ رقمِ آخرِ کارت و مبلغ‌های بی‌کاما دست نمی‌خورند', () {
      expect(maskSensitive('کارت 5678 خرید مبلغ 250000 تومان'),
          'کارت 5678 خرید مبلغ 250000 تومان');
    });

    test('حسابِ نقطه‌دارِ پاسارگاد پوشانده می‌شود، مبلغ نه', () {
      expect(maskSensitive('777.888.21819509.1\n7,400,000-'), '***.***.*****509.1\n7,400,000-');
    });

    test('شماره‌ی موبایل/شبا (رشته‌ی عددیِ بلند) هر جا باشد پوشانده می‌شود', () {
      expect(maskSensitive('از 09121234567'), 'از *******4567');
      expect(maskSensitive('IR120170000000123456789012'), 'IR${'*' * 20}9012');
    });
  });

  test('گزارشِ متنی شامل هر سه بخش است و شماره‌ی حساب را لو نمی‌دهد', () async {
    final now = DateTime.utc(2026, 9, 23, 12);
    final store = FakeTransactionStore(clock: () => now);
    await store.addAllowedSender('9830001234', bankId: 'mellat');
    await store.addAllowedSender('DigiPay');
    final inbox = [
      RawSms(
          sender: '9830001234',
          body: 'حساب1000000009\nبرداشت1,250,000\nمانده8,750,000\n05/07/01-15:40',
          receivedAt: now),
      RawSms(
          sender: 'DigiPay',
          body: 'پرداخت بدهی و شارژ اعتبار دیجی‌پی\nاعتبار قابل مصرف: ۵۰٬۰۰۰٬۰۰۰ ریال',
          receivedAt: now.add(const Duration(minutes: 1))),
    ];
    await SmsImporter(store).importAll(inbox);
    final all = await store.getAll();

    final text = buildDiagnosticReport(
      balance: computeBalanceBreakdown(all, Period.containing(now)),
      chains: auditBalanceChains(all),
      sms: diagnoseSms(inbox: inbox, stored: all, allowed: await store.allowedSenders()),
      now: now,
    );
    expect(text, contains('== موجودی'));
    expect(text, contains('== زنجیره‌ی مانده'));
    expect(text, contains('== پیامک‌های فرستنده‌های مجاز'));
    expect(text, contains('نمی‌خوانند: 0'));
    expect(text, contains('رد: شماره حساب/کارت ندارد'));
    expect(text, contains('حساب ******0009'));
    expect(text, isNot(contains('1000000009')));
  });
}
