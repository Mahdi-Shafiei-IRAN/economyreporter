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
    test('فرستنده‌ی ناشناخته → مبلغ استخراج می‌شود ولی needsReview', () {
      final r = parser.parse(
        sender: 'Digikala',
        body: 'خرید مبلغ 100,000 ریال',
      );
      expect(r.bankId, isNull);
      expect(r.amountRial, 100000);
      expect(r.kind, TxKind.expense);
      expect(r.needsReview, isTrue);
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
}
