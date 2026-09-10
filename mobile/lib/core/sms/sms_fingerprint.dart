/// اثرانگشت پیامک برای جلوگیری از دوباره‌پارس‌شدن یک پیامک.
///
/// این کلید یکتای مطلق نیست؛ فقط یک سیگنال ضدتکرار است (بازه‌ی زمانی گرد می‌شود
/// تا رسیدن با چند ثانیه اختلاف باعث تکرار نشود). ترتیب اولویت ضدتکرار در کل
/// سیستم: ۱) UUID تراکنش ۲) اثرانگشت پیامک ۳) heuristic سمت سرور.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'digit_utils.dart';

/// بازه‌ی گردکردن زمان دریافت (۵ دقیقه).
const int _bucketMs = 5 * 60 * 1000;

String smsFingerprint({
  required String sender,
  required String body,
  DateTime? receivedAt,
}) {
  final bucket =
      receivedAt == null ? '' : (receivedAt.toUtc().millisecondsSinceEpoch ~/ _bucketMs).toString();
  final normalized = normalizeForParsing(body);
  final input = '$sender|$normalized|$bucket';
  return sha256.convert(utf8.encode(input)).toString();
}
