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
import 'models.dart';

class SmsParser {
  const SmsParser();

  // کلیدواژه‌ها به‌صورت فشرده (بدون فاصله) چون فاصله‌گذاری متغیر است.
  static const _transferKeywords = ['کارتبهکارت', 'حواله'];
  static const _expenseKeywords = ['برداشت', 'خرید', 'پرداخت', 'کسر', 'انتقالوجه', 'انتقال'];
  static const _incomeKeywords = ['واریز', 'عودت', 'افزایش'];

  static final _balanceRe = RegExp(r'(?:مانده|موجودی)\s*:?\s*([0-9][0-9,]*)');
  static final _amountLabeledRe = RegExp(r'مبلغ\s*:?\s*([0-9][0-9,]*)');
  static final _currencyRe = RegExp(r'([0-9][0-9,]*)\s*(ریال|تومان)');
  static final _cardRe = RegExp(r'کارت\s*:?\s*([0-9x\*\.\-]{4,})');
  static final _fourDigitsRe = RegExp(r'[0-9]{4}');

  ParsedTransaction parse({required String sender, required String body}) {
    // قدم ۱: تشخیص بانک
    final bank = detectBank(sender);

    final normalized = normalizeForParsing(body);
    final compacted = compact(normalized);

    // قدم ۲: استخراج فیلدها
    final kind = _detectKind(compacted);
    final balance = _extractBalance(normalized);
    final amountResult = _extractAmount(normalized, balance);
    final cardLast4 = _extractCardLast4(normalized);

    final needsReview =
        amountResult.amountRial == null || kind == TxKind.unknown || bank == null;

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
      needsReview: needsReview,
    );
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
