import 'package:economy/core/format/money_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('groupThousands', () {
    test('گروه‌بندی هزارگان', () {
      expect(groupThousands(1234567), '1٬234٬567');
      expect(groupThousands(0), '0');
      expect(groupThousands(999), '999');
    });
    test('عدد منفی', () {
      expect(groupThousands(-2000000), '-2٬000٬000');
    });
  });

  group('formatToman', () {
    test('تبدیل ریال به تومان + جداکننده (ارقام لاتین)', () {
      expect(formatToman(25000000, persianDigits: false), '2٬500٬000 تومان');
    });
    test('ارقام فارسی به‌صورت پیش‌فرض', () {
      expect(formatToman(25000000), '۲٬۵۰۰٬۰۰۰ تومان');
    });
    test('بدون واحد', () {
      expect(formatToman(10000000, persianDigits: false, withUnit: false), '1٬000٬000');
    });
    test('مانده‌ی منفی', () {
      expect(formatToman(-20000000, persianDigits: false), '-2٬000٬000 تومان');
    });
  });
}
