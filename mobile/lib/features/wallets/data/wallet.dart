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
