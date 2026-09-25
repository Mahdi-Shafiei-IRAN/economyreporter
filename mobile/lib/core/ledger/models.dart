/// مدل‌های دفترِ حسابِ نسخه‌ی ۲ (docs/v2-design.md بخش ۴).
library;

enum EntryKind { income, expense }

enum EntrySource { sms, manual, adjustment }

enum SmsStatus { pending, accepted, rejected }

enum RejectReason {
  notTx('not_tx'),
  duplicate('duplicate'),
  other('other');

  const RejectReason(this.code);
  final String code;

  static RejectReason fromCode(String code) => values.firstWhere((r) => r.code == code);
}

String _iso(DateTime t) => t.toUtc().toIso8601String();
DateTime _time(Object? v) => DateTime.parse(v! as String).toUtc();
DateTime? _timeOrNull(Object? v) => v == null ? null : DateTime.parse(v as String).toUtc();
String? _blankToNull(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

/// حساب = همان کیف (`wallets`) + `archived`.
class LedgerAccount {
  final String id;
  final String ownerName;
  final String? ownerUserId;
  final String label;
  final String? bankId;
  final String? cardLast4;
  final String? accountRef;
  final bool archived;

  const LedgerAccount({
    required this.id,
    required this.ownerName,
    required this.label,
    this.ownerUserId,
    this.bankId,
    this.cardLast4,
    this.accountRef,
    this.archived = false,
  });

  bool get hasNumber => cardLast4 != null || accountRef != null;

  factory LedgerAccount.fromWalletRow(Map<String, Object?> m) => LedgerAccount(
        id: m['id']! as String,
        ownerName: m['owner_name']! as String,
        ownerUserId: m['owner_user_id'] as String?,
        label: m['label']! as String,
        bankId: m['bank_id'] as String?,
        cardLast4: _blankToNull(m['card_last4'] as String?),
        accountRef: _blankToNull(m['account_ref'] as String?),
        archived: (m['archived'] as int? ?? 0) == 1,
      );
}

/// تراکنشِ دفتر؛ فقط با کارِ کاربر ساخته می‌شود (I1).
class Entry {
  final String id;
  final String accountId;
  final EntryKind kind;
  final bool isTransfer;
  final String? transferPairId;
  final int amountRial;
  final DateTime occurredAt;

  /// مانده‌ی بانک بعد از همین تراکنش (از پیامک) = نقطه‌ی مانده‌ی بانکی.
  final int? bankBalanceAfter;
  final EntrySource source;
  final String? smsKey;
  final String? note;
  final String? createdByDevice;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Entry({
    required this.id,
    required this.accountId,
    required this.kind,
    required this.amountRial,
    required this.occurredAt,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.isTransfer = false,
    this.transferPairId,
    this.bankBalanceAfter,
    this.smsKey,
    this.note,
    this.createdByDevice,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;
  int get signed => kind == EntryKind.income ? amountRial : -amountRial;

  Entry copyWith({
    String? accountId,
    EntryKind? kind,
    bool? isTransfer,
    int? amountRial,
    DateTime? occurredAt,
    String? note,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      Entry(
        id: id,
        accountId: accountId ?? this.accountId,
        kind: kind ?? this.kind,
        isTransfer: isTransfer ?? this.isTransfer,
        transferPairId: transferPairId,
        amountRial: amountRial ?? this.amountRial,
        occurredAt: occurredAt ?? this.occurredAt,
        bankBalanceAfter: bankBalanceAfter,
        source: source,
        smsKey: smsKey,
        note: note ?? this.note,
        createdByDevice: createdByDevice,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'kind': kind.name,
        'is_transfer': isTransfer ? 1 : 0,
        'transfer_pair_id': transferPairId,
        'amount_rial': amountRial,
        'occurred_at': _iso(occurredAt),
        'bank_balance_after': bankBalanceAfter,
        'source': source.name,
        'sms_key': smsKey,
        'note': note,
        'created_by_device': createdByDevice,
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
        'deleted_at': deletedAt == null ? null : _iso(deletedAt!),
      };

  factory Entry.fromMap(Map<String, Object?> m) => Entry(
        id: m['id']! as String,
        accountId: m['account_id']! as String,
        kind: EntryKind.values.byName(m['kind']! as String),
        isTransfer: (m['is_transfer'] as int? ?? 0) == 1,
        transferPairId: m['transfer_pair_id'] as String?,
        amountRial: m['amount_rial']! as int,
        occurredAt: _time(m['occurred_at']),
        bankBalanceAfter: m['bank_balance_after'] as int?,
        source: EntrySource.values.byName(m['source']! as String),
        smsKey: m['sms_key'] as String?,
        note: m['note'] as String?,
        createdByDevice: m['created_by_device'] as String?,
        createdAt: _time(m['created_at']),
        updatedAt: _time(m['updated_at']),
        deletedAt: _timeOrNull(m['deleted_at']),
      );
}

/// نقطه‌ی مانده‌ی **دستی** (لنگر / تطبیق با موجودیِ واقعی). نقطه‌ی بانکی ذخیره نمی‌شود؛
/// از [Entry.bankBalanceAfter] مشتق می‌شود.
class Checkpoint {
  final String id;
  final String accountId;
  final DateTime at;
  final int balanceRial;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const Checkpoint({
    required this.id,
    required this.accountId,
    required this.at,
    required this.balanceRial,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.deletedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'account_id': accountId,
        'at': _iso(at),
        'balance_rial': balanceRial,
        'note': note,
        'created_at': _iso(createdAt),
        'updated_at': _iso(updatedAt),
        'deleted_at': deletedAt == null ? null : _iso(deletedAt!),
      };

  factory Checkpoint.fromMap(Map<String, Object?> m) => Checkpoint(
        id: m['id']! as String,
        accountId: m['account_id']! as String,
        at: _time(m['at']),
        balanceRial: m['balance_rial']! as int,
        note: m['note'] as String?,
        createdAt: _time(m['created_at']),
        updatedAt: _time(m['updated_at']),
        deletedAt: _timeOrNull(m['deleted_at']),
      );
}

/// پیشنهادِ برنامه برای یک پیامک؛ فقط پیشنهاد، هرگز خودکار ثبت نمی‌شود (ت۲).
class SmsSuggestion {
  /// null = جهت معلوم نیست (کاربر هنگامِ ثبت انتخاب می‌کند).
  final EntryKind? kind;
  final int? amountRial;
  final int? balanceRial;
  final DateTime? occurredAt;
  final String? accountId;

  /// چرا این حساب (`AccountReason`).
  final String? accountReason;

  /// null = شکلِ تراکنش دارد؛ وگرنه دلیلِ «تراکنش نیست» (`NotTxReason`).
  final String? notTxReason;
  final bool likelyDuplicate;

  /// شماره‌ی کارت/حسابِ داخلِ پیامک با هیچ حسابی نمی‌خواند («حسابِ تازه است؟»).
  final bool unknownAccountNumber;

  const SmsSuggestion({
    this.kind,
    this.amountRial,
    this.balanceRial,
    this.occurredAt,
    this.accountId,
    this.accountReason,
    this.notTxReason,
    this.likelyDuplicate = false,
    this.unknownAccountNumber = false,
  });

  bool get looksLikeTx => notTxReason == null;

  Map<String, Object?> toColumns() => {
        'sugg_kind': kind?.name,
        'sugg_amount': amountRial,
        'sugg_balance': balanceRial,
        'sugg_occurred_at': occurredAt == null ? null : _iso(occurredAt!),
        'sugg_account_id': accountId,
        'sugg_account_reason': accountReason,
        'sugg_not_tx': notTxReason,
        'sugg_duplicate': likelyDuplicate ? 1 : 0,
        'sugg_new_account': unknownAccountNumber ? 1 : 0,
      };

  factory SmsSuggestion.fromColumns(Map<String, Object?> m) => SmsSuggestion(
        kind: m['sugg_kind'] == null ? null : EntryKind.values.byName(m['sugg_kind']! as String),
        amountRial: m['sugg_amount'] as int?,
        balanceRial: m['sugg_balance'] as int?,
        occurredAt: _timeOrNull(m['sugg_occurred_at']),
        accountId: m['sugg_account_id'] as String?,
        accountReason: m['sugg_account_reason'] as String?,
        notTxReason: m['sugg_not_tx'] as String?,
        likelyDuplicate: (m['sugg_duplicate'] as int? ?? 0) == 1,
        unknownAccountNumber: (m['sugg_new_account'] as int? ?? 0) == 1,
      );
}

/// تصمیمِ کاربر روی یک پیامک، همان‌طور که روی سرور می‌رود: **بدونِ متن و فرستنده** (I6).
class SmsDecision {
  final String key;
  final String contentHash;
  final DateTime receivedAt;
  final SmsStatus status;
  final RejectReason? rejectReason;
  final String? entryId;
  final DateTime? decidedAt;

  const SmsDecision({
    required this.key,
    required this.contentHash,
    required this.receivedAt,
    required this.status,
    this.rejectReason,
    this.entryId,
    this.decidedAt,
  });

  Map<String, Object?> toPayload() => {
        'key': key,
        'content_hash': contentHash,
        'received_at': _iso(receivedAt),
        'status': status.name,
        'reject_reason': rejectReason?.code,
        'entry_id': entryId,
        'decided_at': decidedAt == null ? null : _iso(decidedAt!),
      };

  factory SmsDecision.fromPayload(Map<String, Object?> m) => SmsDecision(
        key: m['key']! as String,
        contentHash: m['content_hash']! as String,
        receivedAt: _time(m['received_at']),
        status: SmsStatus.values.byName(m['status']! as String),
        rejectReason:
            m['reject_reason'] == null ? null : RejectReason.fromCode(m['reject_reason']! as String),
        entryId: m['entry_id'] as String?,
        decidedAt: _timeOrNull(m['decided_at']),
      );
}

/// یک پیامکِ فرستنده‌ی مجاز بعد از تاریخِ شروع. متن فقط روی گوشی است.
class SmsItem {
  final String key;
  final String contentHash;
  final String sender;
  final DateTime receivedAt;
  final String? body;
  final SmsSuggestion suggestion;
  final SmsStatus status;
  final String? entryId;
  final RejectReason? rejectReason;
  final DateTime? decidedAt;
  final int parserVersion;

  const SmsItem({
    required this.key,
    required this.contentHash,
    required this.sender,
    required this.receivedAt,
    required this.suggestion,
    required this.parserVersion,
    this.body,
    this.status = SmsStatus.pending,
    this.entryId,
    this.rejectReason,
    this.decidedAt,
  });

  SmsDecision get decision => SmsDecision(
        key: key,
        contentHash: contentHash,
        receivedAt: receivedAt,
        status: status,
        rejectReason: rejectReason,
        entryId: entryId,
        decidedAt: decidedAt,
      );

  SmsItem _copy({String? body, SmsSuggestion? suggestion, int? parserVersion}) => SmsItem(
        key: key,
        contentHash: contentHash,
        sender: sender,
        receivedAt: receivedAt,
        body: body ?? this.body,
        suggestion: suggestion ?? this.suggestion,
        status: status,
        entryId: entryId,
        rejectReason: rejectReason,
        decidedAt: decidedAt,
        parserVersion: parserVersion ?? this.parserVersion,
      );

  SmsItem withBody(String body) => _copy(body: body);

  SmsItem withSuggestion(SmsSuggestion suggestion, int parserVersion) =>
      _copy(suggestion: suggestion, parserVersion: parserVersion);

  Map<String, Object?> toMap() => {
        'key': key,
        'content_hash': contentHash,
        'sender': sender,
        'received_at': _iso(receivedAt),
        'body': body,
        ...suggestion.toColumns(),
        'status': status.name,
        'entry_id': entryId,
        'reject_reason': rejectReason?.code,
        'decided_at': decidedAt == null ? null : _iso(decidedAt!),
        'parser_version': parserVersion,
      };

  factory SmsItem.fromMap(Map<String, Object?> m) => SmsItem(
        key: m['key']! as String,
        contentHash: m['content_hash']! as String,
        sender: m['sender']! as String,
        receivedAt: _time(m['received_at']),
        body: m['body'] as String?,
        suggestion: SmsSuggestion.fromColumns(m),
        status: SmsStatus.values.byName(m['status']! as String),
        entryId: m['entry_id'] as String?,
        rejectReason:
            m['reject_reason'] == null ? null : RejectReason.fromCode(m['reject_reason']! as String),
        decidedAt: _timeOrNull(m['decided_at']),
        parserVersion: m['parser_version']! as int,
      );
}
