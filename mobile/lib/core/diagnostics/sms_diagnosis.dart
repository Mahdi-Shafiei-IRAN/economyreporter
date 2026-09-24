/// عیب‌یابیِ پیامک‌ها: هر پیامکِ فرستنده‌ی مجاز چه سرنوشتی داشت و چرا.
///
/// برای هر پیامک (صندوق گوشی + پیامک‌های ثبت‌شده‌ای که دیگر در صندوق نیستند) می‌گوید
/// شمرده شد، انتقال/بازبینی شد، حذف شد، یا چرا رد شد. قانونِ ثبت: پیامک فقط وقتی
/// تراکنش است که از سرشماره‌ی مجاز باشد و **شماره‌ی حساب/کارت + مبلغ + نوع
/// (واریز/برداشت)** داشته باشد ([ParsedTransaction.isCountable]).
///
/// همه‌چیز روی گوشی می‌ماند؛ متن پیامک به سرور یا لاگ نمی‌رود.
library;

import '../../features/senders/data/allowed_sender.dart';
import '../../features/transactions/data/transaction_record.dart';
import '../../features/transactions/data/transaction_repository.dart';
import '../sms/models.dart';
import '../sms/sms_fingerprint.dart';
import '../sms/sms_importer.dart';
import '../sms/sms_parser.dart';

enum SmsVerdict {
  /// ثبت شده و در درآمد/هزینه می‌آید.
  counted,

  /// ثبت شده ولی «انتقال» است؛ در درآمد/هزینه نمی‌آید.
  transfer,

  /// ثبت شده ولی منتظر بازبینی/نوع نامشخص؛ در جمع نمی‌آید.
  review,

  /// ثبت شده و بعد حذف (نامعتبر) شده.
  deleted,

  /// همان تراکنشِ یک پیامکِ دیگر (ضدتکرار یکی‌شان کرده).
  duplicate,

  /// پارسر آن را تراکنش می‌داند ولی ثبت نشده.
  notImported,

  /// رمز پویا/یکبارمصرف.
  otp,

  /// یادآوری/سررسید.
  reminder,

  /// مبلغ پیدا نشد.
  noAmount,

  /// معلوم نشد واریز است یا برداشت.
  unknownKind,

  /// شماره‌ی حساب/کارت ندارد (اعتبار کیف پول، تبلیغ، اطلاعیه، …).
  noId,
}

extension SmsVerdictInfo on SmsVerdict {
  /// ثبت شده (در دیتابیس هست و حذف نشده)؟
  bool get isStored =>
      this == SmsVerdict.counted ||
      this == SmsVerdict.transfer ||
      this == SmsVerdict.review;

  String get label => switch (this) {
        SmsVerdict.counted => 'شمرده شد',
        SmsVerdict.transfer => 'انتقال (در جمع نیست)',
        SmsVerdict.review => 'منتظر بازبینی (در جمع نیست)',
        SmsVerdict.deleted => 'حذف شده',
        SmsVerdict.duplicate => 'تکراری (یکی شد)',
        SmsVerdict.notImported => 'ثبت نشده',
        SmsVerdict.otp => 'رد: رمز پویا',
        SmsVerdict.reminder => 'رد: یادآوری/سررسید',
        SmsVerdict.noAmount => 'رد: مبلغ ندارد',
        SmsVerdict.unknownKind => 'رد: نوع نامعلوم',
        SmsVerdict.noId => 'رد: شماره حساب/کارت ندارد',
      };
}

/// نتیجه‌ی «قانون پیشنهادی» روی یک پیامک.
class StrictCheck {
  /// چیزهایی که پیامک کم دارد (خالی = قبول).
  final List<String> missing;

  const StrictCheck(this.missing);

  bool get accepts => missing.isEmpty;

  static const noId = 'شماره حساب/کارت ندارد';
  static const noAmount = 'مبلغ ندارد';
  static const noKind = 'نوعش (واریز/برداشت) معلوم نیست';
  static const notTx = 'رمز پویا/یادآوری است';

  factory StrictCheck.of(ParsedTransaction p) => StrictCheck([
        if (p.isOtp || p.isReminder) notTx,
        if (p.cardLast4 == null && p.accountRef == null) noId,
        if (p.amountRial == null) noAmount,
        if (p.kind == TxKind.unknown) noKind,
      ]);
}

class SmsDiagnosis {
  final String sender;
  final String body;

  /// زمان رسیدن پیامک (یا زمانِ تراکنشِ ثبت‌شده).
  final DateTime? at;
  final AllowedSender allowed;
  final ParsedTransaction parsed;

  /// تراکنشِ ثبت‌شده برای این پیامک (اگر هست).
  final TransactionRecord? stored;

  /// false یعنی پیامک دیگر در صندوق گوشی نیست و فقط تراکنشش مانده.
  final bool inInbox;
  final SmsVerdict verdict;
  final StrictCheck strict;

  const SmsDiagnosis({
    required this.sender,
    required this.body,
    required this.at,
    required this.allowed,
    required this.parsed,
    required this.stored,
    required this.inInbox,
    required this.verdict,
    required this.strict,
  });

  /// الان در جمع‌ها/فهرست هست ولی با قانون پیشنهادی رد می‌شود.
  bool get droppedByStrict => verdict.isStored && !strict.accepts;
}

class SmsDiagnosisReport {
  /// جدیدترین اول.
  final List<SmsDiagnosis> items;

  /// پیامک‌های مبلغ‌دار از فرستنده‌هایی که مجاز نیستند (فرستنده → تعداد).
  final Map<String, int> notAllowedWithAmount;

  /// صندوق گوشی خوانده شد؟ (بدون مجوز پیامک فقط تراکنش‌های ثبت‌شده دیده می‌شوند.)
  final bool inboxRead;

