import 'package:economy/core/sms/sms_importer.dart';
import 'package:economy/features/senders/data/sender_candidates.dart';
import 'package:flutter_test/flutter_test.dart';

RawSms sms(String sender, String body) => RawSms(
      sender: sender,
      body: body,
      receivedAt: DateTime.utc(2026, 9, 10),
    );

void main() {
  const bankBody = 'خرید مبلغ 10,000 ریال از کارت 1234 مانده 9,000,000 ریال';

  test('فرستنده‌ی مبلغ‌دار به‌عنوان پیشنهاد می‌آید', () {
    final list = findSenderCandidates(
      inbox: [sms('BankMellat', bankBody)],
      stored: const [],
      allowed: const [],
    );
    expect(list.map((c) => c.address), contains('BankMellat'));
  });

  test('فرستنده‌ی «بانک نیست» (dismissed) دیگر پیشنهاد نمی‌شود', () {
    final list = findSenderCandidates(
      inbox: [sms('98404014014201', bankBody)],
      stored: const [],
      allowed: const [],
      dismissed: const ['98404014014201'],
    );
    expect(list, isEmpty);
  });

  test('dismissed با شکل‌های مختلف شماره هم می‌گیرد', () {
    final list = findSenderCandidates(
      inbox: [sms('+989120000510', bankBody)],
      stored: const [],
      allowed: const [],
      dismissed: const ['09120000510'],
    );
    expect(list, isEmpty);
  });
}
