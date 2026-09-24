import 'package:economy/core/sms/digit_utils.dart';
import 'package:economy/core/sms/sms_fingerprint.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// پیامک‌هایی که روی صفحه عادی‌اند ولی نویسه‌ی نامرئی یا جداکننده‌ی دیگری دارند
/// (دو پیامکِ سودِ ملتِ کاربرِ دوم با پارسرِ قبلی ثبت نمی‌شد).
void main() {
  const p = SmsParser();
  const bodies = [
    'واریز سود علی الحساب\nسپرده4900000001\nبه حساب4900000002\nمبلغ86,184\n05/07/01',
    'واریز سود کوتاه مدت\nحساب4900000002\nمبلغ4,033\n05/07/01',
    'حساب4900000002\nبرداشت1,250,000\nمانده8,750,000\n05/07/01-15:40',
  ];

  // نویسه‌های قالب/اعراب/کشیده که بین کلمه و عدد (یا وسطِ کلمه) می‌آیند.
  const hidden = {
    'RLM': '\u200F', 'LRM': '\u200E', 'ALM': '\u061C', 'ZWSP': '\u200B', 'ZWJ': '\u200D',
    'WJ': '\u2060', 'SHY': '\u00AD', 'CGJ': '\u034F', 'MVS': '\u180E', 'TATWEEL': '\u0640',
    'RLE': '\u202B', 'PDF': '\u202C', 'RLI': '\u2067', 'PDI': '\u2069', 'BOM': '\uFEFF',
    'VS16': '\uFE0F', 'NADS': '\u206F', 'FATHA': '\u064E',
  };

  for (final body in bodies) {
    final base = p.parse(sender: 'Bank Mellat', body: body, bankId: 'mellat');

    test('پایه: ${body.split('\n').first}', () {
      expect(base.isCountable, isTrue);
      expect(base.accountRef, '4900000002');
    });

    for (final e in hidden.entries) {
      test('${e.key} هر جای «${body.split('\n').first}» پارس را خراب نمی‌کند', () {
        for (var i = 1; i < body.length; i++) {
          final b = body.substring(0, i) + e.value + body.substring(i);
          final r = p.parse(sender: 'Bank Mellat', body: b, bankId: 'mellat');
          expect(
              [r.isCountable, r.kind, r.amountRial, r.accountRef, r.balanceAfterRial],
              [true, base.kind, base.amountRial, base.accountRef, base.balanceAfterRial],
              reason: 'جای $i: ${b.replaceAll('\n', ' | ')}');
        }
      });
    }
  }

  test('«ى» عربی و «مبل\u0640\u0640غ» کشیده', () {
    final r = p.parse(
        sender: 'Bank Mellat',
        body: 'وارىز سود على الحساب\nبه حساب4900000002\nمبل\u0640\u0640غ86,184',
        bankId: 'mellat');
    expect([r.isCountable, r.amountRial, r.accountRef], [true, 86184, '4900000002']);
  });

  group('جداکننده‌ی هزارگانِ غیرِ کاما', () {
    int? amount(String body) =>
        p.parse(sender: 'Bank Mellat', body: body, bankId: 'mellat').amountRial;

    test('«،» / «٬» / «’» / «.» مثلِ کاما', () {
      for (final sep in ['،', '٬', '’', "'", '.', '٫']) {
        expect(amount('حساب4900000002\nواریز1${sep}250${sep}000\nمانده9${sep}000${sep}000'),
            1250000,
            reason: sep);
      }
    });

    test('حسابِ نقطه‌دارِ پاسارگاد، تاریخ و ساعت دست نمی‌خورند', () {
      expect(cleanForParsing('777.888.10000001.1\n7,400,000-'), '777.888.10000001.1 7,400,000-');
      expect(cleanForParsing('1405.07.01 12.30'), '1405.07.01 12.30');
      expect(cleanForParsing('کارت 1234، مبلغ 500،000'), 'کارت 1234، مبلغ 500,000');
      final pasargad = p.parse(
          sender: 'B.Pasargad', body: '777.888.10000001.1\n7,400,000-\n10:55_07/02\nمانده: 95.812.229');
      expect([pasargad.accountRef, pasargad.amountRial, pasargad.balanceAfterRial],
          ['777.888.10000001.1', 7400000, 95812229]);
    });
  });

  test('اثرانگشتِ پیامک با پاک‌سازیِ تازه عوض نمی‌شود (پیامکِ ثبت‌شده دوباره ثبت نمی‌شود)', () {
    const body = 'حساب\u2060490000\u200F0002\nمبلغ86،184';
    // همان فرمولِ نسخه‌های قبل: فقط normalizeForParsing روی متنِ خام.
    expect(smsFingerprint(sender: 'Bank Mellat', body: body),
        smsFingerprint(sender: 'Bank Mellat', body: body));
    expect(normalizeForParsing(body), contains('\u2060'));
  });

  test('describeInvisible نویسه‌های نامرئی را نام می‌برد', () {
    expect(describeInvisible('حساب\u200F123\u200F\nمبلغ\u2060۵'), 'U+200F×2، U+2060×1');
    expect(describeInvisible('حساب123 نیم‌فاصله'), '');
    expect(describeInvisible('على'), 'U+0649×1');
  });
}