  const SmsDiagnosisReport({
    required this.items,
    required this.notAllowedWithAmount,
    this.inboxRead = true,
  });

  int count(SmsVerdict v) => items.where((d) => d.verdict == v).length;

  int get droppedByStrictCount => items.where((d) => d.droppedByStrict).length;

  int get rejectedCount => items
      .where((d) => !d.verdict.isStored && d.verdict != SmsVerdict.deleted)
      .length;
}

SmsVerdict _verdictOfStored(TransactionRecord t) {
  if (t.isDeleted) return SmsVerdict.deleted;
  if (countsInTotals(t)) return SmsVerdict.counted;
  if (!t.needsReview && t.kind == 'transfer') return SmsVerdict.transfer;
  return SmsVerdict.review;
}

SmsVerdict _verdictOfParsed(ParsedTransaction p) {
  if (p.isOtp) return SmsVerdict.otp;
  if (p.isReminder) return SmsVerdict.reminder;
  if (p.amountRial == null) return SmsVerdict.noAmount;
  if (p.kind == TxKind.unknown) return SmsVerdict.unknownKind;
  if (!p.hasAccountId) return SmsVerdict.noId;
  return SmsVerdict.notImported;
}

/// [inbox]: پیامک‌های صندوق گوشی؛ [stored]: همه‌ی تراکنش‌های محلی (با حذف‌شده‌ها).
SmsDiagnosisReport diagnoseSms({
  required List<RawSms> inbox,
  required Iterable<TransactionRecord> stored,
  required List<AllowedSender> allowed,
  SmsParser parser = const SmsParser(),
  bool inboxRead = true,
}) {
  final smsTx = [
    for (final t in stored)
      if (t.source == 'sms' && !t.isRemote && t.smsBody != null) t,
  ];
  // نسخه‌ی سرورِ همین پیامک (بی‌متن) هم همان تراکنش است.
  final byHash = <String, TransactionRecord>{
    for (final t in stored)
      if (t.source == 'sms' && t.sourceMessageHash != null) t.sourceMessageHash!: t,
  };
  final byContent = <String, List<TransactionRecord>>{};
  for (final t in smsTx) {
    if (t.smsContentHash != null) {
      byContent.putIfAbsent(t.smsContentHash!, () => []).add(t);
    }
  }
  final claimed = <String>{};
  final items = <SmsDiagnosis>[];
  final notAllowed = <String, int>{};

  // قدیمی‌ترین اول، تا در پیامک‌های تکراری اولی صاحبِ تراکنش شود.
  final ordered = [...inbox]..sort((a, b) =>
      (a.receivedAt ?? DateTime(0)).compareTo(b.receivedAt ?? DateTime(0)));

  for (final sms in ordered) {
    final sender = findAllowedSender(allowed, sms.sender);
    if (sender == null) {
      final p = parser.parse(sender: sms.sender, body: sms.body);
      if (p.amountRial != null && !p.isOtp) {
        notAllowed[sms.sender] = (notAllowed[sms.sender] ?? 0) + 1;
      }
      continue;
    }
    final parsed =
        parser.parse(sender: sms.sender, body: sms.body, bankId: sender.bankId);

    TransactionRecord? match = byHash[smsFingerprint(
        sender: sms.sender, body: sms.body, receivedAt: sms.receivedAt)];
    if (match == null) {
      final candidates = byContent[smsContentHash(sender: sms.sender, body: sms.body)];
      if (candidates != null && candidates.isNotEmpty) {
        final free = [for (final t in candidates) if (!claimed.contains(t.id)) t];
        match = _nearest(free.isNotEmpty ? free : candidates, sms.receivedAt);
      }
    }

    SmsVerdict verdict;
    if (match != null && claimed.contains(match.id)) {
      verdict = SmsVerdict.duplicate;
    } else if (match != null) {
      claimed.add(match.id);
      verdict = _verdictOfStored(match);
    } else {
      verdict = _verdictOfParsed(parsed);
    }
    items.add(SmsDiagnosis(
      sender: sms.sender,
      body: sms.body,
      at: sms.receivedAt,
      allowed: sender,
      parsed: parsed,
      stored: match,
      inInbox: true,
      verdict: verdict,
      strict: StrictCheck.of(parsed),
    ));
  }

  // تراکنش‌های پیامکیِ این گوشی که پیامکشان دیگر در صندوق نیست.
  for (final t in smsTx) {
    if (claimed.contains(t.id)) continue;
    final sender = t.smsSender ?? '';
    final allowedSender = findAllowedSender(allowed, sender) ??
        AllowedSender(id: '', address: sender, bankId: t.bankId);
    final parsed = parser.parse(
        sender: sender, body: t.smsBody!, bankId: allowedSender.bankId);
    items.add(SmsDiagnosis(
      sender: sender,
      body: t.smsBody!,
      at: t.smsReceivedAt ?? t.effectiveTime,
      allowed: allowedSender,
      parsed: parsed,
      stored: t,
      inInbox: false,
      verdict: _verdictOfStored(t),
      strict: StrictCheck.of(parsed),
    ));
  }

  items.sort((a, b) =>
      (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
  return SmsDiagnosisReport(
    items: items,
    notAllowedWithAmount: notAllowed,
    inboxRead: inboxRead,
  );
}

TransactionRecord _nearest(List<TransactionRecord> list, DateTime? at) {
  if (at == null) return list.first;
  TransactionRecord best = list.first;
  Duration? bestGap;
  for (final t in list) {
    final when = t.smsReceivedAt ?? t.effectiveTime;
    final gap = when.difference(at.toUtc()).abs();
    if (bestGap == null || gap < bestGap) {
      best = t;
      bestGap = gap;
    }
  }
  return best;
}
