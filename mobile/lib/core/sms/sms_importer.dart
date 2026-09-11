/// وارد کردن پیامک‌ها به‌صورت تراکنش. لایه‌ی خالص و تست‌پذیر؛
/// خواندن واقعی پیامک از سیستم‌عامل در features/sms انجام می‌شود.
library;

import '../../features/transactions/data/transaction_repository.dart';
import 'sms_parser.dart';

/// یک پیامک خام (فرستنده + متن + زمان دریافت).
class RawSms {
  final String sender;
  final String body;
  final DateTime? receivedAt;

  const RawSms({required this.sender, required this.body, this.receivedAt});
}

class ImportResult {
  final int created;
  final int duplicates;
  final int skipped; // OTP یا غیرتراکنش

  const ImportResult({
    required this.created,
    required this.duplicates,
    required this.skipped,
  });
}

class SmsImporter {
  final TransactionStore store;
  final SmsParser parser;
  final String? deviceId;

  const SmsImporter(this.store, {this.parser = const SmsParser(), this.deviceId});

  /// یک پیامک را در صورت تراکنش‌بودن ذخیره می‌کند. برمی‌گرداند: ذخیره شد یا نه.
  Future<bool> importOne(RawSms sms) async {
    final parsed = parser.parse(sender: sms.sender, body: sms.body);
    if (!parsed.looksLikeTransaction) return false; // OTP یا غیرتراکنش
    final outcome = await store.saveParsed(
      parsed,
      sender: sms.sender,
      deviceId: deviceId,
      receivedAt: sms.receivedAt,
    );
    return outcome.isCreated;
  }

  /// فهرستی از پیامک‌ها را وارد می‌کند و آمار می‌دهد.
  Future<ImportResult> importAll(List<RawSms> messages) async {
    var created = 0;
    var duplicates = 0;
    var skipped = 0;
    for (final sms in messages) {
      final parsed = parser.parse(sender: sms.sender, body: sms.body);
      if (!parsed.looksLikeTransaction) {
        skipped++;
        continue;
      }
      final outcome = await store.saveParsed(
        parsed,
        sender: sms.sender,
        deviceId: deviceId,
        receivedAt: sms.receivedAt,
      );
      if (outcome.isCreated) {
        created++;
      } else {
        duplicates++;
      }
    }
    return ImportResult(created: created, duplicates: duplicates, skipped: skipped);
  }
}
