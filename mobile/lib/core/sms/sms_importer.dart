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
  final int skipped; // OTP، یادآوری یا غیرتراکنش

  const ImportResult({
    required this.created,
    required this.duplicates,
    required this.skipped,
  });
}

/// خلاصه‌ی یک تراکنشِ تازه‌ساخته‌شده (برای نوتیفیکیشن).
class ImportedTx {
  final String id;
  final int amountRial;

  /// نوتیفیکیشن «دسته‌بندی کن» لازم است؟ فقط برای تراکنشِ خودم (نه عضو دیگر)،
  /// بدون ابهام، و از «شروع دسته‌بندی» به بعد.
  final bool promptCategorize;

  const ImportedTx({
    required this.id,
    required this.amountRial,
    this.promptCategorize = true,
  });
}

class SmsImporter {
  final TransactionStore store;
  final SmsParser parser;
  final String? deviceId;

  const SmsImporter(this.store, {this.parser = const SmsParser(), this.deviceId});

  /// یک پیامک را در صورت تراکنش‌بودن ذخیره می‌کند.
  /// اگر تراکنشِ جدید ساخته شد، خلاصه‌اش را برمی‌گرداند؛ وگرنه null.
  Future<ImportedTx?> importOne(RawSms sms) async {
    final parsed = parser.parse(sender: sms.sender, body: sms.body);
    if (!parsed.looksLikeTransaction) return null; // OTP یا غیرتراکنش
    final outcome = await store.saveParsed(
      parsed,
      sender: sms.sender,
      deviceId: deviceId,
      receivedAt: sms.receivedAt,
    );
    if (!outcome.isCreated) return null; // تکراری
    return ImportedTx(
      id: outcome.id,
      amountRial: parsed.amountRial ?? 0,
      promptCategorize: await _shouldPrompt(outcome.id),
    );
  }

  Future<bool> _shouldPrompt(String id) async {
    final t = await store.getById(id);
    if (t == null || t.needsReview) return false;
    if (t.kind != 'income' && t.kind != 'expense') return false;
    final me = await store.getSetting(SettingKeys.meUserId);
    if (me != null && t.ownerUserId != null && t.ownerUserId != me) return false;
    return !t.effectiveTime.isBefore(await store.categorizeFrom());
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
