/// ورودِ پیامک به دفتر (docs/v2-design.md ۵.۱ و ۵.۲): فقط یک `SmsItem` می‌سازد، هرگز تراکنش (ت۲).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../features/senders/data/allowed_sender.dart';
import '../sms/digit_utils.dart';
import '../sms/jalali.dart';
import '../sms/sms_parser.dart';
import 'models.dart';
import 'suggestion.dart';

/// زمانِ دریافتِ زنده و ستونِ `date` صندوق چند ثانیه تا چند دقیقه فرق دارند.
const kSameSmsWindow = Duration(minutes: 10);

final _withCountryCode = RegExp(r'^98[0-9]{7,}$');

/// شکلِ پایدارِ فرستنده برای کلید: «+98…»، «0…» و بی‌پیش‌شماره یکی‌اند.
String ledgerSenderKey(String raw) {
  final s = canonicalSender(raw);
  return _withCountryCode.hasMatch(s) ? s.substring(2) : s;
}

/// عمداً با [normalizeForParsing] و نه `cleanForParsing`: کلید با بهترشدنِ پارسر عوض نمی‌شود.
String smsContentHash({required String sender, required String body}) => sha256
    .convert(utf8.encode('${ledgerSenderKey(sender)}|${normalizeForParsing(body)}'))
    .toString();

String smsItemKey(String contentHash, DateTime receivedAt) =>
    '$contentHash:${receivedAt.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute}';

bool isSameSms(String hashA, DateTime atA, String hashB, DateTime atB) =>
    hashA == hashB && atA.difference(atB).abs() <= kSameSmsWindow;

/// تاریخِ شروع (ت۱): اولِ ماهِ شمسیِ جاری، ساعتِ ۰۰:۰۰ تهران، به UTC.
DateTime ledgerStartFor(DateTime now) {
  final j = JalaliDate.fromDateTime(now);
  return JalaliDate(j.year, j.month, 1).toUtcStart();
}

class IncomingSms {
  final String sender;
  final String body;
  final DateTime receivedAt;
  const IncomingSms({required this.sender, required this.body, required this.receivedAt});
}

sealed class IntakeResult {
  const IntakeResult();
}

class IntakeIgnored extends IntakeResult {
  static const notAllowed = 'not_allowed';
  static const beforeStart = 'before_start';

  final String reason;
  const IntakeIgnored(this.reason);
}

/// همین پیامک قبلاً هست؛ تصمیمش دست‌نخورده. [bodyFilled]: متنش خالی بود و پر شد.
class IntakeKnown extends IntakeResult {
  final SmsItem item;
  final bool bodyFilled;
  const IntakeKnown(this.item, {this.bodyFilled = false});
}

class IntakeNew extends IntakeResult {
  final SmsItem item;
  const IntakeNew(this.item);
}

IntakeResult intakeSms(
  IncomingSms sms, {
  required DateTime startDate,
  required Iterable<AllowedSender> allowed,
  required Iterable<SmsItem> existing,
  Iterable<SmsDecision> serverDecisions = const [],
  required SuggestionContext ctx,
  SmsParser parser = const SmsParser(),
}) {
  final sender = findAllowedSender(allowed, sms.sender);
  if (sender == null) return const IntakeIgnored(IntakeIgnored.notAllowed);
  if (sms.receivedAt.isBefore(startDate)) return const IntakeIgnored(IntakeIgnored.beforeStart);

  final hash = smsContentHash(sender: sms.sender, body: sms.body);
  var resent = false;
  for (final e in existing) {
    if (e.contentHash != hash) continue;
    if (isSameSms(hash, sms.receivedAt, e.contentHash, e.receivedAt)) {
      return e.body == null ? IntakeKnown(e.withBody(sms.body), bodyFilled: true) : IntakeKnown(e);
    }
    if (e.receivedAt.isBefore(sms.receivedAt)) resent = true;
  }

  final parsed = parser.parse(
      sender: sms.sender, body: sms.body, bankId: sender.bankId, receivedAt: sms.receivedAt);
  final suggestion = suggest(parsed, receivedAt: sms.receivedAt, ctx: ctx, resent: resent);

  SmsDecision? decision;
  for (final d in serverDecisions) {
    if (isSameSms(hash, sms.receivedAt, d.contentHash, d.receivedAt)) {
      decision = d;
      break;
    }
  }
  return IntakeNew(SmsItem(
    key: decision?.key ?? smsItemKey(hash, sms.receivedAt),
    contentHash: hash,
    sender: sms.sender,
    receivedAt: sms.receivedAt,
    body: sms.body,
    suggestion: suggestion,
    status: decision?.status ?? SmsStatus.pending,
    entryId: decision?.entryId,
    rejectReason: decision?.rejectReason,
    decidedAt: decision?.decidedAt,
    parserVersion: kParserVersion,
  ));
}

/// پیشنهادِ تازه برای پیامکِ **منتظر** با پارسرِ جدیدتر؛ تصمیم‌دارها هرگز (I2). null = کاری نیست.
SmsItem? resuggest(
  SmsItem item, {
  required Iterable<AllowedSender> allowed,
  required Iterable<SmsItem> others,
  required SuggestionContext ctx,
  SmsParser parser = const SmsParser(),
  int parserVersion = kParserVersion,
}) {
  final body = item.body;
  if (item.status != SmsStatus.pending || body == null || item.parserVersion >= parserVersion) {
    return null;
  }
  final sender = findAllowedSender(allowed, item.sender);
  final parsed = parser.parse(
      sender: item.sender, body: body, bankId: sender?.bankId, receivedAt: item.receivedAt);
  final resent = others.any((o) =>
      o.key != item.key && o.contentHash == item.contentHash && o.receivedAt.isBefore(item.receivedAt));
  return item.withSuggestion(
      suggest(parsed, receivedAt: item.receivedAt, ctx: ctx, resent: resent), parserVersion);
}
