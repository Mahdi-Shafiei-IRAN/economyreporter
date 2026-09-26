import 'package:economy/core/format/date_format.dart';
import 'package:economy/core/sms/jalali.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('تبدیل میلادی ↔ شمسی', () {
    test('تاریخ‌های شناخته‌شده', () {
      expect(gregorianToJalali(2026, 9, 11), [1405, 6, 20]);
      expect(gregorianToJalali(2026, 3, 21), [1405, 1, 1]);
      expect(gregorianToJalali(2026, 9, 23), [1405, 7, 1]);
      expect(gregorianToJalali(2025, 3, 20), [1403, 12, 30]); // اسفند کبیسه
    });

    test('رفت‌وبرگشت برای ۱۰۰۰ روز پیاپی', () {
      var day = DateTime.utc(2024, 1, 1);
      for (var i = 0; i < 1000; i++) {
        final j = gregorianToJalali(day.year, day.month, day.day);
        expect(jalaliToGregorian(j[0], j[1], j[2]), [day.year, day.month, day.day]);
        day = day.add(const Duration(days: 1));
      }
    });

    test('طول ماه‌ها', () {
      expect(jalaliMonthLength(1405, 6), 31);
      expect(jalaliMonthLength(1405, 7), 30);
      expect(jalaliMonthLength(1403, 12), 30);
      expect(jalaliMonthLength(1404, 12), 29);
    });

    test('روز شمسی به وقت ایران حساب می‌شود، نه UTC', () {
      // ۲۳:۵۹ شب ۳۱ شهریور به وقت ایران
      expect(JalaliDate.fromDateTime(DateTime.utc(2026, 9, 22, 20, 29)),
          const JalaliDate(1405, 6, 31));
      // ۰۰:۰۰ اول مهر به وقت ایران
      expect(JalaliDate.fromDateTime(DateTime.utc(2026, 9, 22, 20, 30)),
          const JalaliDate(1405, 7, 1));
    });
  });

  group('قالب‌بندی', () {
    test('تاریخ و ساعت', () {
      final t = DateTime.utc(2026, 9, 11, 11, 0); // ۱۴:۳۰ تهران
      expect(formatJalaliDate(t), '۲۰ شهریور ۱۴۰۵');
      expect(formatJalaliNumeric(t), '۱۴۰۵/۰۶/۲۰');
      expect(formatClock(t), '۱۴:۳۰');
      expect(formatJalaliDateTime(t), '۲۰ شهریور ۱۴۰۵، ساعت ۱۴:۳۰');
      expect(formatDayHeader(t), 'جمعه ۲۰ شهریور ۱۴۰۵');
      expect(formatShortDateTime(t), '۲۰ شهریور، ۱۴:۳۰');
    });
  });

}
