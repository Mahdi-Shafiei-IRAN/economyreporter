/// فرستنده‌ی مجاز پیامک بانکی: فقط پیامک سرشماره‌ها/نام‌هایی که خود کاربر تعیین
/// کرده خودکار ثبت می‌شود؛ بقیه (تبلیغ، فروشگاه، …) حتی اگر مبلغ داشته باشند نه.
library;

import '../../../core/sms/digit_utils.dart';

class AllowedSender {
  final String id;

  /// همان‌طور که در پیامک دیده/وارد شده (مثلاً «BankMellat» یا «+98200012345»).
  final String address;

  /// بانکِ این فرستنده؛ قدم اول پارس (تشخیص بانک از فرستنده) از همین است.
  final String? bankId;

  const AllowedSender({required this.id, required this.address, this.bankId});

  bool matches(String sender) => sameSender(address, sender);

  Map<String, Object?> toMap() => {'id': id, 'address': address, 'bank_id': bankId};

  factory AllowedSender.fromMap(Map<String, Object?> m) => AllowedSender(
        id: m['id'] as String,
        address: m['address'] as String,
        bankId: m['bank_id'] as String?,
      );
}

final _separators = RegExp(r'[\s\-()]');
final _number = RegExp(r'^\+?\d+$');
final _digits = RegExp(r'^\d+$');

/// شکل قابل‌مقایسه‌ی فرستنده: ارقام لاتین، بدون فاصله/خط‌تیره/پرانتز، حروف کوچک؛
/// برای شماره‌ها «+» و صفرهای اول هم حذف می‌شود.
String canonicalSender(String raw) {
  var s = normalizeForParsing(raw).toLowerCase().replaceAll(_separators, '');
  if (_number.hasMatch(s)) {
    s = s.replaceFirst('+', '').replaceFirst(RegExp(r'^0+'), '');
  }
  return s;
}

/// آیا دو فرستنده یکی‌اند؟ برای شماره‌ها «+98…»، «0…» و بدون پیش‌شماره برابرند؛
/// برای نام‌ها فاصله و حروف بزرگ/کوچک مهم نیست.
bool sameSender(String a, String b) {
  final x = canonicalSender(a);
  final y = canonicalSender(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  return _digits.hasMatch(x) && _digits.hasMatch(y) && (x == '98$y' || y == '98$x');
}

/// فرستنده‌ی مجازِ منطبق با [sender]؛ null یعنی پیامکش نباید ثبت شود.
AllowedSender? findAllowedSender(Iterable<AllowedSender> allowed, String sender) {
  for (final s in allowed) {
    if (s.matches(sender)) return s;
  }
  return null;
}
