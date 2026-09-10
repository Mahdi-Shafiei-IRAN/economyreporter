/// مدل ردیف تراکنش در پایگاه‌داده‌ی محلی + نگاشت از/به Map و از ParsedTransaction.
library;

import '../../../core/sms/models.dart';

class TransactionRecord {
  final String id;
  final String? bankId;

  /// income | expense | transfer | unknown
  final String kind;

  /// مبلغ کانونی به ریال.
  final int? amountRial;
  final int? balanceAfterRial;
  final String? rawAmount;
  final String rawUnit;
  final String? cardLast4;

  /// شماره‌ی حساب (محلی؛ برای تطبیق مانده). به سرور فرستاده نمی‌شود.
  final String? accountRef;
  final String? counterparty;
  final String? description;

  /// زمان واقعی رخداد (از پیامک) — فعلاً null تا پارس تاریخ اضافه شود.
  final DateTime? transactionDate;

  /// زمان ساخت روی دستگاه.
  final DateTime? clientCreatedAt;

  /// sms | manual | notification
  final String source;
  final String? sourceMessageHash;
  final String? deviceId;
  final bool needsReview;

  /// pending | syncing | synced | failed
  final String syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TransactionRecord({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    this.bankId,
    this.amountRial,
    this.balanceAfterRial,
    this.rawAmount,
    this.rawUnit = 'rial',
    this.cardLast4,
    this.accountRef,
    this.counterparty,
    this.description,
    this.transactionDate,
    this.clientCreatedAt,
    this.source = 'sms',
    this.sourceMessageHash,
    this.deviceId,
    this.needsReview = false,
    this.syncStatus = 'pending',
  });

  /// ساخت از خروجی پارسر پیامک.
  factory TransactionRecord.fromParsed(
    ParsedTransaction parsed, {
    required String id,
    required DateTime now,
    String? sourceMessageHash,
    String? deviceId,
  }) {
    return TransactionRecord(
      id: id,
      bankId: parsed.bankId,
      kind: parsed.kind.name,
      amountRial: parsed.amountRial,
      balanceAfterRial: parsed.balanceAfterRial,
      rawAmount: parsed.rawAmount,
      rawUnit: parsed.rawUnit,
      cardLast4: parsed.cardLast4,
      accountRef: parsed.accountRef,
      counterparty: parsed.counterparty,
      transactionDate: parsed.occurredAt,
      clientCreatedAt: now,
      source: 'sms',
      sourceMessageHash: sourceMessageHash,
      deviceId: deviceId,
      needsReview: parsed.needsReview,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'bank_id': bankId,
        'kind': kind,
        'amount_rial': amountRial,
        'balance_after_rial': balanceAfterRial,
        'raw_amount': rawAmount,
        'raw_unit': rawUnit,
        'card_last4': cardLast4,
        'account_ref': accountRef,
        'counterparty': counterparty,
        'description': description,
        'transaction_date': transactionDate?.toIso8601String(),
        'client_created_at': clientCreatedAt?.toIso8601String(),
        'source': source,
        'source_message_hash': sourceMessageHash,
        'device_id': deviceId,
        'needs_review': needsReview ? 1 : 0,
        'sync_status': syncStatus,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// زمان مؤثر برای مرتب‌سازی/تطبیق: زمان رخداد، وگرنه زمان ساخت روی دستگاه.
  DateTime get effectiveTime => transactionDate ?? clientCreatedAt ?? createdAt;

  /// نسخه‌ی جدید با فیلدهای ویرایش‌شده (بقیه ثابت).
  TransactionRecord copyWith({
    String? kind,
    int? amountRial,
    String? counterparty,
    String? description,
    bool? needsReview,
    String? syncStatus,
    DateTime? updatedAt,
  }) {
    return TransactionRecord(
      id: id,
      bankId: bankId,
      kind: kind ?? this.kind,
      amountRial: amountRial ?? this.amountRial,
      balanceAfterRial: balanceAfterRial,
      rawAmount: rawAmount,
      rawUnit: rawUnit,
      cardLast4: cardLast4,
      accountRef: accountRef,
      counterparty: counterparty ?? this.counterparty,
      description: description ?? this.description,
      transactionDate: transactionDate,
      clientCreatedAt: clientCreatedAt,
      source: source,
      sourceMessageHash: sourceMessageHash,
      deviceId: deviceId,
      needsReview: needsReview ?? this.needsReview,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// payload برای endpoint سرور (`POST /sync/transactions/`).
  /// حساب/کارت/دسته فعلاً ارسال نمی‌شوند (در فاز بازبینی لینک می‌شوند).
  Map<String, Object?> toSyncPayload() => {
        'id': id,
        'kind': kind,
        'amount_rial': amountRial,
        'balance_after_rial': balanceAfterRial,
        'raw_amount': rawAmount,
        'raw_unit': rawUnit,
        'counterparty': counterparty,
        'description': description ?? '',
        'source': source,
        'source_message_hash': sourceMessageHash ?? '',
        'device_id': deviceId ?? '',
        'needs_review': needsReview,
        'transaction_date': transactionDate?.toIso8601String(),
        'client_created_at': clientCreatedAt?.toIso8601String(),
      };

  factory TransactionRecord.fromMap(Map<String, Object?> map) {
    DateTime? parseDate(Object? v) =>
        v == null ? null : DateTime.parse(v as String);
    return TransactionRecord(
      id: map['id'] as String,
      bankId: map['bank_id'] as String?,
      kind: map['kind'] as String,
      amountRial: map['amount_rial'] as int?,
      balanceAfterRial: map['balance_after_rial'] as int?,
      rawAmount: map['raw_amount'] as String?,
      rawUnit: (map['raw_unit'] as String?) ?? 'rial',
      cardLast4: map['card_last4'] as String?,
      accountRef: map['account_ref'] as String?,
      counterparty: map['counterparty'] as String?,
      description: map['description'] as String?,
      transactionDate: parseDate(map['transaction_date']),
      clientCreatedAt: parseDate(map['client_created_at']),
      source: (map['source'] as String?) ?? 'sms',
      sourceMessageHash: map['source_message_hash'] as String?,
      deviceId: map['device_id'] as String?,
      needsReview: (map['needs_review'] as int? ?? 0) == 1,
      syncStatus: (map['sync_status'] as String?) ?? 'pending',
      createdAt: parseDate(map['created_at'])!,
      updatedAt: parseDate(map['updated_at'])!,
    );
  }
}
