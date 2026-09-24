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

/// نویسه‌های نامرئی که بعضی بانک‌ها وسطِ متن می‌گذارند: «حساب\u200F123…» روی صفحه همان
/// «حساب123…» است ولی Regex را خراب می‌کند. همه‌ی نویسه‌های قالب (Cf: RLM، LRM، WJ،
/// نیم‌خط نرم، …)، نشانه‌های روی حرف (Mn: اعراب، variation selector) و کشیده‌ی «ـ».
/// نیم‌فاصله (ZWNJ) نه: جزو نوشتار است و [normalizeForParsing] فاصله‌اش می‌کند.
final _invisible = RegExp(r'(?!\u200C)[\p{Cf}\p{Mn}\u0640\u180E]', unicode: true);

/// حذفِ نویسه‌های نامرئی. عمداً در [normalizeForParsing] نیست، چون اثرانگشتِ پیامک
/// (ضدتکرار) از آن ساخته می‌شود و تغییرش پیامک‌های ثبت‌شده را دوباره ثبت می‌کرد.
String stripInvisible(String input) => input.replaceAll(_invisible, '');

/// نویسه‌های نامرئیِ یک متن به‌صورت «U+200F×2، U+2060×1» (برای گزارش عیب‌یابی؛
/// روی صفحه دیده نمی‌شوند). خالی یعنی متن تمیز است.
String describeInvisible(String input) {
  final counts = <int, int>{};
  for (final m in _invisible.allMatches(input)) {
    final rune = m[0]!.runes.first;
    counts[rune] = (counts[rune] ?? 0) + 1;
  }
  if (input.contains('ى')) counts[0x0649] = 'ى'.allMatches(input).length;
  return [
    for (final e in counts.entries)
      'U+${e.key.toRadixString(16).toUpperCase().padLeft(4, '0')}×${e.value}',
  ].join('، ');
}

/// جداکننده‌ی هزارگانِ غیرِ کاما: «86،184»، «86’184» و «1.500.000» (نه حسابِ نقطه‌دارِ
/// پاسارگاد «777.888.10000001.1»، نه تاریخِ «1405.07.01»: همه‌ی گروه‌ها باید ۳ رقمی باشند).
final _altThousands = RegExp(
    r"(?<![0-9.,،’'])[0-9]{1,3}(?:[،’'][0-9]{3})+(?![0-9])"
    r'|(?<![0-9.,])[0-9]{1,3}(?:\.[0-9]{3})+(?![0-9]|[.,][0-9])');
final _altSeparator = RegExp(r"[،’'.]");

/// متنِ آماده‌ی پارس (فقط پارس، نه اثرانگشت): نویسه‌های نامرئی حذف، «ى» عربی → «ی»،
/// [normalizeForParsing]، و جداکننده‌ی هزارگانِ دیگر → کاما.
String cleanForParsing(String body) {
  final s = normalizeForParsing(stripInvisible(body).replaceAll('ى', 'ی'));
  return s.replaceAllMapped(_altThousands, (m) => m[0]!.replaceAll(_altSeparator, ','));
}

/// نسخه‌ی فشرده (بدون هیچ فاصله‌ای) برای تطبیق کلیدواژه‌ها،
/// چون فاصله‌گذاری بین کلمات در پیامک بانک‌ها ثابت نیست.
String compact(String normalized) => normalized.replaceAll(' ', '');

/// رشته‌ی عددی (احتمالاً کاماخورده) را به عدد صحیح تبدیل می‌کند.
int? parseIntSafe(String? raw) {
  if (raw == null) return null;
  return int.tryParse(raw.replaceAll(',', '').replaceAll('.', ''));
}
