/// گزارشِ متنیِ عیب‌یابی برای کپی و فرستادن (به انتخابِ خودِ کاربر).
///
/// شماره‌ی کارت/حساب و هر رشته‌ی عددیِ بلند (کارت، شبا، موبایل) پوشانده می‌شود؛
/// فقط ۴ رقمِ آخر می‌ماند. مبلغ و مانده می‌مانند چون بدون آن‌ها عیب‌یابی ممکن نیست.
/// این متن خودکار جایی فرستاده یا لاگ نمی‌شود؛ فقط در کلیپ‌بورد کپی می‌شود.
library;

import '../../features/transactions/data/transaction_record.dart';
import '../../features/transactions/data/tx_query.dart';
import '../format/date_format.dart';
import '../sms/bank_registry.dart';
import '../sms/digit_utils.dart';
import 'balance_breakdown.dart';
import 'balance_chain.dart';
import 'sms_diagnosis.dart';

final _idAfterKeyword = RegExp(
    r'(حساب|کارت|شماره|شبا|سپرده|IR|ir)(\s*:?\s*)([0-9][0-9\-\*xX\.]{3,}[0-9])');
final _longDigits = RegExp(r'(?<![0-9,])[0-9]{11,}(?![0-9,])');
final _digit = RegExp(r'[0-9]');

/// همه‌ی رقم‌ها جز ۴ رقمِ آخر را با * عوض می‌کند.
String _maskToken(String token) {
  final total = _digit.allMatches(token).length;
  var seen = 0;
  return token.replaceAllMapped(_digit, (m) {
    seen++;
    return seen > total - 4 ? m[0]! : '*';
  });
}

/// پوشاندنِ شماره‌ی کارت/حساب/شبا/موبایل در متن (ارقام فارسی هم لاتین می‌شوند).
String maskSensitive(String text) {
  var s = normalizeDigits(text);
  s = s.replaceAllMapped(
      _idAfterKeyword, (m) => '${m[1]}${m[2]}${_maskToken(m[3]!)}');
  return s.replaceAllMapped(_longDigits, (m) => _maskToken(m[0]!));
}

/// «بانک ملت • حساب 1234567890 • بابا» (با [masked] فقط ۴ رقمِ آخرِ حساب).
String diagAccountTitle(TransactionRecord t, {bool masked = false}) {
  final label = t.walletLabel?.trim();
  final acct = t.accountRef;
  return [
    if (label != null && label.isNotEmpty) label,
    t.bankId != null ? bankNameById(t.bankId!) : 'بانک نامشخص',
    if (t.cardLast4 != null)
      'کارت ${t.cardLast4}'
    else if (acct != null)
      'حساب ${masked ? _maskToken(acct) : acct}'
    else
      'بدون شماره کارت/حساب',
    personOf(t),
  ].join(' • ');
}

String _rial(int v) {
  final digits = v.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return '${v < 0 ? '-' : ''}$b';
}

String _when(DateTime? t) =>
    t == null ? '?' : '${formatJalaliNumeric(t)} ${formatClock(t)}';

String _kind(String k) => switch (k) {
      'income' => 'واریز',
      'expense' => 'برداشت',
      'transfer' => 'انتقال',
      _ => 'نامشخص',
    };

String _oneLine(String body) => maskSensitive(body).replaceAll(RegExp(r'\s*\n\s*'), ' | ');

