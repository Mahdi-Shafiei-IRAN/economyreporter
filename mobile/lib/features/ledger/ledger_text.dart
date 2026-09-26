/// متن‌های صفحه‌های نسخه‌ی ۲ و ورودیِ مبلغ.
library;

import '../../core/format/money_format.dart';
import '../../core/ledger/models.dart';
import '../../core/ledger/suggestion.dart';
import '../../core/sms/bank_registry.dart';
import '../../core/sms/digit_utils.dart';

String kindLabel(EntryKind? k) => switch (k) {
      EntryKind.income => 'واریز',
      EntryKind.expense => 'برداشت',
      null => 'جهت؟',
    };

/// «چرا این حساب» — هر پیشنهاد دلیلش را کنارش نشان می‌دهد (طرح ۱۳).
String? accountReasonText(String? reason) => switch (reason) {
      AccountReason.number => 'چون شماره‌ی حساب/کارت در پیامک بود',
      AccountReason.onlyAccount => 'تنها حسابِ این بانک',
      AccountReason.balance => 'چون مانده‌ی پیامک با همین حساب جور است',
      _ => null,
    };

String? notTxText(String? reason) => switch (reason) {
      NotTxReason.otp => 'رمزِ یک‌بارمصرف است، تراکنش نیست',
      NotTxReason.reminder => 'یادآوری/سررسید است، تراکنش نیست',
      NotTxReason.failed => 'تراکنش ناموفق بوده',
      NotTxReason.noAmount => 'مبلغی در پیامک پیدا نشد',
      NotTxReason.noAccount => 'نه بانک دارد نه شماره‌ی حساب (مثلاً اعتبارِ کیف پول)',
      NotTxReason.archived => 'مالِ حسابِ کنارگذاشته است',
      _ => null,
    };

String accountTitle(LedgerAccount a) => a.label.isEmpty ? a.ownerName : a.label;

/// «مهدی • بانک ملت • حساب ۱۰۰۰۰۰۵۵۹۶»
String accountSubtitle(LedgerAccount a) => [
      a.ownerName,
      if (a.bankId != null) bankNameById(a.bankId!) else 'نقد / بدون بانک',
      if (a.cardLast4 != null) 'کارت ${toPersianDigits(a.cardLast4!)}',
      if (a.accountRef != null) 'حساب ${toPersianDigits(a.accountRef!)}',
    ].join(' • ');

/// مبلغِ تومانیِ تایپ‌شده (ارقام فارسی/لاتین، با یا بی جداکننده) → ریال. خالی/نامعتبر = null.
int? parseTomanInput(String text) {
  final t = normalizeDigits(text).trim();
  final negative = t.startsWith('-') || t.startsWith('−');
  final digits = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  final toman = int.tryParse(digits);
  if (toman == null) return null;
  return (negative ? -toman : toman) * 10;
}

/// مقدارِ اولیه‌ی فیلدِ تومانی از ریال: «۱۲۰٬۰۰۰».
String tomanInputText(int? rial) => rial == null ? '' : formatToman(rial, withUnit: false);
