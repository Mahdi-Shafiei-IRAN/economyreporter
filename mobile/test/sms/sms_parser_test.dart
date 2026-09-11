import 'package:economy/core/sms/bank_registry.dart';
import 'package:economy/core/sms/digit_utils.dart';
import 'package:economy/core/sms/models.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = SmsParser();

  group('normalizeDigits', () {
    test('ارقام فارسی → لاتین', () {
      expect(normalizeDigits('۲۵۰۰۰۰۰'), '2500000');
    });
    test('ارقام عربی → لاتین', () {
      expect(normalizeDigits('٢٥٠'), '250');
    });
    test('ترکیب فارسی و لاتین', () {
      expect(normalizeDigits('کارت ۱۲34'), 'کارت 1234');
    });
  });

  group('detectBank — قدم اول: تشخیص بانک از فرستنده', () {
    test('فرستنده‌ی لاتین', () {
      expect(detectBank('BankMellat')?.id, 'mellat');
      expect(detectBank('SB24')?.id, 'saman');
      expect(detectBank('BMI')?.id, 'melli');
    });
    test('فرستنده‌ی فارسی', () {
      expect(detectBank('بانک ملت')?.id, 'mellat');
      expect(detectBank('ملی')?.id, 'melli');
    });
    test('فرستنده‌ی ناشناخته → null', () {
      expect(detectBank('Digikala'), isNull);
      expect(detectBank('98300012'), isNull);
    });
  });

  group('parse — استخراج مبلغ و فیلدها', () {
    test('برداشت به ریال با مبلغ برچسب‌دار، کارت و مانده', () {
      final r = parser.parse(
        sender: 'BankMellat',
        body: 'برداشت مبلغ 2,500,000 ریال از کارت 1234 مانده 43,000,000 ریال',
      );
      expect(r.bankId, 'mellat');
      expect(r.kind, TxKind.expense);
      expect(r.amountRial, 2500000);
      expect(r.balanceAfterRial, 43000000);
      expect(r.cardLast4, '1234');
      expect(r.needsReview, isFalse);
    });

    test('واریز با ارقام فارسی و جداکننده‌ی عربی', () {
      final r = parser.parse(
        sender: 'ملی',
        body: 'واریز مبلغ ۱۲٬۳۴۵٬۰۰۰ ریال به حساب شما مانده ۲۰٬۰۰۰٬۰۰۰ ریال',
      );
      expect(r.bankId, 'melli');
      expect(r.kind, TxKind.income);
      expect(r.amountRial, 12345000);
      expect(r.balanceAfterRial, 20000000);
      expect(r.needsReview, isFalse);
    });

    test('مبلغ به تومان → تبدیل به ریال (×۱۰)', () {
      final r = parser.parse(
        sender: 'Saman',
        body: 'خرید مبلغ 250000 تومان از کارت 5678',
      );
      expect(r.bankId, 'saman');
      expect(r.kind, TxKind.expense);
      expect(r.rawUnit, 'toman');
      expect(r.amountRial, 2500000);
      expect(r.cardLast4, '5678');
    });

    test('کارت‌به‌کارت → نوع transfer', () {
      final r = parser.parse(
        sender: 'BankMellat',
        body: 'انتقال کارت به کارت مبلغ 500,000 ریال از کارت 1234',
      );
      expect(r.kind, TxKind.transfer);
      expect(r.amountRial, 500000);
    });

    test('مبلغ بدون برچسب «مبلغ»', () {
      final r = parser.parse(
        sender: 'Tejarat',
        body: 'برداشت 300,000 ریال از حساب شما',
      );
      expect(r.bankId, 'tejarat');
      expect(r.kind, TxKind.expense);
      expect(r.amountRial, 300000);
    });

    test('کارت ماسک‌شده → چهار رقم آخر', () {
      final r = parser.parse(
        sender: 'Saman',
        body: 'خرید مبلغ 90,000 ریال با کارت 6037****1234',
      );
      expect(r.cardLast4, '1234');
    });

    test('مانده با کلیدواژه‌ی «موجودی»', () {
      final r = parser.parse(
        sender: 'Pasargad',
        body: 'خرید مبلغ 40,000 ریال موجودی 1,000,000 ریال',
      );
      expect(r.balanceAfterRial, 1000000);
      expect(r.amountRial, 40000);
    });
  });

  group('parse — حالت‌های نیازمند بازبینی', () {
    test('فرستنده‌ی ناشناخته ولی مبلغ و نوع معلوم → نیازی به بازبینی نیست', () {
      final r = parser.parse(
        sender: 'Digikala',
        body: 'خرید مبلغ 100,000 ریال',
      );
      expect(r.bankId, isNull);
      expect(r.amountRial, 100000);
      expect(r.kind, TxKind.expense);
      expect(r.needsReview, isFalse);
      expect(r.reviewReasons, isEmpty);
    });

    test('تراکنش ناموفق → بازبینی با دلیل failed', () {
      final r = parser.parse(
        sender: 'BankMellat',
        body: 'خرید ناموفق مبلغ 500,000 ریال از کارت 1234 - موجودی کافی نیست',
      );
      expect(r.amountRial, 500000);
      expect(r.needsReview, isTrue);
      expect(r.reviewReasons, [ReviewReason.failed]);
      expect(r.looksLikeTransaction, isTrue); // وارد می‌شود ولی در صف بازبینی
    });

    test('رمز با مبلغ («رمز: 123456 مبلغ ...») تراکنش حساب نمی‌شود', () {
      final r = parser.parse(
        sender: 'BankMellat',
        body: 'رمز: 482913\nمبلغ: 1,200,000 ریال\nپذیرنده: فروشگاه نمونه',
      );
      expect(r.isOtp, isTrue);
      expect(r.looksLikeTransaction, isFalse);
    });

    test('در واریز، «به کارت …» کارت خودمان است نه طرف حساب', () {
      final r = parser.parse(
        sender: 'Mellat',
        body: 'بانک ملت\nواریز حقوق به کارت 1234\nمبلغ: 185,000,000 ریال',
      );
      expect(r.kind, TxKind.income);
      expect(r.cardLast4, '1234');
      expect(r.counterparty, isNull);
    });

    test('نام پذیرنده تاریخِ بعدش را نمی‌گیرد', () {
      final r = parser.parse(
        sender: 'Saman',
        body: 'سامان\nخرید از کارت 5678\nمبلغ 2,400,000 ریال\nپذیرنده: داروخانه\n1405/06/20 10:30',
      );
      expect(r.counterparty, 'داروخانه');
      expect(r.occurredAt, isNotNull);
    });

    test('کد پیگیری در پیامک واقعی باعث تشخیص OTP نمی‌شود', () {
      final r = parser.parse(
        sender: 'BankMellat',
        body: 'خرید مبلغ 90,000 ریال از کارت 1234 کد پیگیری 123456',
      );
      expect(r.isOtp, isFalse);
      expect(r.looksLikeTransaction, isTrue);
    });

    test('یادآوری سررسید قسط تراکنش نیست', () {
      final r = parser.parse(
        sender: 'BankMellat',
        body: 'یادآوری: سررسید قسط وام شما مبلغ 5,000,000 ریال فردا است',
      );
      expect(r.isReminder, isTrue);
      expect(r.looksLikeTransaction, isFalse);
    });

    test('پیامک نامرتبط → مبلغ null و نوع unknown', () {
      final r = parser.parse(sender: 'BankMellat', body: 'سلام دوست عزیز');
      expect(r.amountRial, isNull);
      expect(r.kind, TxKind.unknown);
      expect(r.needsReview, isTrue);
    });
  });

  group('parse — تاریخ و طرف حساب', () {
    test('تاریخ شمسی استخراج می‌شود', () {
      final r = parser.parse(
        sender: 'BankMellat',
        body: 'برداشت مبلغ 500,000 ریال از کارت 1234 در 1405/06/19 12:30',
      );
      expect(r.occurredAt, isNotNull);
      expect(r.occurredAt!.isUtc, isTrue);
    });

    test('کارت مقصد در انتقال به‌عنوان طرف حساب', () {
      final r = parser.parse(
        sender: 'BankMellat',
        body: 'انتقال کارت به کارت مبلغ 500,000 ریال از کارت 1234 به کارت 5678',
      );
      expect(r.kind, TxKind.transfer);
      expect(r.cardLast4, '1234');
      expect(r.counterparty, 'کارت مقصد 5678');
    });

    test('«بابت» به‌عنوان طرف حساب', () {
      final r = parser.parse(
        sender: 'ملی',
        body: 'خرید مبلغ 200,000 ریال بابت نان مانده 1,000,000 ریال',
      );
      expect(r.counterparty, 'نان');
    });
  });

  group('parse — رمز پویا (OTP)', () {
    test('پیامک رمز پویا تراکنش حساب نمی‌شود', () {
      final r = parser.parse(
        sender: 'BankMellat',
        body: 'رمز پویا: 84512 اعتبار 60 ثانیه',
      );
      expect(r.isOtp, isTrue);
      expect(r.looksLikeTransaction, isFalse);
    });

    test('رمز یکبار مصرف خرید اینترنتی تراکنش نیست', () {
      final r = parser.parse(
        sender: 'Saman',
        body: 'رمز یکبار مصرف خرید اینترنتی شما: 123456',
      );
      expect(r.isOtp, isTrue);
      expect(r.looksLikeTransaction, isFalse);
    });

    test('تراکنش واقعی OTP نیست و looksLikeTransaction=true', () {
      final r = parser.parse(
        sender: 'BankMellat',
        body: 'برداشت مبلغ 2,500,000 ریال از کارت 1234 مانده 43,000,000 ریال',
      );
      expect(r.isOtp, isFalse);
      expect(r.looksLikeTransaction, isTrue);
    });
  });

  group('parse — قالب‌های واقعی', () {
    test('مبلغِ چسبیده به فعل، بدون واحد و بدون «مبلغ»', () {
      final r = parser.parse(
        sender: '',
        body: 'حساب1000000001\nبرداشت12,345,000\nمانده6,000,000\n05/06/19-16:00',
      );
      expect(r.kind, TxKind.expense);
      expect(r.amountRial, 12345000);
      expect(r.balanceAfterRial, 6000000);
      expect(r.accountRef, '1000000001'); // حساب استخراج می‌شود
      expect(r.occurredAt, isNotNull); // سالِ دورقمی هم پارس می‌شود
    });

    test('تشخیص بانک از داخل متن وقتی فرستنده خالی است', () {
      final r = parser.parse(
        sender: '',
        body: '*بانک تجارت* واریز: 500 ریال مانده: 700,000 ریال',
      );
      expect(r.bankId, 'tejarat');
      expect(r.kind, TxKind.income);
      expect(r.amountRial, 500);
      expect(r.needsReview, isFalse);
    });
  });
}
