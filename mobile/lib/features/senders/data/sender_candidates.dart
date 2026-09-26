/// پیشنهاد فرستنده‌های بانک: فرستنده‌هایی که در صندوقِ گوشی پیامکِ مبلغ‌دار داده‌اند ولی هنوز
/// مجاز نیستند (منطق خالص و تست‌پذیر).
library;

import '../../../core/sms/bank_registry.dart';
import '../../../core/sms/raw_sms.dart';
import '../../../core/sms/sms_parser.dart';
import 'allowed_sender.dart';

class SenderCandidate {
  /// فرستنده همان‌طور که در پیامک آمده.
  final String address;

  /// بانکِ حدسی (از نام فرستنده، وگرنه از متن).
  final String? bankId;

  /// پیامک‌های تراکنش‌مانندِ صندوق گوشی از این فرستنده.
  final int inboxCount;

  /// جدیدترین متن پیامک (تا معلوم شود بانک است یا تبلیغ/فروشگاه).
  final String? sample;
  final DateTime? lastAt;

  const SenderCandidate({
    required this.address,
    required this.inboxCount,
    this.bankId,
    this.sample,
    this.lastAt,
  });

  int get weight => inboxCount;
}

class _Group {
  final String address;
  String? bankId;
  int inboxCount = 0;
  String? sample;
  DateTime? lastAt;

  _Group(this.address);

  void offer(String body, DateTime? at) {
    if (sample != null && (at == null || (lastAt != null && !at.isAfter(lastAt!)))) return;
    sample = body;
    lastAt = at;
  }
}

List<SenderCandidate> findSenderCandidates({
  required Iterable<RawSms> inbox,
  required Iterable<AllowedSender> allowed,
  Iterable<String> dismissed = const [],
  SmsParser parser = const SmsParser(),
}) {
  bool isDismissed(String address) =>
      dismissed.any((d) => sameSender(d, address));
  final groups = <_Group>[];
  _Group groupFor(String address) {
    for (final g in groups) {
      if (sameSender(g.address, address)) return g;
    }
    final g = _Group(address.trim());
    groups.add(g);
    return g;
  }

  for (final sms in inbox) {
    if (sms.sender.trim().isEmpty ||
        isDismissed(sms.sender) ||
        findAllowedSender(allowed, sms.sender) != null) {
      continue;
    }
    final parsed =
        parser.parse(sender: sms.sender, body: sms.body, receivedAt: sms.receivedAt);
    if (!parsed.looksLikeTransaction) continue;
    final g = groupFor(sms.sender)
      ..inboxCount += 1
      ..bankId ??= parsed.bankId;
    g.offer(sms.body, sms.receivedAt);
  }

  return [
    for (final g in groups)
      SenderCandidate(
        address: g.address,
        bankId: detectBank(g.address)?.id ?? g.bankId,
        inboxCount: g.inboxCount,
        sample: g.sample,
        lastAt: g.lastAt,
      ),
  ]..sort((a, b) {
      final c = b.weight.compareTo(a.weight);
      if (c != 0) return c;
      return (b.lastAt ?? DateTime(0)).compareTo(a.lastAt ?? DateTime(0));
    });
}
