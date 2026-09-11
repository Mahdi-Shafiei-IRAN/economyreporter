/// بازه‌ی نمایش تراکنش‌ها: یک ماه شمسی یا «همه‌ی زمان‌ها».
library;

import '../../../core/format/date_format.dart';
import '../../../core/format/money_format.dart';
import '../../../core/sms/jalali.dart';

class Period {
  final int? year;
  final int? month;

  const Period.month(int this.year, int this.month);
  const Period.all()
      : year = null,
        month = null;

  /// ماهِ شمسیِ شاملِ یک لحظه (به وقت ایران).
  factory Period.containing(DateTime t) {
    final d = JalaliDate.fromDateTime(t);
    return Period.month(d.year, d.month);
  }

  bool get isAll => year == null;

  /// آغاز بازه (UTC)؛ null یعنی بدون محدودیت.
  DateTime? get from => isAll ? null : JalaliDate(year!, month!, 1).toUtcStart();

  /// پایان بازه (UTC، انحصاری)؛ null یعنی بدون محدودیت.
  DateTime? get to => isAll ? null : next.from;

  Period get next =>
      isAll ? this : (month == 12 ? Period.month(year! + 1, 1) : Period.month(year!, month! + 1));

  Period get previous =>
      isAll ? this : (month == 1 ? Period.month(year! - 1, 12) : Period.month(year!, month! - 1));

  bool contains(DateTime t) {
    if (isAll) return true;
    final u = t.toUtc();
    return !u.isBefore(from!) && u.isBefore(to!);
  }

  /// «شهریور ۱۴۰۵» یا «همه‌ی زمان‌ها».
  String get title =>
      isAll ? 'همه‌ی زمان‌ها' : toPersianDigits('${jalaliMonthName(month!)} $year');

  /// «از ۱ شهریور ۱۴۰۵ تا ۳۱ شهریور ۱۴۰۵» — تا معلوم باشد جمع‌ها مال کدام بازه است.
  String get rangeLabel {
    if (isAll) return 'همه‌ی تراکنش‌های ثبت‌شده، از اول تا امروز';
    final last = jalaliMonthLength(year!, month!);
    return 'از ${formatJalali(JalaliDate(year!, month!, 1))} '
        'تا ${formatJalali(JalaliDate(year!, month!, last))}';
  }

  @override
  bool operator ==(Object other) =>
      other is Period && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}
