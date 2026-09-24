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
///
/// و برعکس ([planRevival]): تراکنشی که **خودِ برنامه** حذف کرده بود و حالا با قانون
/// می‌خواند (پارسرِ بهتر، فرستنده‌ی دوباره مجاز) خودکار برمی‌گردد؛ و ([planBalanceRevival])
/// حذف‌شده‌ای که مانده‌ی بانک ثابت می‌کند واقعاً انجام شده.
library;

import '../../features/senders/data/allowed_sender.dart';
import '../../features/transactions/data/transaction_record.dart';
import '../../features/transactions/data/transaction_repository.dart';
import '../reconcile/balance_proof.dart';
import '../sms/sms_fingerprint.dart';
import '../sms/sms_importer.dart';
import '../sms/models.dart';
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

  /// حذف‌شده‌های خودکارِ قبلی که حالا با قانون می‌خوانند و برگشتند.
  final int revived;

  /// تراکنش‌هایی که مانده‌ی بانک ثابتشان کرد (حذف‌شده‌ی برگشته یا پیامکِ بی‌شماره‌ی واردشده).
  final int proven;

  /// نسخه‌ی پارسری که این تعمیر با آن اجرا شد ([kParserVersion])؛ پارسرِ تازه‌تر
  /// یعنی تعمیر یک بار دیگر خودکار اجرا شود.
  final int? parserVersion;

  const RepairResult({
    required this.at,
    this.adopted = 0,
    this.backfilled = 0,
    this.removedIds = const [],
    this.imported = 0,
    this.revived = 0,
    this.proven = 0,
    this.parserVersion,
  });

  int get removed => removedIds.length;
  bool get changedAnything =>
      adopted + backfilled + removed + imported + revived + proven > 0;

  Map<String, Object?> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'adopted': adopted,
        'backfilled': backfilled,
        'removed': removedIds,
        'imported': imported,
        'revived': revived,
        'proven': proven,
        if (parserVersion != null) 'parser': parserVersion,
      };

  factory RepairResult.fromJson(Map<String, dynamic> j) => RepairResult(
        at: DateTime.parse(j['at'] as String),
        adopted: j['adopted'] as int? ?? 0,
        backfilled: j['backfilled'] as int? ?? 0,
        removedIds: [for (final e in (j['removed'] as List? ?? const [])) e.toString()],
        imported: j['imported'] as int? ?? 0,
        revived: j['revived'] as int? ?? 0,
        proven: j['proven'] as int? ?? 0,
        parserVersion: j['parser'] as int?,
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
    // ردیفِ سرور که متنِ پیامکش روی همین گوشی پیدا شده هم (بعد از نصبِ دوباره): پیامک
    // مالِ همین گوشی است، پس شماره‌ی حساب و بقیه از متن تکمیل و ردیف «محلی» می‌شود.
    if (t.source != 'sms' || t.smsBody == null) continue;
    final sender = t.smsSender ?? '';
    final parsed = parser.parse(
      sender: sender,
      body: t.smsBody!,
      bankId: findAllowedSender(allowed, sender)?.bankId,
      receivedAt: t.smsReceivedAt,
    );
    final fill = {..._fillFromText(t, parsed), if (t.isRemote) 'origin': 'local'};
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

/// ستون‌هایی که پارسرِ قدیمی نخوانده بود و متنِ پیامک دارد: شماره/بانکِ خالی، مانده و تاریخ.
Map<String, Object?> _fillFromText(TransactionRecord t, ParsedTransaction parsed) => {
      if (t.accountRef == null && parsed.accountRef != null) 'account_ref': parsed.accountRef,
      if (t.cardLast4 == null && parsed.cardLast4 != null) 'card_last4': parsed.cardLast4,
      if (t.bankId == null && parsed.bankId != null) 'bank_id': parsed.bankId,
      if (parsed.balanceAfterRial != null && parsed.balanceAfterRial != t.balanceAfterRial)
        'balance_after_rial': parsed.balanceAfterRial,
      if (parsed.occurredAt != null && parsed.occurredAt != t.transactionDate)
        'transaction_date': parsed.occurredAt!.toUtc().toIso8601String(),
    };

/// برگرداندنِ تراکنش‌هایی که **خودِ برنامه** حذف کرده بود ([autoRemoved]: تعمیرِ خودکار،
/// «بردار و تراکنش‌هایش را حذف کن») و حالا با قانون می‌خوانند: فرستنده‌شان مجاز است و
/// پیامکشان «شماره حساب/کارت + مبلغ + نوع» دارد (مثلاً بعد از بهترشدنِ پارسر، یا مجاز
/// کردنِ دوباره‌ی فرستنده). بدونِ این، ضدتکرار (که حذف‌شده‌ها را هم می‌بیند) نمی‌گذاشت
/// آن پیامک‌ها دوباره ثبت شوند. حذفِ دستیِ کاربر در [autoRemoved] نیست و برنمی‌گردد.
List<TxPatch> planRevival({
  required Iterable<TransactionRecord> deleted,
  required Set<String> autoRemoved,
  required List<AllowedSender> allowed,
  SmsParser parser = const SmsParser(),
}) {
  final patches = <TxPatch>[];
  for (final t in deleted) {
    if (!t.isDeleted || !autoRemoved.contains(t.id)) continue;
    final body = t.smsBody, address = t.smsSender;
    if (t.source != 'sms' || body == null || address == null) continue;
    final sender = findAllowedSender(allowed, address);
    if (sender == null) continue;
    final parsed = parser.parse(
        sender: address, body: body, bankId: sender.bankId, receivedAt: t.smsReceivedAt);
    if (!parsed.isCountable) continue;
    patches.add(TxPatch(t.id, set: _fillFromText(t, parsed), restore: true));
  }
  return patches;
}

/// حذف‌شده‌هایی که **مانده‌ی بانک** ثابت می‌کند واقعاً انجام شده‌اند ([proveByBalance]) برمی‌گردند؛
/// اگر شماره‌ی حساب/کارت نداشتند (کارمزد/وام/قسطِ «حساب دیجیتال» پاسارگاد) به همان حساب وصل
/// می‌شوند. نوع/مبلغ/مانده از پارسرِ فعلی (ردیفِ قدیمی ممکن است «باقی مانده:0» را مانده خوانده باشد).
/// [userDeleted]: حذف‌های دستیِ کاربر از این نسخه به بعد؛ این‌ها برنمی‌گردند.
List<TxPatch> planBalanceRevival({
  required Iterable<TransactionRecord> live,
  required Iterable<TransactionRecord> deleted,
  required List<AllowedSender> allowed,
  Set<String> userDeleted = const {},
  SmsParser parser = const SmsParser(),
}) {
  final rows = <String, (TransactionRecord, ParsedTransaction)>{};
  final candidates = <ProofCandidate>[];
  for (final t in deleted) {
    if (!t.isDeleted || userDeleted.contains(t.id)) continue;
    final body = t.smsBody, address = t.smsSender;
    if (t.source != 'sms' || body == null || address == null) continue;
    final sender = findAllowedSender(allowed, address);
    if (sender == null) continue;
    final p = parser.parse(
        sender: address, body: body, bankId: sender.bankId, receivedAt: t.smsReceivedAt);
    if (!p.looksLikeTransaction || (p.kind != TxKind.income && p.kind != TxKind.expense)) continue;
    final bank = t.bankId ?? sender.bankId ?? p.bankId;
    final card = t.cardLast4 ?? p.cardLast4, acct = t.accountRef ?? p.accountRef;
    rows[t.id] = (t, p);
    candidates.add(ProofCandidate(
      key: t.id,
      bankId: bank,
      signedAmount: p.kind == TxKind.income ? p.amountRial! : -p.amountRial!,
      balanceAfterRial: p.balanceAfterRial,
      at: proofTime(p.occurredAt, t.smsReceivedAt) ?? t.effectiveTime,
      accountKey: card == null && acct == null
          ? null
          : balanceCardKey(recordWith(t, {'bank_id': bank, 'card_last4': card, 'account_ref': acct})),
    ));
  }
  final proven = proveByBalance(live: live, candidates: candidates);
  return [
    for (final e in proven.entries)
      if (rows[e.key] case (final t, final p))
        TxPatch(t.id, restore: true, set: {
          ..._fillFromText(t, p),
          'kind': p.kind.name,
          'amount_rial': p.amountRial,
          'balance_after_rial': p.balanceAfterRial,
          'needs_review': p.needsReview ? 1 : 0,
          if (t.bankId == null) 'bank_id': e.value.bankId,
          if (t.cardLast4 == null && p.cardLast4 == null && t.accountRef == null && p.accountRef == null) ...{
            'card_last4': e.value.cardLast4,
            'account_ref': e.value.accountRef,
          },
          if (t.isRemote) 'origin': 'local',
        }),
  ];
}
