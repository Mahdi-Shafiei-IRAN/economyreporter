/// تبدیل تاریخ شمسی (جلالی) به میلادی و استخراج تاریخِ رخداد از متن پیامک.
///
/// پیامک‌های بانکی ایران تاریخ را به‌صورت شمسی (مثلاً 1405/06/19) و ساعت محلی
/// می‌نویسند. اینجا به لحظه‌ی UTC تبدیل می‌شود (ایران UTC+3:30، بدون DST).
library;

/// اختلاف ساعت ایران با UTC (بدون ساعت تابستانی از ۱۴۰۱).
const Duration kIranOffset = Duration(hours: 3, minutes: 30);

/// الگوریتم استاندارد تبدیل میلادی → جلالی. خروجی [jy, jm, jd].
List<int> gregorianToJalali(int gy, int gm, int gd) {
  const gdm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
  final gy2 = gm > 2 ? gy + 1 : gy;
  var days = 355666 +
      (365 * gy) +
      ((gy2 + 3) ~/ 4) -
      ((gy2 + 99) ~/ 100) +
      ((gy2 + 399) ~/ 400) +
      gd +
      gdm[gm - 1];
  var jy = -1595 + (33 * (days ~/ 12053));
  days %= 12053;
  jy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    jy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  final jm = days < 186 ? 1 + (days ~/ 31) : 7 + ((days - 186) ~/ 30);
  final jd = 1 + (days < 186 ? days % 31 : (days - 186) % 30);
  return [jy, jm, jd];
}

/// یک روز در تقویم شمسی.
class JalaliDate {
  final int year;
  final int month;
  final int day;

  const JalaliDate(this.year, this.month, this.day);

  /// روزِ شمسیِ یک لحظه، به وقت ایران.
  factory JalaliDate.fromDateTime(DateTime t) {
    final local = t.toUtc().add(kIranOffset);
    final j = gregorianToJalali(local.year, local.month, local.day);
    return JalaliDate(j[0], j[1], j[2]);
  }

  /// آغاز این روز (۰۰:۰۰ به وقت ایران) به UTC.
  DateTime toUtcStart() {
    final g = jalaliToGregorian(year, month, day);
    return DateTime.utc(g[0], g[1], g[2]).subtract(kIranOffset);
  }

  /// روز هفته طبق DateTime (۱=دوشنبه … ۷=یکشنبه).
  int get weekday {
    final g = jalaliToGregorian(year, month, day);
    return DateTime.utc(g[0], g[1], g[2]).weekday;
  }

  @override
  bool operator ==(Object other) =>
      other is JalaliDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '$year/$month/$day';
}

/// تعداد روزهای یک ماه شمسی (اسفندِ سال کبیسه ۳۰ روز).
int jalaliMonthLength(int jy, int jm) {
  if (jm <= 6) return 31;
  if (jm <= 11) return 30;
  final start = JalaliDate(jy, 12, 1).toUtcStart();
  final next = JalaliDate(jy + 1, 1, 1).toUtcStart();
  return next.difference(start).inDays;
}

/// الگوریتم استاندارد تبدیل جلالی → میلادی. خروجی [gy, gm, gd].
List<int> jalaliToGregorian(int jy, int jm, int jd) {
  jy += 1595;
  var days = -355668 +
      (365 * jy) +
      ((jy ~/ 33) * 8) +
      (((jy % 33) + 3) ~/ 4) +
      jd +
      ((jm < 7) ? (jm - 1) * 31 : ((jm - 7) * 30) + 186);
  var gy = 400 * (days ~/ 146097);
  days %= 146097;
  if (days > 36524) {
    gy += 100 * ((--days) ~/ 36524);
    days %= 36524;
    if (days >= 365) days++;
  }
  gy += 4 * (days ~/ 1461);
  days %= 1461;
  if (days > 365) {
    gy += (days - 1) ~/ 365;
    days = (days - 1) % 365;
  }
  var gd = days + 1;
  final isLeap = (gy % 4 == 0 && gy % 100 != 0) || (gy % 400 == 0);
  final salA = [0, 31, isLeap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var gm = 0;
  for (gm = 0; gm < 13 && gd > salA[gm]; gm++) {
    gd -= salA[gm];
  }
  return [gy, gm, gd];
}

final _dateRe = RegExp(r'(\d{2,4})/(\d{1,2})/(\d{1,2})');
final _timeRe = RegExp(r'(\d{1,2}):(\d{2})');

/// تاریخِ رخداد را از متنِ نرمال‌شده استخراج و به UTC برمی‌گرداند (اگر پیدا نشد null).
DateTime? extractOccurredAt(String normalized) {
  final dm = _dateRe.firstMatch(normalized);
  if (dm == null) return null;

  var jy = int.parse(dm.group(1)!);
  final jm = int.parse(dm.group(2)!);
  final jd = int.parse(dm.group(3)!);
  if (jy < 100) jy += 1400; // سالِ دورقمی → 14xx
  if (jy < 1300 || jy > 1500 || jm < 1 || jm > 12 || jd < 1 || jd > 31) {
    return null;
  }

  final g = jalaliToGregorian(jy, jm, jd);

  var hh = 0;
  var mi = 0;
  final tm = _timeRe.firstMatch(normalized);
  if (tm != null) {
    final h = int.parse(tm.group(1)!);
    final m = int.parse(tm.group(2)!);
    if (h <= 23 && m <= 59) {
      hh = h;
      mi = m;
    }
  }

  // زمانِ محلی ایران را می‌سازیم و به UTC تبدیل می‌کنیم (UTC+3:30).
  final iranWallClock = DateTime.utc(g[0], g[1], g[2], hh, mi);
  return iranWallClock.subtract(const Duration(hours: 3, minutes: 30));
}
