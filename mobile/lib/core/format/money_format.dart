/// قالب‌بندی پول برای نمایش.
///
/// قانون پروژه: مبلغ کانونی به ریال ذخیره می‌شود و تبدیل به **تومان** فقط
/// در لایه‌ی نمایش انجام می‌شود (docs/architecture.md §۱۲).
library;

const List<String> _persianDigits = [
  '۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹',
];

/// ارقام لاتین یک رشته را به فارسی تبدیل می‌کند.
String toPersianDigits(String input) {
  return input.replaceAllMapped(
    RegExp(r'[0-9]'),
    (m) => _persianDigits[int.parse(m[0]!)],
  );
}

/// عدد را با جداکننده‌ی هزارگان (٬) گروه‌بندی می‌کند (ارقام لاتین).
String groupThousands(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (digits.length - i) % 3 == 0) buffer.write('٬');
    buffer.write(digits[i]);
  }
  return (value < 0 ? '-' : '') + buffer.toString();
}

/// مبلغ ریالی را به‌صورت «... تومان» نمایش می‌دهد (تقسیم بر ۱۰).
String formatToman(int rial, {bool persianDigits = true, bool withUnit = true}) {
  final toman = rial ~/ 10;
  var text = groupThousands(toman);
  if (persianDigits) text = toPersianDigits(text);
  return withUnit ? '$text تومان' : text;
}