String buildDiagnosticReport({
  required BalanceBreakdown balance,
  required BalanceChainReport chains,
  SmsDiagnosisReport? sms,
  required DateTime now,
  String? scope,
  String? appVersion,
  int maxSms = 200,
}) {
  final b = StringBuffer()
    ..writeln('گزارش عیب‌یابی «مالی خانواده» — ${_when(now)}')
    ..writeln('بازه: ${balance.period.title} • شخص: ${scope ?? 'همه'}'
        '${appVersion == null ? '' : ' • نسخه: $appVersion'}')
    ..writeln('مبلغ‌ها به ریال. شماره‌ی کارت/حساب پوشانده شده؛ قبل از فرستادن یک بار بخوان.')
    ..writeln();

  // --- موجودی ---
  b
    ..writeln('== موجودی (کارت خلاصه) ==')
    ..writeln('اول دوره: ${_rial(balance.openingRial)} + درآمد: ${_rial(balance.incomeRial)}'
        ' − هزینه: ${_rial(balance.expenseRial)} = ${_rial(balance.expectedClosingRial)}')
    ..writeln('آخر دوره طبق بانک: ${_rial(balance.bankClosingRial)} • اختلاف: ${_rial(balance.diffRial)}');
  for (final c in balance.cards) {
    b.writeln('- ${diagAccountTitle(c.sample, masked: true)}: '
        'اول ${_rial(c.openingRial)}${c.openingIsEstimate ? ' (تخمینی)' : ''}'
        ' | +${_rial(c.incomeRial)} −${_rial(c.expenseRial)}'
        ' | بانک آخر ${_rial(c.closingRial)}${c.closingIsEstimate ? ' (تخمینی)' : ''}'
        ' | اختلاف ${_rial(c.diffRial)}'
        '${c.uncounted.isEmpty ? '' : ' | خارج از جمع: ${c.uncounted.length}'}');
  }
  b.writeln();

  // --- زنجیره‌ی مانده ---
  b.writeln('== زنجیره‌ی مانده (فقط موارد ناجور) ==');
  for (final h in chains.splitHints) {
    b.writeln('! احتمالاً یک حساب‌اند (موجودی دو بار شمرده می‌شود): '
        '${diagAccountTitle(h.a.sample, masked: true)} ⟷ '
        '${diagAccountTitle(h.b.sample, masked: true)} '
        '(${h.consistent} از ${h.switches} جابه‌جایی جور)');
  }
  var anyProblem = false;
  for (final a in chains.accounts) {
    final problems = a.problems;
    if (problems.isEmpty) continue;
    anyProblem = true;
    b.writeln('[${diagAccountTitle(a.sample, masked: true)}] '
        '${problems.length} مورد از ${a.links.length}');
    for (final l in problems) {
      final t = l.tx;
      b.writeln('  - ${_when(t.effectiveTime)} ${_kind(t.kind)}'
          ' ${t.amountRial == null ? '?' : _rial(t.amountRial!)}'
          '${t.needsReview ? ' (بازبینی)' : ''} → ${l.status.label}'
          ' | قبلی ${_rial(l.previousBalanceRial ?? 0)}'
          ' انتظار ${_rial(l.expectedBalanceRial ?? 0)}'
          ' بانک ${_rial(l.actualBalanceRial ?? 0)}'
          ' تغییرِ بانک ${_rial(l.bankDeltaRial ?? 0)}');
      if (t.smsBody != null) b.writeln('    متن: ${_oneLine(t.smsBody!)}');
    }
  }
  if (!anyProblem && chains.splitHints.isEmpty) b.writeln('موردی نیست.');
  b.writeln();

  // --- پیامک‌ها ---
  b.writeln('== پیامک‌های فرستنده‌های مجاز ==');
  if (sms == null) {
    b.writeln('(خوانده نشد)');
    return b.toString();
  }
  if (!sms.inboxRead) b.writeln('(صندوق پیامک خوانده نشد؛ فقط تراکنش‌های ثبت‌شده)');
  b.writeln([
    for (final v in SmsVerdict.values)
      if (sms.count(v) > 0) '${v.label}: ${sms.count(v)}',
  ].join(' • '));
  b.writeln('با قانون پیشنهادی (سرشماره + شماره حساب/کارت + مبلغ + نوع) از جمع/فهرست '
      'بیرون می‌روند: ${sms.droppedByStrictCount}');
  if (sms.notAllowedWithAmount.isNotEmpty) {
    b.writeln('پیامکِ مبلغ‌دار از فرستنده‌های غیرمجاز: ${[
      for (final e in sms.notAllowedWithAmount.entries)
        '${maskSensitive(e.key)} (${e.value})',
    ].join('، ')}');
  }
  for (final d in sms.items.take(maxSms)) {
    final p = d.parsed;
    final strict = d.strict.accepts ? 'قبول' : 'رد: ${d.strict.missing.join('، ')}';
    b.writeln('- ${_when(d.at)} [${maskSensitive(d.sender)}]'
        '${d.inInbox ? '' : ' (در صندوق نیست)'} ${d.verdict.label}'
        ' | پارس: ${_kind(p.kind.name)} ${p.amountRial == null ? '?' : _rial(p.amountRial!)}'
        ' مانده ${p.balanceAfterRial == null ? '-' : _rial(p.balanceAfterRial!)}'
        ' | قانون جدید: $strict');
    b.writeln('    متن: ${_oneLine(d.body)}');
  }
  if (sms.items.length > maxSms) {
    b.writeln('… و ${sms.items.length - maxSms} پیامکِ قدیمی‌تر');
  }
  return b.toString();
}
