/// پارسر پیامک بانکی.
///
/// ترتیب کار (طبق طراحی پروژه):
///   ۱) تشخیص بانک از روی فرستنده
///   ۲) استخراج مبلغ/نوع/مانده/کارت/پذیرنده از متن
///
/// فعلاً یک استخراج‌گر عمومی (Generic) داریم؛ در فاز کامل، پارسر مخصوص هر بانک
/// روی همین پایه اضافه می‌شود. جزئیات: docs/sms-parsing.md
library;

import 'bank_registry.dart';
import 'digit_utils.dart';
import 'jalali.dart';
import 'models.dart';

class SmsParser {
  const SmsParser();

  // پیامک رمز پویا/یکبارمصرف — نباید تراکنش حساب شود (فشرده).
  static const _otpKeywords = [
    'رمزپویا',
    'رمزیکبار',
    'یکبارمصرف',
    'رمزدوم',
    'رمزاینترنتی',
    'رمزپرداخت',
    'کدتایید',
    'کدتأیید',
    'کدفعالسازی',
    'کدفعال‌سازی',
    'کدپویا',
    'رمزخرید',
    'ثانیه', // «اعتبار ۶۰ ثانیه» — پیامک تراکنش واقعی ثانیه ندارد
    'otp',
    'pooya',
  ];

  // «رمز: 123456» یا «کد پویا 12345» → رمز یکبارمصرف (حتی اگر مبلغ داشته باشد).
  static final _otpCodeRe = RegExp(
    r'(?:رمز|کد)\s*(?:پویا|یکبار\s*مصرف|دوم|خرید|اینترنتی|تایید|تأیید)?\s*:?\s*[0-9]{4,}',
  );

  // یادآوری/سررسید قسط یا قبض — تراکنشِ انجام‌شده نیست.
  static const _reminderKeywords = ['یادآوری', 'سررسید', 'مهلتپرداخت', 'قابلپرداخت'];

  // نشانه‌ی تراکنش ناموفق/لغوشده → به صف بازبینی (کاربر تأیید یا حذف می‌کند).
  static const _failedKeywords = [
    'ناموفق',
    'لغوشد',
    'عدمموفقیت',
    'انجامنشد',
    'ردشد',
    'برگشتخورد',
    'موجودیکافینیست',
    'موجودیناکافی',
    'عدمموجودی',
    'رمزنامعتبر',
    'رمزاشتباه',
  ];

  // کلیدواژه‌ها به‌صورت فشرده (بدون فاصله) چون فاصله‌گذاری متغیر است.
  static const _transferKeywords = ['کارتبهکارت', 'حواله'];
  static const _expenseKeywords = ['برداشت', 'خرید', 'پرداخت', 'کسر', 'انتقالوجه', 'انتقال'];
  static const _incomeKeywords = ['واریز', 'عودت', 'افزایش'];

  static final _balanceRe = RegExp(r'(?:مانده|موجودی)\s*:?\s*([0-9][0-9,]*)');
  static final _amountLabeledRe = RegExp(r'مبلغ\s*:?\s*([0-9][0-9,]*)');
  static final _currencyRe = RegExp(r'([0-9][0-9,]*)\s*(ریال|تومان)');
  // مبلغِ چسبیده به فعل، بدون واحد و بدون «مبلغ» (مثل «برداشت13,625,000»).
  static final _amountAfterActionRe = RegExp(
    r'(?:برداشت|واریز|خرید|پرداخت|کسر|عودت|انتقال)\s*:?\s*([0-9][0-9,]{1,})',
  );
  static final _cardRe = RegExp(r'کارت\s*:?\s*([0-9x\*\.\-]{4,})');
  static final _fourDigitsRe = RegExp(r'[0-9]{4}');
  // شماره‌ی حساب: «حساب» و بعد حداقل ۵ رقم (تا با اعداد کوتاه اشتباه نشود).
  static final _accountRe = RegExp(r'حساب\s*:?\s*([0-9]{5,})');

  // استخراج طرف حساب/پذیرنده: «بابت ...»، «به کارت ...»، «پذیرنده/فروشگاه ...».
  static final _reasonRe = RegExp(r'بابت\s*:?\s*(.+?)(?:\s+مانده|\s+تاریخ|\s+\d{2,4}/|$)');
  static final _destCardRe = RegExp(r'به\s*کارت\s*:?\s*([0-9x\*\.\-]{4,})');
  // پایانِ نام پذیرنده: «مانده»، «تاریخ» یا خودِ تاریخ (مثل 1405/06/20) — تا تاریخ جزو نام نشود.
  static final _merchantRe = RegExp(
      r'(?:پذیرنده|فروشگاه)\s*:?\s*(.+?)(?:\s+مانده|\s+تاریخ|\s+\d{2,4}/|$)');

