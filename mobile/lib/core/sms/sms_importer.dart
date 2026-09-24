/// وارد کردن پیامک‌ها به‌صورت تراکنش. لایه‌ی خالص و تست‌پذیر؛
/// خواندن واقعی پیامک از سیستم‌عامل در features/sms انجام می‌شود.
///
/// ترتیب (قاعده‌ی پروژه): اول فرستنده — فقط سرشماره/نامی که کاربر مجاز کرده —
/// بعد پارس متن. پیامکِ هر فرستنده‌ی دیگری حتی اگر مبلغ داشته باشد ثبت نمی‌شود؛
/// از فرستنده‌ی مجاز هم فقط پیامکِ دارای شماره‌ی حساب/کارت + مبلغ + نوع — یا پیامکِ
/// بی‌شماره‌ای که مانده‌ی بانکِ دقیقاً یک حساب ثابتش کند ([proveByBalance]).
library;

import '../../features/senders/data/allowed_sender.dart';
import '../../features/transactions/data/transaction_record.dart';
import '../../features/transactions/data/transaction_repository.dart';
import '../reconcile/balance_proof.dart';
import 'models.dart';
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
  final int skipped; // OTP، یادآوری، بی‌شماره یا غیرتراکنش (از فرستنده‌ی مجاز)
  final int notAllowed; // فرستنده جزو فرستنده‌های مجاز نیست

  /// از [created]: پیامک‌های بی‌شماره که مانده‌ی بانک به یک حساب وصلشان کرد.
  final int proven;

  const ImportResult({
    required this.created,
    required this.duplicates,
    required this.skipped,
    this.notAllowed = 0,
    this.proven = 0,
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

  /// یک پیامک را اگر از فرستنده‌ی مجاز و تراکنش باشد ذخیره می‌کند.
  /// اگر تراکنشِ جدید ساخته شد، خلاصه‌اش را برمی‌گرداند؛ وگرنه null.
  Future<ImportedTx?> importOne(RawSms sms) async {
    final sender = findAllowedSender(await store.allowedSenders(), sms.sender);
    if (sender == null) return null; // فرستنده‌ی مجاز نیست
    var parsed = parser.parse(
        sender: sms.sender, body: sms.body, bankId: sender.bankId, receivedAt: sms.receivedAt);
    if (!parsed.isCountable) {
      if (!_provable(parsed, sender)) return null; // OTP، غیرتراکنش یا بی‌بانک
      final account = proveByBalance(
          live: await store.getAll(),
          candidates: [_candidate('0', sms, parsed, sender)])['0'];
      if (account == null) return null; // بی‌شماره و مانده هم ثابتش نکرد
      parsed = _withAccount(parsed, account);
    }
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

  /// واردکردنِ صندوقِ گوشی. [full] = false: فقط پیامک‌های بعد از آخرین خواندن (با ۲ روز
  /// حاشیه)؛ اولین بار (یا [full]) همه. «آخرین خواندن» بعد از هر بار به‌روز می‌شود.
  Future<ImportResult> importInbox(List<RawSms> inbox, {bool full = false}) async {
    // پارسرِ تازه‌تر: پیامک‌هایی که قبلاً رد شده بودند شاید حالا خوانده شوند → کلِ صندوق.
    final parserChanged =
        await store.getSetting(SettingKeys.parserVersion) != '$kParserVersion';
    full = full || parserChanged;
    final raw = full ? null : await store.getSetting(SettingKeys.inboxWatermark);
    final watermark = raw == null ? null : DateTime.tryParse(raw);
    final since = watermark?.subtract(const Duration(days: 2));
    final messages = since == null
        ? inbox
        : [
            for (final m in inbox)
              if (m.receivedAt == null || m.receivedAt!.isAfter(since)) m,
          ];
    final result = await importAll(messages);
    DateTime? newest;
    for (final m in inbox) {
      final at = m.receivedAt;
      if (at != null && (newest == null || at.isAfter(newest))) newest = at;
    }
    if (newest != null &&
        (watermark == null || newest.isAfter(watermark))) {
      await store.setSetting(SettingKeys.inboxWatermark, newest.toUtc().toIso8601String());
    }
    if (parserChanged) await store.setSetting(SettingKeys.parserVersion, '$kParserVersion');
    return result;
  }

  /// فقط شماره‌ی حساب/کارت کم دارد (مبلغ و واریز/برداشت دارد، رمز/یادآوری نیست) و بانکش
  /// معلوم است (پیامکِ بی‌بانک مثلِ اعتبارِ دیجی‌پی هرگز نامزد نیست).
  static bool _provable(ParsedTransaction p, AllowedSender sender) =>
      p.looksLikeTransaction &&
      !p.hasAccountId &&
      (p.kind == TxKind.income || p.kind == TxKind.expense) &&
      (sender.bankId ?? p.bankId) != null;

  static ProofCandidate _candidate(
          String key, RawSms sms, ParsedTransaction p, AllowedSender sender) =>
      ProofCandidate(
        key: key,
        bankId: sender.bankId ?? p.bankId,
        signedAmount: p.kind == TxKind.income ? p.amountRial! : -p.amountRial!,
        balanceAfterRial: p.balanceAfterRial,
        at: proofTime(p.occurredAt, sms.receivedAt) ?? DateTime.now(),
      );

  static ParsedTransaction _withAccount(ParsedTransaction p, TransactionRecord account) =>
      p.withAccount(
          bankId: account.bankId, cardLast4: account.cardLast4, accountRef: account.accountRef);

  /// فهرستی از پیامک‌ها را وارد می‌کند و آمار می‌دهد.
  Future<ImportResult> importAll(List<RawSms> messages) async {
    final allowed = await store.allowedSenders();
    var created = 0;
    var duplicates = 0;
    var skipped = 0;
    var notAllowed = 0;
    final idless = <(RawSms, ParsedTransaction, AllowedSender)>[];
    for (final sms in messages) {
      final sender = findAllowedSender(allowed, sms.sender);
      if (sender == null) {
        notAllowed++;
        continue;
      }
      final parsed = parser.parse(
          sender: sms.sender, body: sms.body, bankId: sender.bankId, receivedAt: sms.receivedAt);
      if (!parsed.isCountable) {
        if (_provable(parsed, sender)) {
          idless.add((sms, parsed, sender));
        } else {
          skipped++;
        }
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

    // دورِ دوم: پیامک‌های بی‌شماره در برابرِ زنجیره‌ی مانده‌ی حساب‌ها (بعد از ثبتِ بقیه).
    var proven = 0;
    if (idless.isNotEmpty) {
      final byProof = proveByBalance(live: await store.getAll(), candidates: [
        for (var i = 0; i < idless.length; i++)
          _candidate('$i', idless[i].$1, idless[i].$2, idless[i].$3),
      ]);
      for (var i = 0; i < idless.length; i++) {
        final account = byProof['$i'];
        if (account == null) {
          skipped++;
          continue;
        }
        final (sms, parsed, _) = idless[i];
        final outcome = await store.saveParsed(
          _withAccount(parsed, account),
          sender: sms.sender,
          deviceId: deviceId,
          receivedAt: sms.receivedAt,
        );
        if (outcome.isCreated) {
          created++;
          proven++;
        } else {
          duplicates++;
        }
      }
    }
    return ImportResult(
      created: created,
      duplicates: duplicates,
      skipped: skipped,
      notAllowed: notAllowed,
      proven: proven,
    );
  }
}
