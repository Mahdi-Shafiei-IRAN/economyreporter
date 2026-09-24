import 'package:economy/core/sms/jalali.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('jalaliToGregorian', () {
    test('نوروز ۱۴۰۳ = ۲۰ مارس ۲۰۲۴', () {
      expect(jalaliToGregorian(1403, 1, 1), [2024, 3, 20]);
    });
    test('نوروز ۱۴۰۰ = ۲۱ مارس ۲۰۲۱', () {
      expect(jalaliToGregorian(1400, 1, 1), [2021, 3, 21]);
    });
  });

  group('extractOccurredAt', () {
    test('تاریخ + ساعت → UTC (ایران UTC+3:30)', () {
      final g = jalaliToGregorian(1405, 6, 19);
      final expected = DateTime.utc(g[0], g[1], g[2], 12, 30)
          .subtract(const Duration(hours: 3, minutes: 30));
      expect(extractOccurredAt('برداشت 1405/06/19 12:30 مانده 100'), expected);
    });

    test('تاریخ بدون ساعت → نیمه‌شب ایران', () {
      final g = jalaliToGregorian(1405, 6, 19);
      final expected = DateTime.utc(g[0], g[1], g[2], 0, 0)
          .subtract(const Duration(hours: 3, minutes: 30));
      expect(extractOccurredAt('برداشت در 1405/06/19'), expected);
    });

    test('بدون تاریخ → null', () {
      expect(extractOccurredAt('برداشت مبلغ 100000 ریال'), isNull);
    });

    test('تاریخ میلادی‌نما (خارج بازه‌ی شمسی) → null', () {
      expect(extractOccurredAt('کد 2023/06/19'), isNull);
    });
  });

  group('پاسارگاد: «ماه/روز_ساعت» بی‌سال', () {
    // ۱ مهر ۱۴۰۵ ساعتِ ۱۲ تهران.
    final received = DateTime.utc(2026, 9, 23, 8, 30);

    test('سالِ زمانِ رسیدن', () {
      final at = extractOccurredAt('777.888.10000001.1 -1,850,000 05/27 12:50', reference: received);
      expect(at, isNull); // بدونِ «_» قالبِ پاسارگاد نیست
      final t = extractOccurredAt('777.888.10000001.1 -1,850,000 05/27_12:50 مانده: 1',
          reference: received)!;
      final local = t.add(kIranOffset);
      expect(gregorianToJalali(local.year, local.month, local.day), [1405, 5, 27]);
      expect([local.hour, local.minute], [12, 50]);
    });

    test('تاریخِ بعد از زمانِ رسیدن → سالِ قبل (پیامکِ اسفند در فروردین)', () {
      final t = extractOccurredAt('-500,000 12/29_23:10', reference: received)!;
      final local = t.add(kIranOffset);
      expect(gregorianToJalali(local.year, local.month, local.day), [1404, 12, 29]);
    });
  });
}
