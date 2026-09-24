/// مدل ردیف تراکنش در پایگاه‌داده‌ی محلی + نگاشت از/به Map و از ParsedTransaction.
library;

import '../../../core/sms/models.dart';

/// سهمِ یک دسته از مبلغ تراکنش.
class Allocation {
  final String categoryName;
  final int amountRial;
  const Allocation(this.categoryName, this.amountRial);

  @override
  bool operator ==(Object other) =>
      other is Allocation &&
      other.categoryName == categoryName &&
      other.amountRial == amountRial;

  @override
  int get hashCode => Object.hash(categoryName, amountRial);
}

/// جداکننده‌های GROUP_CONCAT برای خواندن تخصیص‌ها در همان کوئری تراکنش.
final String kAllocFieldSep = String.fromCharCode(0x1F);
final String kAllocItemSep = String.fromCharCode(0x1E);

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

  /// زمان واقعی رخداد (از متن پیامک، اگر تاریخ داشت).
  final DateTime? transactionDate;

  /// زمان ساخت روی دستگاه.
  final DateTime? clientCreatedAt;

  /// sms | manual | notification
  final String source;
  final String? sourceMessageHash;
  final String? deviceId;
  final bool needsReview;

  /// کدهای ReviewReason (مبلغ/نوع نامشخص، احتمال ناموفق).
  final List<String> reviewReasons;

  /// pending | syncing | synced | failed
  final String syncStatus;
  final DateTime createdAt;

  /// زمان آخرین ویرایش کاربر (برای «آخرین ویرایش برنده است» در sync).
  final DateTime updatedAt;

  // --- فقط روی همین گوشی (هرگز sync یا لاگ نمی‌شود) ---
  final String? smsSender;
  final String? smsBody;

  /// زمان رسیدن پیامک به گوشی.
  final DateTime? smsReceivedAt;
  final String? smsContentHash;

  /// حذف نرم (تراکنش نامعتبر). ردیف می‌ماند تا پیامکش دوباره وارد نشود.
  final DateTime? deletedAt;

  // --- صاحب ---
  /// کاربرِ صاحب کارت در سرور؛ فقط او ویرایش/دسته‌بندی می‌کند.
  final String? ownerUserId;

  /// نام نمایشی صاحب (مثلاً «بابا»)؛ null یعنی کارت هنوز به کسی وصل نشده.
  final String? ownerName;
  final String? walletLabel;

  /// local = پیامکش روی همین گوشی آمده؛ remote = از گوشی عضو دیگر (سرور).
  final String origin;

  /// سهم دسته‌ها (خالی یعنی دسته‌بندی‌نشده).
  final List<Allocation> allocations;

  /// کیفی که کاربر دستی به این تراکنش چسبانده («تعیین کارت»)؛ null یعنی حدسِ خودکار.
  final String? pinnedWalletId;

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
    this.reviewReasons = const [],
    this.syncStatus = 'pending',
    this.smsSender,
    this.smsBody,
    this.smsReceivedAt,
    this.smsContentHash,
    this.deletedAt,
    this.ownerUserId,
    this.ownerName,
    this.walletLabel,
    this.origin = 'local',
    this.allocations = const [],
    this.pinnedWalletId,
  });

  /// ساخت از خروجی پارسر پیامک.
  factory TransactionRecord.fromParsed(
    ParsedTransaction parsed, {
    required String id,
    required DateTime now,
    String? sourceMessageHash,
    String? deviceId,
    DateTime? smsReceivedAt,
    String? smsContentHash,
    String? ownerUserId,
    String? ownerName,
    String? walletLabel,
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
      reviewReasons: parsed.reviewReasons,
      syncStatus: 'pending',
      createdAt: now,
      updatedAt: now,
      smsSender: parsed.rawSender,
      smsBody: parsed.rawBody,
      smsReceivedAt: smsReceivedAt?.toUtc(),
      smsContentHash: smsContentHash,
      ownerUserId: ownerUserId,
      ownerName: ownerName,
      walletLabel: walletLabel,
    );
  }

  bool get isDeleted => deletedAt != null;
  bool get isRemote => origin == 'remote';
  bool get isCategorized => allocations.isNotEmpty;

  /// زمان مؤثر برای مرتب‌سازی/بازه: زمان رخداد، وگرنه زمان رسیدن پیامک، وگرنه زمان ثبت.
  DateTime get effectiveTime =>
      transactionDate ?? smsReceivedAt ?? clientCreatedAt ?? createdAt;

  /// مبلغ علامت‌دار برای جمع: درآمد مثبت، هزینه منفی، بقیه صفر.
  int get signedAmount => switch (kind) {
        'income' => amountRial ?? 0,
        'expense' => -(amountRial ?? 0),
        _ => 0,
      };

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
        'transaction_date': transactionDate?.toUtc().toIso8601String(),
        'client_created_at': clientCreatedAt?.toUtc().toIso8601String(),
        'source': source,
        'source_message_hash': sourceMessageHash,
        'device_id': deviceId,
        'needs_review': needsReview ? 1 : 0,
        'review_reason': reviewReasons.isEmpty ? null : reviewReasons.join(','),
        'sync_status': syncStatus,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'sms_sender': smsSender,
        'sms_body': smsBody,
        'sms_received_at': smsReceivedAt?.toUtc().toIso8601String(),
        'sms_content_hash': smsContentHash,
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'owner_user_id': ownerUserId,
        'owner_name': ownerName,
        'wallet_label': walletLabel,
        'origin': origin,
      };

  /// نسخه‌ی جدید با فیلدهای ویرایش‌شده (بقیه ثابت).
  TransactionRecord copyWith({
    String? bankId,
    String? kind,
    int? amountRial,
    String? counterparty,
    String? description,
    bool? needsReview,
    List<String>? reviewReasons,
    String? syncStatus,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeleted = false,
    String? ownerUserId,
    String? ownerName,
    bool clearOwnerName = false,
    String? walletLabel,
    bool clearWalletLabel = false,
    List<Allocation>? allocations,
  }) {
    return TransactionRecord(
      id: id,
      bankId: bankId ?? this.bankId,
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
      reviewReasons: reviewReasons ?? this.reviewReasons,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      smsSender: smsSender,
      smsBody: smsBody,
      smsReceivedAt: smsReceivedAt,
      smsContentHash: smsContentHash,
      deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
      ownerUserId: ownerUserId ?? this.ownerUserId,
      ownerName: clearOwnerName ? null : (ownerName ?? this.ownerName),
      walletLabel: clearWalletLabel ? null : (walletLabel ?? this.walletLabel),
      origin: origin,
      allocations: allocations ?? this.allocations,
      pinnedWalletId: pinnedWalletId,
    );
  }

  /// payload برای endpoint سرور (`POST /sync/transactions/`).
  /// متن/فرستنده‌ی خام پیامک و شماره‌ی حساب هرگز فرستاده نمی‌شوند.
  /// رشته‌ها هیچ‌وقت null نیستند (سرور null را برای فیلد متنی رد می‌کرد).
  Map<String, Object?> toSyncPayload() => {
        'id': id,
        'kind': kind,
        'amount_rial': amountRial,
        'balance_after_rial': balanceAfterRial,
        'raw_amount': rawAmount ?? '',
        'raw_unit': rawUnit,
        'counterparty': counterparty ?? '',
        'description': description ?? '',
        'source': source,
        'source_message_hash': sourceMessageHash ?? '',
        'device_id': deviceId ?? '',
        'needs_review': needsReview,
        'transaction_date': (transactionDate ?? smsReceivedAt)?.toUtc().toIso8601String(),
        'client_created_at': clientCreatedAt?.toUtc().toIso8601String(),
        'client_updated_at': updatedAt.toUtc().toIso8601String(),
        'bank_id': bankId ?? '',
        'card_last4': cardLast4 ?? '',
        'owner_member': ownerUserId,
        'person_name': ownerName ?? '',
        'wallet_label': walletLabel ?? '',
        'allocations': [
          for (final a in allocations)
            {'name': a.categoryName, 'amount_rial': a.amountRial},
        ],
        'is_deleted': isDeleted,
      };

  factory TransactionRecord.fromMap(Map<String, Object?> map) {
    DateTime? parseDate(Object? v) =>
        v == null ? null : DateTime.parse(v as String);
    final reasons = (map['review_reason'] as String?) ?? '';
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
      reviewReasons: reasons.isEmpty ? const [] : reasons.split(','),
      syncStatus: (map['sync_status'] as String?) ?? 'pending',
      createdAt: parseDate(map['created_at'])!,
      updatedAt: parseDate(map['updated_at'])!,
      smsSender: map['sms_sender'] as String?,
      smsBody: map['sms_body'] as String?,
      smsReceivedAt: parseDate(map['sms_received_at']),
      smsContentHash: map['sms_content_hash'] as String?,
      deletedAt: parseDate(map['deleted_at']),
      ownerUserId: map['owner_user_id'] as String?,
      ownerName: map['owner_name'] as String?,
      walletLabel: map['wallet_label'] as String?,
      origin: (map['origin'] as String?) ?? 'local',
      allocations: _parseAllocations(map['alloc'] as String?),
      pinnedWalletId: map['pinned_wallet_id'] as String?,
    );
  }

  static List<Allocation> _parseAllocations(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final result = <Allocation>[];
    for (final item in raw.split(kAllocItemSep)) {
      final parts = item.split(kAllocFieldSep);
      if (parts.length != 2) continue;
      result.add(Allocation(parts[0], int.tryParse(parts[1]) ?? 0));
    }
    return result;
  }
}
