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
}
