/// مدل‌های خروجی پارسر پیامک.
library;

/// نوع تراکنش. `transfer` = جابه‌جایی داخلی (کارت‌به‌کارت/حواله) که در جمع
/// درآمد/هزینه شمرده نمی‌شود. `unknown` یعنی پارسر نتوانست نوع را تشخیص دهد.
enum TxKind { income, expense, transfer, unknown }

/// نتیجه‌ی پارس یک پیامک. مبلغ کانونی همیشه به **ریال** (عدد صحیح) است.
class ParsedTransaction {
  /// شناسه‌ی بانک (از رجیستری) — null یعنی بانک از روی فرستنده شناخته نشد.
  final String? bankId;

  /// نام نمایشی بانک.
  final String? bankName;

  final TxKind kind;

  /// مبلغ کانونی به ریال.
  final int? amountRial;

  /// مبلغ همان‌طور که در پیامک آمده بود (برای audit).
  final String? rawAmount;

  /// واحد منبع همان‌طور که در پیامک آمده بود: `rial` یا `toman`.
  final String rawUnit;

  /// مانده‌ی حساب پس از تراکنش، به ریال (اگر در پیامک بود).
  final int? balanceAfterRial;

  /// چهار رقم آخر کارت (اگر تشخیص داده شد).
  final String? cardLast4;

  /// شماره‌ی حساب (اگر پیامک حساب‌محور بود؛ برای تطبیق مانده استفاده می‌شود).
  final String? accountRef;

  /// طرف حساب/پذیرنده (نام فروشگاه/پایانه یا کارت مقصد).
  final String? counterparty;

  /// زمانِ رخداد استخراج‌شده از پیامک (UTC)، اگر تاریخ در متن بود.
  final DateTime? occurredAt;

  /// فرستنده‌ی خام پیامک.
  final String rawSender;

  /// متن خام پیامک (فقط روی دستگاه؛ هرگز به سرور/لاگ نمی‌رود).
  final String rawBody;

  /// نیازمند بازبینی انسان: بانک ناشناخته، مبلغ استخراج‌نشده، یا نوع نامشخص.
  final bool needsReview;

  /// پیامک رمز پویا/یکبارمصرف است (نباید تراکنش حساب شود).
  final bool isOtp;

  /// آیا این پیامک واقعاً یک تراکنش است؟ (برای خواندن خودکار پیامک).
  bool get looksLikeTransaction =>
      !isOtp && amountRial != null && kind != TxKind.unknown;

  const ParsedTransaction({
    required this.rawSender,
    required this.rawBody,
    required this.kind,
    required this.needsReview,
    this.bankId,
    this.bankName,
    this.amountRial,
    this.rawAmount,
    this.rawUnit = 'rial',
    this.balanceAfterRial,
    this.cardLast4,
    this.accountRef,
    this.counterparty,
    this.occurredAt,
    this.isOtp = false,
  });

  @override
  String toString() =>
      'ParsedTransaction(bank: $bankId, kind: $kind, amountRial: $amountRial, '
      'balance: $balanceAfterRial, card: $cardLast4, review: $needsReview)';
}
