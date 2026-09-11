/// «کیف»: یک کارت یا حساب متعلق به یک عضو خانواده (نام صاحب + برچسب).
library;

class Wallet {
  final String id;
  final String ownerName; // مثلاً «بابا»، «مامان»، «من»
  final String label; // مثلاً «کارت حقوق»، «حساب پس‌انداز»
  final String? bankId;
  final String? cardLast4;
  final String? accountRef;

  const Wallet({
    required this.id,
    required this.ownerName,
    required this.label,
    this.bankId,
    this.cardLast4,
    this.accountRef,
  });

  /// آیا این کیف با کارت/حساب یک تراکنش می‌خواند؟
  bool matches({String? cardLast4, String? accountRef}) {
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

  Map<String, Object?> toMap() => {
        'id': id,
        'owner_name': ownerName,
        'label': label,
        'bank_id': bankId,
        'card_last4': cardLast4,
        'account_ref': accountRef,
      };

  factory Wallet.fromMap(Map<String, Object?> m) => Wallet(
        id: m['id'] as String,
        ownerName: m['owner_name'] as String,
        label: m['label'] as String,
        bankId: m['bank_id'] as String?,
        cardLast4: m['card_last4'] as String?,
        accountRef: m['account_ref'] as String?,
      );
}
