/// نمایش تاریخ/ساعت به شمسی و به وقت ایران (مستقل از منطقه‌ی زمانی گوشی).
library;

import '../sms/jalali.dart';
import 'money_format.dart';

const List<String> kJalaliMonthNames = [
  'فروردین',
  'اردیبهشت',
  'خرداد',
  'تیر',
  'مرداد',
  'شهریور',
  'مهر',
  'آبان',
  'آذر',
  'دی',
  'بهمن',
  'اسفند',
];

/// نام روز هفته؛ اندیس = DateTime.weekday (۱=دوشنبه … ۷=یکشنبه).
const List<String> _weekdayNames = [
  '',
  'دوشنبه',
  'سه‌شنبه',
  'چهارشنبه',
  'پنجشنبه',
  'جمعه',
  'شنبه',
  'یکشنبه',
];

String _two(int v) => v.toString().padLeft(2, '0');

String jalaliMonthName(int month) => kJalaliMonthNames[month - 1];

/// «۲۰ شهریور ۱۴۰۵»
String formatJalaliDate(DateTime t) => formatJalali(JalaliDate.fromDateTime(t));

/// «۲۰ شهریور ۱۴۰۵» از یک روز شمسی.
String formatJalali(JalaliDate d) =>
    toPersianDigits('${d.day} ${jalaliMonthName(d.month)} ${d.year}');

/// «۱۴۰۵/۰۶/۲۰»
String formatJalaliNumeric(DateTime t) {
  final d = JalaliDate.fromDateTime(t);
  return toPersianDigits('${d.year}/${_two(d.month)}/${_two(d.day)}');
}

/// «۱۴:۳۰» به وقت ایران.
String formatClock(DateTime t) {
  final local = t.toUtc().add(kIranOffset);
  return toPersianDigits('${_two(local.hour)}:${_two(local.minute)}');
}

/// «۲۰ شهریور ۱۴۰۵، ساعت ۱۴:۳۰»
String formatJalaliDateTime(DateTime t) =>
    '${formatJalaliDate(t)}، ساعت ${formatClock(t)}';

/// سرتیتر روز در فهرست: «پنجشنبه ۲۰ شهریور ۱۴۰۵».
String formatDayHeader(DateTime t) {
  final d = JalaliDate.fromDateTime(t);
  return '${_weekdayNames[d.weekday]} ${formatJalali(d)}';
}

/// کوتاه برای ردیف تراکنش: «۲۰ شهریور، ۱۴:۳۰».
String formatShortDateTime(DateTime t) {
  final d = JalaliDate.fromDateTime(t);
  return '${toPersianDigits('${d.day} ${jalaliMonthName(d.month)}')}، ${formatClock(t)}';
}