  /// [bankId]: بانکی که کاربر برای این فرستنده تعیین کرده (فرستنده‌های مجاز).
  ParsedTransaction parse({
    required String sender,
    required String body,
    String? bankId,
  }) {
    // قدم ۱: تشخیص بانک از فرستنده — اول بانکی که کاربر برای این سرشماره تعیین
    // کرده، بعد از نام فرستنده، و اگر نشد از داخل متن (بعضی بانک‌ها نامشان را در
    // متن پیامک می‌آورند).
    final bank = (bankId == null ? null : bankById(bankId)) ??
        detectBank(sender) ??
        detectBank(body);

    final normalized = normalizeForParsing(body);
    final compacted = compact(normalized);

    final lowerCompacted = compacted.toLowerCase();
    final isOtp = _otpKeywords.any(lowerCompacted.contains) ||
        _otpCodeRe.hasMatch(normalized);
    final isReminder = _reminderKeywords.any(compacted.contains);

    // قدم ۲: استخراج فیلدها
    final kind = _detectKind(compacted);
    final balance = _extractBalance(normalized);
    final amountResult = _extractAmount(normalized, balance);
    final cardLast4 = _extractCardLast4(normalized);
    final accountRef = _accountRe.firstMatch(normalized)?.group(1);
    final occurredAt = extractOccurredAt(normalized);
    final counterparty = _extractCounterparty(normalized, kind);

    // بانکِ ناشناخته دلیل بازبینی نیست؛ فقط ابهام واقعی در مبلغ/نوع/موفقیت.
    final reviewReasons = [
      if (amountResult.amountRial == null) ReviewReason.amount,
      if (kind == TxKind.unknown) ReviewReason.kind,
      if (_failedKeywords.any(compacted.contains)) ReviewReason.failed,
    ];
    final needsReview = reviewReasons.isNotEmpty;

    return ParsedTransaction(
      rawSender: sender,
      rawBody: body,
      bankId: bank?.id,
      bankName: bank?.name,
      kind: kind,
      amountRial: amountResult.amountRial,
      rawAmount: amountResult.rawAmount,
      rawUnit: amountResult.unit,
      balanceAfterRial: balance,
      cardLast4: cardLast4,
      accountRef: accountRef,
      counterparty: counterparty,
      occurredAt: occurredAt,
      needsReview: needsReview,
      reviewReasons: reviewReasons,
      isOtp: isOtp,
      isReminder: isReminder,
    );
  }

  String? _extractCounterparty(String normalized, TxKind kind) {
    final reason = _reasonRe.firstMatch(normalized)?.group(1)?.trim();
    if (reason != null && reason.isNotEmpty) return reason;

    // «به کارت …» در واریز، کارتِ خودِ ماست نه طرف حساب.
    final dest = kind == TxKind.income ? null : _destCardRe.firstMatch(normalized);
    if (dest != null) {
      final digits =
          _fourDigitsRe.allMatches(dest.group(1)!).map((e) => e.group(0)!).toList();
      if (digits.isNotEmpty) return 'کارت مقصد ${digits.last}';
    }

    final merchant = _merchantRe.firstMatch(normalized)?.group(1)?.trim();
    if (merchant != null && merchant.isNotEmpty) return merchant;

    return null;
  }

  TxKind _detectKind(String compacted) {
    for (final k in _transferKeywords) {
      if (compacted.contains(k)) return TxKind.transfer;
    }
    for (final k in _expenseKeywords) {
      if (compacted.contains(k)) return TxKind.expense;
    }
    for (final k in _incomeKeywords) {
      if (compacted.contains(k)) return TxKind.income;
    }
    return TxKind.unknown;
  }

  int? _extractBalance(String normalized) {
    final m = _balanceRe.firstMatch(normalized);
    return m == null ? null : parseIntSafe(m.group(1));
  }

  _AmountResult _extractAmount(String normalized, int? balance) {
    int? amount;
    String? rawAmount;
    String unit = 'rial';

    // اولویت با مبلغ برچسب‌دار «مبلغ ...»
    final labeled = _amountLabeledRe.firstMatch(normalized);
    if (labeled != null) {
      rawAmount = labeled.group(1);
      amount = parseIntSafe(rawAmount);
    }

    // پیمایش مبالغ همراه با واحد پول، برای یافتن واحد و مقدار جایگزین.
    for (final m in _currencyRe.allMatches(normalized)) {
      final val = parseIntSafe(m.group(1));
      final currency = m.group(2); // ریال | تومان
      if (val == null) continue;

      if (amount == null) {
        // مبلغِ برچسب‌دار نبود؛ اولین مبلغی که مانده نیست را بردار.
        if (val != balance) {
          amount = val;
          rawAmount = m.group(1);
          unit = currency == 'تومان' ? 'toman' : 'rial';
        }
      } else if (val == amount) {
        // واحدِ همان مبلغ برچسب‌دار را مشخص کن.
        unit = currency == 'تومان' ? 'toman' : 'rial';
      }
    }

    // Fallback: مبلغِ چسبیده به فعل، بدون واحد (مثل «برداشت13,625,000»).
    if (amount == null) {
      final m = _amountAfterActionRe.firstMatch(normalized);
      if (m != null) {
        final val = parseIntSafe(m.group(1));
        if (val != null && val != balance) {
          amount = val;
          rawAmount = m.group(1);
        }
      }
    }

    // تبدیل تومان به ریال (کانونی).
    if (unit == 'toman' && amount != null) {
      amount = amount * 10;
    }

    return _AmountResult(amountRial: amount, rawAmount: rawAmount, unit: unit);
  }

  String? _extractCardLast4(String normalized) {
    final m = _cardRe.firstMatch(normalized);
    if (m == null) return null;
    final token = m.group(1)!;
    final groups = _fourDigitsRe.allMatches(token).map((e) => e.group(0)!).toList();
    return groups.isEmpty ? null : groups.last; // چهار رقم آخر
  }
}

class _AmountResult {
  final int? amountRial;
  final String? rawAmount;
  final String unit;
  const _AmountResult({this.amountRial, this.rawAmount, required this.unit});
}
