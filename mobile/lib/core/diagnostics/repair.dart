/// تعمیرِ خودکارِ داده با قانون‌های فعلی (خالص؛ فقط «وصله» می‌سازد، خودش چیزی نمی‌نویسد).
///
/// سه کار، به این ترتیب:
///   ۱) **وصل کردنِ نسخه‌های سرور به پیامکشان:** تراکنشی که از سرور برگشته (مثلاً از
///      نصبِ قبلی) شماره‌ی حساب ندارد، چون شماره‌ی حساب عمداً به سرور نمی‌رود؛ برای همین
///      جدا از حسابِ اصلی شمرده می‌شد و موجودی دو بار جمع می‌خورد. اگر پیامکش هنوز در
///      گوشی باشد (با اثرانگشتِ پیامک)، متن و شماره‌ی حسابش برمی‌گردد.
///   ۲) **تکمیل از متن پیامک:** شماره‌ی حساب/کارت، بانک، مانده و تاریخی که پارسرِ قدیمی
///      نخوانده بود (مثلاً «24:00» که اولِ روز حساب می‌شد).
///   ۳) **قانونِ «شماره‌ی حساب/کارت + مبلغ + نوع»:** پیامکِ بی‌شماره یا رمز پویا/یادآوری
///      حذف نرم می‌شود (قابل برگرداندن). تراکنشی که کاربر دستی به کارتی چسبانده یا
///      برگردانده ([kept]) دست نمی‌خورد.
library;

import '../../features/senders/data/allowed_sender.dart';
import '../../features/transactions/data/transaction_record.dart';
import '../../features/transactions/data/transaction_repository.dart';
import '../sms/sms_fingerprint.dart';
import '../sms/sms_importer.dart';
import '../sms/sms_parser.dart';

class RepairResult {
  final DateTime at;

  /// نسخه‌های سرور که به پیامکِ خودشان وصل شدند.
  final int adopted;

  /// تراکنش‌هایی که شماره/مانده/تاریخشان از متن پیامک تکمیل شد.
  final int backfilled;

  /// شناسه‌ی تراکنش‌هایی که با قانون کنار رفتند (حذف نرم).
  final List<String> removedIds;

  /// پیامک‌های تراکنشیِ صندوق که تازه وارد شدند (قبلاً ثبت نشده بودند).
  final int imported;

  const RepairResult({
    required this.at,
    this.adopted = 0,
    this.backfilled = 0,
    this.removedIds = const [],
    this.imported = 0,
  });

  int get removed => removedIds.length;
  bool get changedAnything => adopted + backfilled + removed + imported > 0;

  Map<String, Object?> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'adopted': adopted,
        'backfilled': backfilled,
        'removed': removedIds,
        'imported': imported,
      };

  factory RepairResult.fromJson(Map<String, dynamic> j) => RepairResult(
        at: DateTime.parse(j['at'] as String),
        adopted: j['adopted'] as int? ?? 0,
        backfilled: j['backfilled'] as int? ?? 0,
        removedIds: [for (final e in (j['removed'] as List? ?? const [])) e.toString()],
        imported: j['imported'] as int? ?? 0,
      );
}

class RepairPlan {
  final List<TxPatch> patches;
  final RepairResult result;
  const RepairPlan(this.patches, this.result);
}

/// [records]: تراکنش‌های حذف‌نشده (هر دو منشأ)؛ [inbox]: صندوقِ پیامکِ گوشی.
RepairPlan planRepair({
  required Iterable<TransactionRecord> records,
  required List<RawSms> inbox,
  required List<AllowedSender> allowed,
  required DateTime now,
  Set<String> kept = const {},
  SmsParser parser = const SmsParser(),
}) {
  final working = {for (final t in records) if (!t.isDeleted) t.id: t};
  final cols = <String, Map<String, Object?>>{};
  void setCols(String id, Map<String, Object?> c) {
    (cols[id] ??= {}).addAll(c);
    working[id] = recordWith(working[id]!, c);
  }

  // ۱) وصل کردنِ ردیف‌های بی‌متن (نسخه‌ی سرور) به پیامکِ خودشان.
  final orphanByHash = <String, TransactionRecord>{
    for (final t in working.values)
      if (t.smsBody == null && t.sourceMessageHash != null) t.sourceMessageHash!: t,
  };
  final adopted = <String>{};
  for (final sms in inbox) {
    if (orphanByHash.isEmpty) break;
    if (findAllowedSender(allowed, sms.sender) == null) continue;
    final fp = smsFingerprint(sender: sms.sender, body: sms.body, receivedAt: sms.receivedAt);
    final t = orphanByHash.remove(fp);
    if (t == null) continue;
    adopted.add(t.id);
    setCols(t.id, {
      'sms_sender': sms.sender,
      'sms_body': sms.body,
      'sms_received_at': sms.receivedAt?.toUtc().toIso8601String(),
      'sms_content_hash': smsContentHash(sender: sms.sender, body: sms.body),
      'origin': 'local',
    });
  }

  // ۲ و ۳) تکمیل از متن + قانون.
  final backfilled = <String>{};
  final removed = <String>[];
  for (final t in [...working.values]) {
    if (t.source != 'sms' || t.smsBody == null || t.isRemote) continue;
    final sender = t.smsSender ?? '';
    final parsed = parser.parse(
      sender: sender,
      body: t.smsBody!,
      bankId: findAllowedSender(allowed, sender)?.bankId,
    );
    final fill = <String, Object?>{
      if (t.accountRef == null && parsed.accountRef != null) 'account_ref': parsed.accountRef,
      if (t.cardLast4 == null && parsed.cardLast4 != null) 'card_last4': parsed.cardLast4,
      if (t.bankId == null && parsed.bankId != null) 'bank_id': parsed.bankId,
      if (t.balanceAfterRial == null && parsed.balanceAfterRial != null)
        'balance_after_rial': parsed.balanceAfterRial,
      if (parsed.occurredAt != null && parsed.occurredAt != t.transactionDate)
        'transaction_date': parsed.occurredAt!.toUtc().toIso8601String(),
    };
    final hasId = (t.accountRef ?? parsed.accountRef) != null ||
        (t.cardLast4 ?? parsed.cardLast4) != null;
    final breaksRule = !hasId || parsed.isOtp || parsed.isReminder;
    if (breaksRule && t.pinnedWalletId == null && !kept.contains(t.id)) {
      removed.add(t.id);
    } else if (fill.isNotEmpty) {
      setCols(t.id, fill);
      backfilled.add(t.id);
    }
  }

  final patches = <TxPatch>[
    for (final id in {...cols.keys, ...removed})
      TxPatch(id, set: cols[id] ?? const {}, delete: removed.contains(id)),
  ];
  return RepairPlan(
    patches,
    RepairResult(
      at: now,
      adopted: adopted.length,
      backfilled: backfilled.difference(adopted).length,
      removedIds: removed,
    ),
  );
}
