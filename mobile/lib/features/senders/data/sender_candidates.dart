/// پیشنهاد فرستنده‌های بانک: فرستنده‌هایی که پیامکِ مبلغ‌دار داده‌اند ولی هنوز مجاز
/// نیستند — از صندوق گوشی و از تراکنش‌هایی که قبلاً ثبت شده (منطق خالص و تست‌پذیر).
library;

import '../../../core/sms/bank_registry.dart';
import '../../../core/sms/sms_importer.dart';
import '../../../core/sms/sms_parser.dart';
import '../../transactions/data/transaction_record.dart';
import 'allowed_sender.dart';

class SenderCandidate {
  /// فرستنده همان‌طور که در پیامک آمده.
  final String address;

  /// بانکِ حدسی (از نام فرستنده، وگرنه از متن).
  final String? bankId;

  /// پیامک‌های تراکنش‌مانندِ صندوق گوشی از این فرستنده.
  final int inboxCount;

  /// تراکنش‌هایی که قبلاً (پیش از تعیین فرستنده‌ها) از این فرستنده ثبت شده‌اند.
  final List<TransactionRecord> stored;

  /// جدیدترین متن پیامک (تا معلوم شود بانک است یا تبلیغ/فروشگاه).
  final String? sample;
  final DateTime? lastAt;

  const SenderCandidate({
    required this.address,
    required this.inboxCount,
    required this.stored,
    this.bankId,
    this.sample,
    this.lastAt,
  });

  int get weight => inboxCount + stored.length;
}

class _Group {
  final String address;
  String? bankId;
  int inboxCount = 0;
  final List<TransactionRecord> stored = [];
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
  required Iterable<TransactionRecord> stored,
  required Iterable<AllowedSender> allowed,
  SmsParser parser = const SmsParser(),
}) {
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
    if (sms.sender.trim().isEmpty || findAllowedSender(allowed, sms.sender) != null) {
      continue;
    }
    final parsed = parser.parse(sender: sms.sender, body: sms.body);
    if (!parsed.looksLikeTransaction) continue;
    final g = groupFor(sms.sender)
      ..inboxCount += 1
      ..bankId ??= parsed.bankId;
    g.offer(sms.body, sms.receivedAt);
  }

  for (final t in stored) {
    final sender = t.smsSender?.trim();
    if (sender == null || sender.isEmpty || t.isRemote || t.isDeleted) continue;
    if (findAllowedSender(allowed, sender) != null) continue;
    final g = groupFor(sender)..bankId ??= t.bankId;
    g.stored.add(t);
    if (t.smsBody != null) g.offer(t.smsBody!, t.smsReceivedAt ?? t.effectiveTime);
  }

  return [
    for (final g in groups)
      SenderCandidate(
        address: g.address,
        bankId: detectBank(g.address)?.id ?? g.bankId,
        inboxCount: g.inboxCount,
        stored: List.unmodifiable(g.stored),
        sample: g.sample,
        lastAt: g.lastAt,
      ),
  ]..sort((a, b) {
      final c = b.weight.compareTo(a.weight);
      if (c != 0) return c;
      return (b.lastAt ?? DateTime(0)).compareTo(a.lastAt ?? DateTime(0));
    });
}
