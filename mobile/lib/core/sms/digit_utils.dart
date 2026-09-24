/// ابزار نرمال‌سازی متن پیامک فارسی/عربی.
///
/// قبل از هر Regex، ارقام فارسی/عربی به لاتین و حروف/جداکننده‌ها یکدست می‌شوند.
library;

/// ارقام فارسی (۰-۹) و عربی (٠-٩) را به لاتین (0-9) تبدیل می‌کند.
String normalizeDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      // Persian ۰..۹
      buffer.writeCharCode(0x30 + (rune - 0x06F0));
    } else if (rune >= 0x0660 && rune <= 0x0669) {
      // Arabic-Indic ٠..٩
      buffer.writeCharCode(0x30 + (rune - 0x0660));
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// نرمال‌سازی کامل برای پارس: ارقام لاتین، حروف عربی→فارسی،
/// حذف جداکننده‌ی هزارگان عربی، یکدست‌کردن فاصله‌ها.
/// کاما (,) عمداً نگه داشته می‌شود تا مبلغ‌های کاماخورده هم Regex شوند
/// و بعداً موقع تبدیل به عدد حذف شوند.
String normalizeForParsing(String input) {
  var s = normalizeDigits(input);
  s = s.replaceAll('‌', ' '); // ZWNJ (نیم‌فاصله) → فاصله
  s = s.replaceAll('٬', ''); // جداکننده‌ی هزارگان عربی ٬ → حذف
  s = s.replaceAll('٫', '.'); // ممیز عربی ٫ → نقطه
  s = s.replaceAll('ك', 'ک'); // ك عربی → ک فارسی
  s = s.replaceAll('ي', 'ی'); // ي عربی → ی فارسی
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

/// نویسه‌های نامرئیِ جهت‌دهی/قالب (RLM، LRM، …) که بعضی بانک‌ها وسطِ متن می‌گذارند:
/// «حساب\u200F123…» روی صفحه همان «حساب123…» است ولی Regex را خراب می‌کند.
final _invisible = RegExp('[\u200B\u200D-\u200F\u202A-\u202E\u2066-\u2069\uFEFF\u061C]');

/// حذفِ نویسه‌های نامرئی. عمداً در [normalizeForParsing] نیست، چون اثرانگشتِ پیامک
/// (ضدتکرار) از آن ساخته می‌شود و تغییرش پیامک‌های ثبت‌شده را دوباره ثبت می‌کرد.
String stripInvisible(String input) => input.replaceAll(_invisible, '');

/// نسخه‌ی فشرده (بدون هیچ فاصله‌ای) برای تطبیق کلیدواژه‌ها،
/// چون فاصله‌گذاری بین کلمات در پیامک بانک‌ها ثابت نیست.
String compact(String normalized) => normalized.replaceAll(' ', '');

/// رشته‌ی عددی (احتمالاً کاماخورده) را به عدد صحیح تبدیل می‌کند.
int? parseIntSafe(String? raw) {
  if (raw == null) return null;
  return int.tryParse(raw.replaceAll(',', '').replaceAll('.', ''));
}
