/// «کیف»: یک کارت یا حساب متعلق به یک عضو خانواده (نام صاحب + برچسب).
library;

class Wallet {
  final String id;
  final String ownerName; // مثلاً «بابا»، «مامان»، «من»

  /// شناسه‌ی کاربرِ صاحب در سرور (اگر عضو خانواده حساب کاربری دارد).
  /// فقط همین کاربر تراکنش‌های این کارت را ویرایش/دسته‌بندی می‌کند.
  final String? ownerUserId;
  final String label; // مثلاً «کارت حقوق»، «حساب پس‌انداز»
  final String? bankId;
  final String? cardLast4;
  final String? accountRef;

  const Wallet({
    required this.id,
    required this.ownerName,
    required this.label,
    this.ownerUserId,
    this.bankId,
    this.cardLast4,
    this.accountRef,
  });

  /// شماره‌ی کارت یا حساب دارد؟ (کیفِ «فقط بانک» برای پیامک‌های بی‌شماره است.)
  bool get hasDigits =>
      (cardLast4?.isNotEmpty ?? false) || (accountRef?.isNotEmpty ?? false);

  /// آیا این کیف با کارت/حساب یک تراکنش می‌خواند؟
  /// اگر بانک هر دو معلوم باشد باید یکی باشد (دو کارت با ۴ رقم یکسان در دو بانک).
  bool matches({String? cardLast4, String? accountRef, String? bankId}) {
    if (this.bankId != null &&
        this.bankId!.isNotEmpty &&
        bankId != null &&
        this.bankId != bankId) {
      return false;
    }
    if (this.cardLast4 != null &&
        this.cardLast4!.isNotEmpty &&
        this.cardLast4 == cardLast4) {
      return true;
    }
    if (this.accountRef != null &&
        this.accountRef!.isNotEmpty &&
        this.accountRef == accountRef) {
      return true;
    }
    return false;
  }

  /// شماره‌ی کارت/حسابِ این کیف با شماره‌ای که خودِ پیامک دارد تضاد دارد؟
  bool _conflicts({String? cardLast4, String? accountRef}) =>
      ((this.cardLast4?.isNotEmpty ?? false) &&
          (cardLast4?.isNotEmpty ?? false) &&
          this.cardLast4 != cardLast4) ||
      ((this.accountRef?.isNotEmpty ?? false) &&
          (accountRef?.isNotEmpty ?? false) &&
          this.accountRef != accountRef);

  Wallet copyWith({
    String? ownerName,
    String? ownerUserId,
    bool clearOwnerUserId = false,
    String? label,
    String? bankId,
    String? cardLast4,
    String? accountRef,
  }) =>
      Wallet(
        id: id,
        ownerName: ownerName ?? this.ownerName,
        ownerUserId: clearOwnerUserId ? null : (ownerUserId ?? this.ownerUserId),
        label: label ?? this.label,
        bankId: bankId ?? this.bankId,
        cardLast4: cardLast4 ?? this.cardLast4,
        accountRef: accountRef ?? this.accountRef,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'owner_name': ownerName,
        'owner_user_id': ownerUserId,
        'label': label,
        'bank_id': bankId,
        'card_last4': cardLast4,
        'account_ref': accountRef,
      };

  factory Wallet.fromMap(Map<String, Object?> m) => Wallet(
        id: m['id'] as String,
        ownerName: m['owner_name'] as String,
        ownerUserId: m['owner_user_id'] as String?,
        label: m['label'] as String,
        bankId: m['bank_id'] as String?,
        cardLast4: m['card_last4'] as String?,
        accountRef: m['account_ref'] as String?,
      );
}

/// کیفِ صاحبِ یک تراکنش. پیامکِ بیشتر بانک‌ها شماره‌ی کارت ندارد (حساب دارد یا هیچ)،
/// پس به‌ترتیب:
///  ۱) کارت یا حسابِ همان شماره؛
///  ۲) کیفِ «فقط بانک»ِ همان بانک (اگر فقط یکی باشد)؛
///  ۳) تنها کیفِ آن بانک که شماره‌اش با پیامک تضاد ندارد.
/// اگر چند کیف ممکن بماند null (نامشخص)، تا اشتباهی به کسی نسبت داده نشود.
Wallet? walletFor(
  Iterable<Wallet> wallets, {
  String? cardLast4,
  String? accountRef,
  String? bankId,
}) {
  for (final w in wallets) {
    if (w.matches(cardLast4: cardLast4, accountRef: accountRef, bankId: bankId)) return w;
  }
  if (bankId == null || bankId.isEmpty) return null;
  final sameBank = [
    for (final w in wallets)
      if (w.bankId == bankId && !w._conflicts(cardLast4: cardLast4, accountRef: accountRef))
        w,
  ];
  final bankOnly = sameBank.where((w) => !w.hasDigits).toList();
  if (bankOnly.length == 1) return bankOnly.single;
  return sameBank.length == 1 ? sameBank.single : null;
}
