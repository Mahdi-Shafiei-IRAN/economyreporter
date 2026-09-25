# Ledger v2 — Phase 1 (pure core) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the v2 ledger core (`mobile/lib/core/ledger/`): models, balance/discrepancy math, suggestions, SMS intake, SQLite tables + repository — no UI, behind the `ledger_v2` flag, with unit tests for the core acceptance scenarios of `docs/v2-design.md` §12.

**Architecture:** Pure Dart functions (`ledger_math`, `suggestion`, `sms_intake`) operate on immutable models; `LedgerRepository` is the only code that touches the new tables, and the only entry-writing methods are explicit user actions (`acceptSms`, `addEntry`, `updateEntry`, `deleteEntry`) — invariant I1. Bank checkpoints are **derived** from `Entry.bankBalanceAfter` (not stored); only manual checkpoints are stored. The balance math works on a totally ordered list (`orderLedger`), never on raw timestamp comparison.

**Tech Stack:** Flutter 3.22.2 / Dart ≥3.4.3, sqflite (+ sqflite_common_ffi in tests), crypto, uuid 3.0.7.

## Global Constraints

- Reference spec: `docs/v2-design.md` (§4 models, §5 SMS flow, §6 balance/discrepancy, §11 phases, §12 scenarios). Invariants I1–I6 must hold.
- I1: no ledger entry is created/changed/deleted except by an explicit user-action method.
- I2: a decided SMS (`accepted`/`rejected`) is never changed automatically; newer parser only rewrites suggestions of `pending` items.
- I4: SMS received before the start date never enters `sms_items`.
- I6: raw SMS text/sender never appear in any server payload (`SmsDecision.toPayload`).
- Same-SMS rule: equal `content_hash` and `|Δreceived_at| ≤ 10 minutes`.
- Start date = first day of the current Jalali month (Iran time, UTC+3:30).
- Money: integer rial. Times: UTC `DateTime`, stored as ISO-8601 strings.
- No UI and no change to v1 behavior in this phase; v1 code stays untouched except `app_database.dart` (schema v11).
- Commits: directly on `main`, user as author, **no Co-Authored-By / assistant trailer** (project CLAUDE.md).
- Run tests from `mobile/`: `flutter test <path>`; analyzer: `flutter analyze`.

## File Structure

| File | Responsibility |
|---|---|
| `mobile/lib/core/ledger/models.dart` | `LedgerAccount`, `Entry`, `Checkpoint`, `SmsSuggestion`, `SmsDecision`, `SmsItem`, enums; DB map conversion |
| `mobile/lib/core/ledger/ledger_math.dart` | `LedgerItem`, `orderLedger`, `currentBalance`, `discrepancies`, `balanceAt` |
| `mobile/lib/core/ledger/suggestion.dart` | `SuggestionContext`, `suggest`, `analyzeWindow` |
| `mobile/lib/core/ledger/sms_intake.dart` | sender key, content hash, item key, same-SMS rule, start date, `intakeSms`, `resuggest` |
| `mobile/lib/core/ledger/ledger_schema.dart` | `createLedgerTables` |
| `mobile/lib/core/ledger/ledger_repository.dart` | settings (flag, start date), accounts, entries, checkpoints, sms items, user actions |
| `mobile/lib/core/database/app_database.dart` | schema v11: `wallets.archived` + ledger tables |
| `mobile/test/ledger/ledger_fixtures.dart` | test builders `entry`, `checkpoint`, `smsItem` |
| `mobile/test/ledger/*_test.dart` | tests per unit |

---

### Task 1: Models

**Files:**
- Create: `mobile/lib/core/ledger/models.dart`
- Test: `mobile/test/ledger/models_test.dart`

**Interfaces:**
- Produces: `enum EntryKind {income, expense}`, `enum EntrySource {sms, manual, adjustment}`, `enum SmsStatus {pending, accepted, rejected}`, `enum RejectReason {notTx('not_tx'), duplicate, other}` with `.code` / `RejectReason.fromCode`; classes `LedgerAccount` (`fromWalletRow`, `hasNumber`), `Entry` (`signed`, `isDeleted`, `copyWith`, `toMap`, `fromMap`), `Checkpoint` (`toMap`, `fromMap`), `SmsSuggestion` (`toColumns`, `fromColumns`, `looksLikeTx`), `SmsDecision` (`toPayload`, `fromPayload`), `SmsItem` (`decision`, `withBody`, `withSuggestion`, `toMap`, `fromMap`).

- [ ] **Step 1: Write the failing test** — `mobile/test/ledger/models_test.dart`

```dart
import 'package:economy/core/ledger/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = DateTime.utc(2026, 9, 23, 9, 35);

  test('Entry round-trips through a DB map and signs by kind', () {
    final e = Entry(
      id: 'e1',
      accountId: 'a1',
      kind: EntryKind.expense,
      amountRial: 1000,
      occurredAt: t,
      bankBalanceAfter: 9000,
      source: EntrySource.sms,
      smsKey: 'k1',
      createdAt: t,
      updatedAt: t,
    );
    final back = Entry.fromMap(e.toMap());
    expect(back.signed, -1000);
    expect(back.bankBalanceAfter, 9000);
    expect(back.source, EntrySource.sms);
    expect(back.occurredAt, t);
    expect(back.isDeleted, isFalse);
  });

  test('SmsItem round-trips with its suggestion', () {
    final item = SmsItem(
      key: 'h:1',
      contentHash: 'h',
      sender: 'Bank Mellat',
      receivedAt: t,
      body: 'متن',
      suggestion: SmsSuggestion(
        kind: EntryKind.income,
        amountRial: 5,
        balanceRial: 10,
        occurredAt: t,
        accountId: 'a1',
        accountReason: 'number',
        likelyDuplicate: true,
      ),
      status: SmsStatus.rejected,
      rejectReason: RejectReason.notTx,
      decidedAt: t,
      parserVersion: 4,
    );
    final back = SmsItem.fromMap(item.toMap());
    expect(back.suggestion.kind, EntryKind.income);
    expect(back.suggestion.likelyDuplicate, isTrue);
    expect(back.rejectReason, RejectReason.notTx);
    expect(back.status, SmsStatus.rejected);
    expect(back.body, 'متن');
  });

  test('scenario 14: decision payload has no SMS text or sender (I6)', () {
    final item = SmsItem(
      key: 'h:1',
      contentHash: 'h',
      sender: 'Bank Mellat',
      receivedAt: t,
      body: 'حساب1000005596 برداشت',
      suggestion: const SmsSuggestion(),
      status: SmsStatus.accepted,
      entryId: 'e1',
      decidedAt: t,
      parserVersion: 4,
    );
    final payload = item.decision.toPayload();
    expect(payload.keys.toSet(),
        {'key', 'content_hash', 'received_at', 'status', 'reject_reason', 'entry_id', 'decided_at'});
    final text = payload.values.join(' ');
    expect(text.contains('Mellat'), isFalse);
    expect(text.contains('1000005596'), isFalse);
    final back = SmsDecision.fromPayload(payload);
    expect(back.status, SmsStatus.accepted);
    expect(back.entryId, 'e1');
  });

  test('LedgerAccount reads a wallets row, blank numbers are null', () {
    final a = LedgerAccount.fromWalletRow({
      'id': 'w1',
      'owner_name': 'مهدی',
      'label': 'ملت',
      'bank_id': 'mellat',
      'card_last4': '',
      'account_ref': '1000005596',
      'archived': 1,
    });
    expect(a.cardLast4, isNull);
    expect(a.hasNumber, isTrue);
    expect(a.archived, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ledger/models_test.dart`
Expected: FAIL — `models.dart` not found.

- [ ] **Step 3: Implement** — `mobile/lib/core/ledger/models.dart`

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ledger/models_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/ledger/models.dart mobile/test/ledger/models_test.dart
git commit -m "ledger v2: مدل‌های دفتر (حساب، تراکنش، نقطه‌ی مانده، پیامک، تصمیم)"
```

---

### Task 2: Ledger math (ordering, balance, discrepancies, balance-at)

**Files:**
- Create: `mobile/lib/core/ledger/ledger_math.dart`
- Create: `mobile/test/ledger/ledger_fixtures.dart`
- Test: `mobile/test/ledger/ledger_math_test.dart`

**Interfaces:**
- Consumes: Task 1 models.
- Produces: `sealed class LedgerItem {DateTime at; String accountId; int? checkpointBalance; int signed}`, `EntryItem(entry)`, `CheckpointItem(checkpoint)`, `void sortEntriesForBalance(List<Entry>)`, `List<LedgerItem> orderLedger(Iterable<Entry>, Iterable<Checkpoint>)`, `AccountBalance? currentBalance(List<LedgerItem>)` (`balanceRial`, `anchor`), `class DiscrepancyWindow {accountId, from, to, expectedRial, actualRial, diffRial, entries, start, end}`, `List<DiscrepancyWindow> discrepancies(List<LedgerItem>)`, `int? balanceAt(List<LedgerItem>, DateTime, {bool inclusive = true, bool backwardFirst = true})`.
- Test helpers produced (`ledger_fixtures.dart`): `Entry entry(String id, EntryKind kind, int amount, DateTime at, {int? bal, String acc = 'a1', DateTime? created})`, `Checkpoint checkpoint(String id, int balance, DateTime at, {String acc = 'a1'})`, `SmsItem smsItem(String key, {required DateTime at, EntryKind? kind, int? amount, String? accountId, SmsStatus status = SmsStatus.pending})`.

- [ ] **Step 1: Create test fixtures** — `mobile/test/ledger/ledger_fixtures.dart`

```dart
import 'package:economy/core/ledger/models.dart';

Entry entry(String id, EntryKind kind, int amount, DateTime at,
        {int? bal, String acc = 'a1', DateTime? created}) =>
    Entry(
      id: id,
      accountId: acc,
      kind: kind,
      amountRial: amount,
      occurredAt: at,
      bankBalanceAfter: bal,
      source: bal == null ? EntrySource.manual : EntrySource.sms,
      createdAt: created ?? at,
      updatedAt: created ?? at,
    );

Checkpoint checkpoint(String id, int balance, DateTime at, {String acc = 'a1'}) => Checkpoint(
      id: id,
      accountId: acc,
      at: at,
      balanceRial: balance,
      createdAt: at,
      updatedAt: at,
    );

SmsItem smsItem(String key,
        {required DateTime at,
        EntryKind? kind,
        int? amount,
        String? accountId,
        SmsStatus status = SmsStatus.pending}) =>
    SmsItem(
      key: key,
      contentHash: key,
      sender: 'bank',
      receivedAt: at,
      suggestion: SmsSuggestion(kind: kind, amountRial: amount, occurredAt: at, accountId: accountId),
      status: status,
      parserVersion: 4,
    );
```

- [ ] **Step 2: Write the failing test** — `mobile/test/ledger/ledger_math_test.dart`

```dart
import 'package:economy/core/ledger/ledger_math.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ledger_fixtures.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 23, 6);
  DateTime h(int hours) => t0.add(Duration(hours: hours));
  const inc = EntryKind.income, exp = EntryKind.expense;

  group('orderLedger', () {
    test('same-minute SMS are chained by bank balance, not by creation order', () {
      final a = entry('A', exp, 100, h(1), bal: 900, created: h(3));
      final b = entry('B', exp, 100, h(1), bal: 800, created: h(2));
      final seq = orderLedger([b, a], [checkpoint('c', 1000, t0)]);
      expect(seq.map((i) => i is EntryItem ? i.entry.id : 'cp'), ['cp', 'A', 'B']);
    });

    test('a manual checkpoint sits after entries at or before its time', () {
      final seq = orderLedger(
          [entry('late', exp, 5, h(2)), entry('same', exp, 5, h(1))], [checkpoint('c', 50, h(1))]);
      expect(seq.map((i) => i is EntryItem ? i.entry.id : 'cp'), ['same', 'cp', 'late']);
    });

    test('deleted entries and checkpoints are left out', () {
      final gone = entry('x', exp, 5, h(1)).copyWith(deletedAt: h(2));
      expect(orderLedger([gone], []), isEmpty);
    });
  });

  group('currentBalance', () {
    test('last checkpoint plus signed entries after it', () {
      final seq = orderLedger([
        entry('s1', exp, 100, h(1), bal: 900),
        entry('m1', exp, 50, h(2)),
      ], [
        checkpoint('c', 1000, t0)
      ]);
      final b = currentBalance(seq)!;
      expect(b.balanceRial, 850);
      expect((b.anchor as EntryItem).entry.id, 's1');
    });

    test('no checkpoint at all: unknown balance', () {
      expect(currentBalance(orderLedger([entry('m', exp, 5, h(1))], [])), isNull);
    });
  });

  group('discrepancies', () {
    test('scenario 2: consistent chain has no window', () {
      final seq = orderLedger([
        entry('s1', exp, 100, h(1), bal: 900),
        entry('s2', inc, 300, h(2), bal: 1200),
      ], [
        checkpoint('c', 1000, t0)
      ]);
      expect(discrepancies(seq), isEmpty);
      expect(currentBalance(seq)!.balanceRial, 1200);
    });

    test('scenario 3: a missing SMS shows as a window with its exact amount', () {
      final seq = orderLedger([
        entry('s1', exp, 100, h(1), bal: 900),
        // missing: expense 200 at h(2), balance 700
        entry('s3', exp, 50, h(3), bal: 650),
      ], [
        checkpoint('c', 1000, t0)
      ]);
      final ws = discrepancies(seq);
      expect(ws, hasLength(1));
      expect(ws.single.diffRial, -200);
      expect(ws.single.start, h(1));
      expect(ws.single.end, h(3));
      expect(ws.single.entries.map((e) => e.id), ['s3']);
      expect(ws.single.accountId, 'a1');
    });

    test('scenario 5: cash account, reconcile, adjustment closes the gap', () {
      final base = [
        entry('m1', exp, 1000000, h(1)),
      ];
      final cps = [checkpoint('anchor', 10000000, t0), checkpoint('real', 8500000, h(2))];
      expect(currentBalance(orderLedger(base, [cps.first]))!.balanceRial, 9000000);
      final ws = discrepancies(orderLedger(base, cps));
      expect(ws.single.diffRial, -500000);
      final fixed = orderLedger([...base, entry('adj', exp, 500000, h(2))], cps);
      expect(discrepancies(fixed), isEmpty);
      expect(currentBalance(fixed)!.balanceRial, 8500000);
    });

    test('scenario 6: a wrong "balance now" shows at the next bank SMS', () {
      final seq = orderLedger([entry('s1', exp, 100000, h(1), bal: 5000000)],
          [checkpoint('anchor', 5000000, t0)]); // really 5,100,000
      expect(discrepancies(seq).single.diffRial, 100000);
    });
  });

  group('balanceAt', () {
    test('month opening goes backward from the nearest later checkpoint', () {
      final seq = orderLedger([
        entry('s1', exp, 100, h(24), bal: 900),
        entry('s2', exp, 50, h(48), bal: 850),
      ], []);
      expect(balanceAt(seq, t0, inclusive: false), 1000);
    });

    test('without a later checkpoint it goes forward from the previous one', () {
      final seq = orderLedger([entry('m', exp, 100, h(1))], [checkpoint('c', 1000, t0)]);
      expect(balanceAt(seq, h(5)), 900);
    });

    test('forward-first gives the chain value right before a new SMS', () {
      final seq = orderLedger([entry('s1', exp, 100, h(1), bal: 900)], [checkpoint('c', 1000, t0)]);
      expect(balanceAt(seq, h(2), backwardFirst: false), 900);
    });

    test('empty ledger: null', () {
      expect(balanceAt(const [], t0), isNull);
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/ledger/ledger_math_test.dart`
Expected: FAIL — `ledger_math.dart` not found.

- [ ] **Step 4: Implement** — `mobile/lib/core/ledger/ledger_math.dart`

```dart
/// حسابِ موجودی و اختلاف (docs/v2-design.md بخش ۶). همه‌چیز روی یک **فهرستِ مرتب**
/// از تراکنش‌ها و نقطه‌های مانده کار می‌کند، نه روی مقایسه‌ی زمان (پیامک فقط تا دقیقه زمان دارد).
library;

import 'models.dart';

sealed class LedgerItem {
  const LedgerItem();
  DateTime get at;
  String get accountId;

  /// موجودیِ قطعی بعد از این قلم، اگر نقطه‌ی مانده است.
  int? get checkpointBalance;
  int get signed;
}

class EntryItem extends LedgerItem {
  final Entry entry;
  const EntryItem(this.entry);
  @override
  DateTime get at => entry.occurredAt;
  @override
  String get accountId => entry.accountId;
  @override
  int? get checkpointBalance => entry.bankBalanceAfter;
  @override
  int get signed => entry.signed;
}

class CheckpointItem extends LedgerItem {
  final Checkpoint checkpoint;
  const CheckpointItem(this.checkpoint);
  @override
  DateTime get at => checkpoint.at;
  @override
  String get accountId => checkpoint.accountId;
  @override
  int? get checkpointBalance => checkpoint.balanceRial;
  @override
  int get signed => 0;
}

int _byTime(Entry a, Entry b) {
  var c = a.occurredAt.compareTo(b.occurredAt);
  if (c != 0) return c;
  c = a.createdAt.compareTo(b.createdAt);
  return c != 0 ? c : a.id.compareTo(b.id);
}

bool _fitsAfter(int prev, Entry e) =>
    e.bankBalanceAfter != null && prev + e.signed == e.bankBalanceAfter;

/// ترتیبِ تراکنش‌های یک حساب: زمان؛ و پیامک‌های هم‌دقیقه به ترتیبی که مانده‌هایشان پشتِ هم
/// جور شود (منطقِ `sortForBalance` نسخه‌ی ۱).
void sortEntriesForBalance(List<Entry> list) {
  list.sort(_byTime);
  int? prev;
  var i = 0;
  while (i < list.length) {
    var j = i + 1;
    while (j < list.length && list[j].occurredAt == list[i].occurredAt) {
      j++;
    }
    if (j - i > 1) list.setRange(i, j, _chainRun(list.sublist(i, j), prev));
    for (var k = i; k < j; k++) {
      prev = list[k].bankBalanceAfter ?? (prev == null ? null : prev + list[k].signed);
    }
    i = j;
  }
}

List<Entry> _chainRun(List<Entry> run, int? prev) {
  (List<Entry>, int) greedy(int? start, List<Entry> items) {
    final rest = [...items];
    final out = <Entry>[];
    var p = start;
    var fits = 0;
    while (rest.isNotEmpty) {
      var k = p == null ? -1 : rest.indexWhere((e) => _fitsAfter(p!, e));
      if (k == -1) {
        k = 0;
      } else {
        fits++;
      }
      final e = rest.removeAt(k);
      out.add(e);
      p = e.bankBalanceAfter ?? (p == null ? null : p + e.signed);
    }
    return (out, fits);
  }

  if (prev != null) return greedy(prev, run).$1;
  var best = run;
  var bestFits = -1;
  for (var s = 0; s < run.length; s++) {
    final first = run[s];
    if (first.bankBalanceAfter == null) continue;
    final (tail, fits) = greedy(first.bankBalanceAfter, [...run]..removeAt(s));
    if (fits > bestFits) {
      best = [first, ...tail];
      bestFits = fits;
    }
  }
  return best;
}

/// فهرستِ مرتبِ یک حساب. نقطه‌ی دستی بعد از همه‌ی تراکنش‌هایی می‌نشیند که
/// `occurredAt ≤ at` دارند؛ نقطه‌ی بانکی همان تراکنشِ مانده‌دار است.
List<LedgerItem> orderLedger(Iterable<Entry> entries, Iterable<Checkpoint> checkpoints) {
  final es = [for (final e in entries) if (!e.isDeleted) e];
  sortEntriesForBalance(es);
  final cps = [for (final c in checkpoints) if (c.deletedAt == null) c]..sort((a, b) {
      final c = a.at.compareTo(b.at);
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });
  final out = <LedgerItem>[];
  var j = 0;
  for (final e in es) {
    while (j < cps.length && cps[j].at.isBefore(e.occurredAt)) {
      out.add(CheckpointItem(cps[j++]));
    }
    out.add(EntryItem(e));
  }
  while (j < cps.length) {
    out.add(CheckpointItem(cps[j++]));
  }
  return out;
}

class AccountBalance {
  final int balanceRial;

  /// آخرین نقطه‌ی مانده (مبنای عدد؛ I3).
  final LedgerItem anchor;
  const AccountBalance(this.balanceRial, this.anchor);
}

/// موجودی = آخرین نقطه‌ی مانده + تراکنش‌های بعد از آن. بدونِ هیچ نقطه‌ای: null.
AccountBalance? currentBalance(List<LedgerItem> seq) {
  for (var k = seq.length - 1; k >= 0; k--) {
    final b = seq[k].checkpointBalance;
    if (b == null) continue;
    var sum = 0;
    for (var i = k + 1; i < seq.length; i++) {
      sum += seq[i].signed;
    }
    return AccountBalance(b + sum, seq[k]);
  }
  return null;
}

/// بازه‌ی بینِ دو نقطه‌ی مانده‌ی پشتِ‌سرِ‌هم که جمعِ تراکنش‌هایش با مانده‌ها نمی‌خواند.
class DiscrepancyWindow {
  final LedgerItem from;
  final LedgerItem to;
  final int expectedRial;
  final int actualRial;

  /// تراکنش‌های داخلِ بازه (شاملِ تراکنشِ نقطه‌ی پایانی اگر بانکی است).
  final List<Entry> entries;

  const DiscrepancyWindow({
    required this.from,
    required this.to,
    required this.expectedRial,
    required this.actualRial,
    required this.entries,
  });

  String get accountId => to.accountId;
  int get diffRial => actualRial - expectedRial;
  DateTime get start => from.at;
  DateTime get end => to.at;
}

List<DiscrepancyWindow> discrepancies(List<LedgerItem> seq) {
  final out = <DiscrepancyWindow>[];
  LedgerItem? prev;
  var sum = 0;
  var inside = <Entry>[];
  for (final item in seq) {
    if (item is EntryItem) {
      sum += item.signed;
      inside.add(item.entry);
    }
    final bal = item.checkpointBalance;
    if (bal == null) continue;
    if (prev != null) {
      final expected = prev.checkpointBalance! + sum;
      if (expected != bal) {
        out.add(DiscrepancyWindow(
            from: prev, to: item, expectedRial: expected, actualRial: bal, entries: inside));
      }
    }
    prev = item;
    sum = 0;
    inside = <Entry>[];
  }
  return out;
}

/// موجودی درست بعد از همه‌ی اقلامِ تا [t] ([inclusive]=false: فقط قبل از [t]).
/// [backwardFirst]: اول رو به عقب از نزدیک‌ترین نقطه‌ی بعد (موجودیِ اولِ ماه، طرح ۶.۱)،
/// وگرنه رو به جلو از نقطه‌ی قبل؛ با false برعکس (مانده‌ی زنجیره پیش از یک پیامکِ تازه).
int? balanceAt(List<LedgerItem> seq, DateTime t,
    {bool inclusive = true, bool backwardFirst = true}) {
  var p = 0;
  while (p < seq.length && (inclusive ? !seq[p].at.isAfter(t) : seq[p].at.isBefore(t))) {
    p++;
  }
  int? backward() {
    for (var k = p; k < seq.length; k++) {
      final b = seq[k].checkpointBalance;
      if (b == null) continue;
      var sum = 0;
      for (var i = p; i <= k; i++) {
        sum += seq[i].signed;
      }
      return b - sum;
    }
    return null;
  }

  int? forward() {
    for (var k = p - 1; k >= 0; k--) {
      final b = seq[k].checkpointBalance;
      if (b == null) continue;
      var sum = 0;
      for (var i = k + 1; i < p; i++) {
        sum += seq[i].signed;
      }
      return b + sum;
    }
    return null;
  }

  return backwardFirst ? (backward() ?? forward()) : (forward() ?? backward());
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/ledger/ledger_math_test.dart`
Expected: PASS (13 tests).

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/core/ledger/ledger_math.dart mobile/test/ledger/ledger_fixtures.dart mobile/test/ledger/ledger_math_test.dart
git commit -m "ledger v2: موجودی از آخرین نقطه‌ی مانده، پنجره‌های اختلاف، موجودیِ اولِ ماه رو به عقب"
```

---

### Task 3: Suggestions (account, kind, not-a-transaction, duplicate, window hints)

**Files:**
- Create: `mobile/lib/core/ledger/suggestion.dart`
- Test: `mobile/test/ledger/suggestion_test.dart`

**Interfaces:**
- Consumes: Task 1 models; Task 2 `orderLedger`, `balanceAt`, `discrepancies`, `DiscrepancyWindow`, `LedgerItem`, `EntryItem`; `SmsParser`/`ParsedTransaction`/`TxKind`/`ReviewReason` (existing `lib/core/sms/`).
- Produces: `class AccountReason {number, onlyAccount, balance}`, `class NotTxReason {otp, reminder, failed, noAmount, noAccount, archived}` (string constants), `class SuggestionContext {accounts, ledgers; SuggestionContext.build(accounts, entries, checkpoints); ledgerOf(id); account(id)}`, `SmsSuggestion suggest(ParsedTransaction p, {required DateTime receivedAt, required SuggestionContext ctx, bool resent = false})`, `class WindowHints {explainingSmsKeys, reversedEntryIds, hasPendingInRange}`, `WindowHints analyzeWindow(DiscrepancyWindow w, Iterable<SmsItem> sms)`.

- [ ] **Step 1: Write the failing test** — `mobile/test/ledger/suggestion_test.dart`

```dart
import 'package:economy/core/ledger/ledger_math.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/suggestion.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ledger_fixtures.dart';

void main() {
  const parser = SmsParser();
  final t0 = DateTime.utc(2026, 9, 23, 6);
  DateTime h(int hours) => t0.add(Duration(hours: hours));
  const inc = EntryKind.income, exp = EntryKind.expense;

  const mellat = LedgerAccount(
      id: 'm1', ownerName: 'مهدی', label: 'ملت', bankId: 'mellat', accountRef: '1000005596');
  const pas1 = LedgerAccount(
      id: 'p1', ownerName: 'مهدی', label: 'پاسارگاد', bankId: 'pasargad', accountRef: '777.888.10000001.1');
  const pas2 = LedgerAccount(id: 'p2', ownerName: 'زهرا', label: 'پاسارگاد ۲', bankId: 'pasargad');

  const mellatBody = 'حساب1000005596\nبرداشت63,881,900\nمانده36,400,179\n05/07/01-13:05';
  final mellatAt = DateTime.utc(2026, 9, 23, 9, 35);

  SuggestionContext ctx(List<LedgerAccount> accounts,
          {List<Entry> entries = const [], List<Checkpoint> cps = const []}) =>
      SuggestionContext.build(accounts, entries, cps);

  group('account', () {
    test('by account number in the SMS', () {
      final p = parser.parse(sender: 'Bank Mellat', body: mellatBody);
      final s = suggest(p, receivedAt: mellatAt, ctx: ctx([mellat, pas1]));
      expect(s.accountId, 'm1');
      expect(s.accountReason, AccountReason.number);
      expect(s.kind, exp);
      expect(s.amountRial, 63881900);
      expect(s.balanceRial, 36400179);
      expect(s.occurredAt, mellatAt);
      expect(s.looksLikeTx, isTrue);
    });

    test('scenario 13: no number, the only account of that bank', () {
      final p = parser.parse(
          sender: '+985000114',
          body: '*بانکداري ديجيتالي پاسارگاد*\nاقساط قرارداد 1001 - حساب پشتوانه به مبلغ '
              '71,367,398 ریال از حساب دیجیتال با موفقیت پرداخت گردید.\nتعداد اقساط باقی مانده:0');
      final s = suggest(p, receivedAt: h(1), ctx: ctx([mellat, pas1]));
      expect(s.accountId, 'p1');
      expect(s.accountReason, AccountReason.onlyAccount);
      expect(s.kind, exp);
    });

    const digitalBody =
        'مبلغ 1,000,000 ریال از حساب دیجیتال با موفقیت پرداخت گردید.\nموجودی حساب دیجیتال: 49,000,000 ریال';

    test('no number, two accounts: the one whose balance chain fits', () {
      final p = parser.parse(sender: 'B.Pasargad', body: digitalBody);
      final s = suggest(p,
          receivedAt: h(1),
          ctx: ctx([pas1, pas2], cps: [
            checkpoint('c1', 100000000, t0, acc: 'p1'),
            checkpoint('c2', 50000000, t0, acc: 'p2'),
          ]));
      expect(s.accountId, 'p2');
      expect(s.accountReason, AccountReason.balance);
    });

    test('two accounts that both fit: no guess', () {
      final p = parser.parse(sender: 'B.Pasargad', body: digitalBody);
      final s = suggest(p,
          receivedAt: h(1),
          ctx: ctx([pas1, pas2], cps: [
            checkpoint('c1', 50000000, t0, acc: 'p1'),
            checkpoint('c2', 50000000, t0, acc: 'p2'),
          ]));
      expect(s.accountId, isNull);
    });

    test('an unknown account number asks "new account?"', () {
      final p = parser.parse(
          sender: 'Bank Mellat', body: 'حساب2000000000\nبرداشت1,000\nمانده5,000\n05/07/01-13:05');
      final s = suggest(p, receivedAt: mellatAt, ctx: ctx([mellat]));
      expect(s.accountId, isNull);
      expect(s.unknownAccountNumber, isTrue);
    });
  });

  group('card-to-card direction', () {
    const body = 'انتقال کارت به کارت\nمبلغ 2,000,000 ریال\nحساب1000005596\nمانده 38,400,179';

    test('inferred from the balance difference', () {
      final p = parser.parse(sender: 'Bank Mellat', body: body);
      final s = suggest(p,
          receivedAt: h(1), ctx: ctx([mellat], cps: [checkpoint('c', 36400179, t0, acc: 'm1')]));
      expect(s.accountId, 'm1');
      expect(s.kind, inc);
    });

    test('unknown when there is no previous balance', () {
      final p = parser.parse(sender: 'Bank Mellat', body: body);
      expect(suggest(p, receivedAt: h(1), ctx: ctx([mellat])).kind, isNull);
    });
  });

  group('not a transaction', () {
    test('one-time password', () {
      final p = parser.parse(sender: 'Bank Mellat', body: 'رمز پویا: 123456 مبلغ 50,000 ریال');
      expect(suggest(p, receivedAt: h(1), ctx: ctx([mellat])).notTxReason, NotTxReason.otp);
    });

    test('scenario 12: DigiPay credit has no bank and no account', () {
      final p = parser.parse(
          sender: '+989900004602',
          body: 'پرداخت بدهی و شارژ اعتبار دیجی‌پی\nاعتبار قابل مصرف: 72٬750٬000 ریال');
      final s = suggest(p, receivedAt: h(1), ctx: ctx([mellat]));
      expect(s.notTxReason, NotTxReason.noAccount);
      expect(s.accountId, isNull);
    });

    test('archived account', () {
      const archived = LedgerAccount(
          id: 'm1', ownerName: 'مهدی', label: 'ملت', bankId: 'mellat', accountRef: '1000005596', archived: true);
      final p = parser.parse(sender: 'Bank Mellat', body: mellatBody);
      final s = suggest(p, receivedAt: mellatAt, ctx: ctx([archived]));
      expect(s.accountId, 'm1');
      expect(s.notTxReason, NotTxReason.archived);
    });
  });

  group('duplicate', () {
    test('same account, amount and bank balance already recorded', () {
      final p = parser.parse(sender: 'Bank Mellat', body: mellatBody);
      final s = suggest(p,
          receivedAt: mellatAt,
          ctx: ctx([mellat],
              entries: [entry('e', exp, 63881900, mellatAt, bal: 36400179, acc: 'm1')]));
      expect(s.likelyDuplicate, isTrue);
    });

    test('bank re-sent the same text', () {
      final p = parser.parse(sender: 'Bank Mellat', body: mellatBody);
      expect(suggest(p, receivedAt: mellatAt, ctx: ctx([mellat]), resent: true).likelyDuplicate, isTrue);
    });

    test('same amount but a different bank balance is not a duplicate', () {
      final p = parser.parse(sender: 'Bank Mellat', body: mellatBody);
      final s = suggest(p,
          receivedAt: mellatAt,
          ctx: ctx([mellat], entries: [entry('e', exp, 63881900, mellatAt, bal: 1, acc: 'm1')]));
      expect(s.likelyDuplicate, isFalse);
    });
  });

  group('analyzeWindow', () {
    List<LedgerItem> gapLedger() => orderLedger([
          entry('s1', exp, 100, h(1), bal: 900),
          entry('s3', exp, 50, h(3), bal: 650),
        ], [
          checkpoint('c', 1000, t0)
        ]);

    test('scenario 3: a rejected SMS with exactly the gap amount is offered', () {
      final w = discrepancies(gapLedger()).single;
      final hints = analyzeWindow(w, [
        smsItem('rej', at: h(2), kind: exp, amount: 200, status: SmsStatus.rejected),
        smsItem('other', at: h(2), kind: exp, amount: 999),
        smsItem('far', at: h(30), kind: exp, amount: 200),
      ]);
      expect(hints.explainingSmsKeys, ['rej']);
      expect(hints.hasPendingInRange, isTrue);
    });

    test('scenario 4: reversed kind shows as twice the amount', () {
      final seq = orderLedger([
        entry('wrong', inc, 100, h(1)),
        entry('s2', exp, 50, h(2), bal: 850),
      ], [
        checkpoint('c', 1000, t0)
      ]);
      final hints = analyzeWindow(discrepancies(seq).single, const []);
      expect(hints.reversedEntryIds, ['wrong']);
      expect(hints.hasPendingInRange, isFalse);
    });

    test('scenario 13: installment without balance explains the gap', () {
      final seq = orderLedger([
        entry('s1', exp, 1000000, h(1), bal: 99000000, acc: 'p1'),
        entry('s3', exp, 1000000, h(3), bal: 26632602, acc: 'p1'),
      ], [
        checkpoint('c', 100000000, t0, acc: 'p1')
      ]);
      final w = discrepancies(seq).single;
      expect(w.diffRial, -71367398);
      final hints = analyzeWindow(
          w, [smsItem('inst', at: h(2), kind: exp, amount: 71367398, accountId: 'p1')]);
      expect(hints.explainingSmsKeys, ['inst']);
    });

    test('SMS suggested for another account is ignored', () {
      final w = discrepancies(gapLedger()).single;
      final hints = analyzeWindow(w, [smsItem('x', at: h(2), kind: exp, amount: 200, accountId: 'zz')]);
      expect(hints.explainingSmsKeys, isEmpty);
      expect(hints.hasPendingInRange, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ledger/suggestion_test.dart`
Expected: FAIL — `suggestion.dart` not found.

- [ ] **Step 3: Implement** — `mobile/lib/core/ledger/suggestion.dart`

```dart
/// پیشنهادهای برنامه برای پیامک‌ها و پنجره‌های اختلاف (docs/v2-design.md ۵.۳، ۶.۳، ۶.۶).
/// همه **فقط پیشنهاد** است؛ هیچ تابعی اینجا چیزی نمی‌نویسد (I1).
library;

import '../sms/models.dart';
import 'ledger_math.dart';
import 'models.dart';

class AccountReason {
  AccountReason._();
  static const number = 'number';
  static const onlyAccount = 'only_account';
  static const balance = 'balance';
}

class NotTxReason {
  NotTxReason._();
  static const otp = 'otp';
  static const reminder = 'reminder';
  static const failed = 'failed';
  static const noAmount = 'no_amount';

  /// بی‌بانک و بی‌شماره: اعتبارِ کیف پول (دیجی‌پی/دیما)، نه پولِ حسابِ بانکی.
  static const noAccount = 'no_account';
  static const archived = 'archived';
}

const _slack = Duration(minutes: 15);
const _dupWindow = Duration(minutes: 10);

class SuggestionContext {
  final List<LedgerAccount> accounts;

  /// شناسه‌ی حساب ← فهرستِ مرتبِ آن ([orderLedger]).
  final Map<String, List<LedgerItem>> ledgers;

  const SuggestionContext({this.accounts = const [], this.ledgers = const {}});

  factory SuggestionContext.build(
      List<LedgerAccount> accounts, Iterable<Entry> entries, Iterable<Checkpoint> checkpoints) {
    final es = <String, List<Entry>>{};
    final cs = <String, List<Checkpoint>>{};
    for (final e in entries) {
      es.putIfAbsent(e.accountId, () => []).add(e);
    }
    for (final c in checkpoints) {
      cs.putIfAbsent(c.accountId, () => []).add(c);
    }
    return SuggestionContext(accounts: accounts, ledgers: {
      for (final a in accounts) a.id: orderLedger(es[a.id] ?? const [], cs[a.id] ?? const []),
    });
  }

  List<LedgerItem> ledgerOf(String accountId) => ledgers[accountId] ?? const [];

  LedgerAccount? account(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }
}

SmsSuggestion suggest(ParsedTransaction p,
    {required DateTime receivedAt, required SuggestionContext ctx, bool resent = false}) {
  final at = p.occurredAt ?? receivedAt;
  final amount = p.amountRial;
  final balance = p.balanceAfterRial;
  var kind = switch (p.kind) {
    TxKind.income => EntryKind.income,
    TxKind.expense => EntryKind.expense,
    _ => null,
  };

  final (accountId, accountReason, unknownNumber) = _suggestAccount(p, at, kind, ctx);

  // کارت‌به‌کارت/حواله جهت ندارد: از اختلافِ مانده با زنجیره‌ی همان حساب.
  if (kind == null && accountId != null && amount != null && balance != null) {
    final prior = balanceAt(ctx.ledgerOf(accountId), at, backwardFirst: false);
    if (prior != null && balance - prior == amount) kind = EntryKind.income;
    if (prior != null && prior - balance == amount) kind = EntryKind.expense;
  }

  final archived = accountId != null && (ctx.account(accountId)?.archived ?? false);
  final notTx = p.isOtp
      ? NotTxReason.otp
      : p.isReminder
          ? NotTxReason.reminder
          : p.reviewReasons.contains(ReviewReason.failed)
              ? NotTxReason.failed
              : amount == null
                  ? NotTxReason.noAmount
                  : (p.bankId == null && !p.hasAccountId)
                      ? NotTxReason.noAccount
                      : archived
                          ? NotTxReason.archived
                          : null;

  final duplicate = resent ||
      (accountId != null &&
          amount != null &&
          _isLikelyDuplicate(ctx.ledgerOf(accountId), amount, kind, balance, at));

  return SmsSuggestion(
    kind: kind,
    amountRial: amount,
    balanceRial: balance,
    occurredAt: at,
    accountId: accountId,
    accountReason: accountReason,
    notTxReason: notTx,
    likelyDuplicate: duplicate,
    unknownAccountNumber: unknownNumber,
  );
}

/// (حساب، دلیل، شماره‌ی ناشناخته). ترتیب: شماره‌ی داخلِ پیامک؛ تنها حسابِ آن بانک؛
/// حسابی که مانده‌اش دقیقاً با زنجیره جور است؛ وگرنه هیچ.
(String?, String?, bool) _suggestAccount(
    ParsedTransaction p, DateTime at, EntryKind? kind, SuggestionContext ctx) {
  if (p.hasAccountId) {
    final byNumber = [for (final a in ctx.accounts) if (_numberMatches(a, p)) a];
    if (byNumber.length == 1) return (byNumber.single.id, AccountReason.number, false);
    if (byNumber.length > 1) return (null, null, false);
  }
  if (p.bankId == null) return (null, null, p.hasAccountId);
  // پیامکِ شماره‌دار فقط به حسابِ بی‌شماره‌ی همان بانک می‌خورد.
  final candidates = [
    for (final a in ctx.accounts)
      if (!a.archived && a.bankId == p.bankId && !(p.hasAccountId && a.hasNumber)) a,
  ];
  if (candidates.length == 1) return (candidates.single.id, AccountReason.onlyAccount, false);
  final amount = p.amountRial, balance = p.balanceAfterRial;
  if (candidates.length > 1 && amount != null && balance != null) {
    final fits = [
      for (final a in candidates)
        if (_fitsChain(ctx.ledgerOf(a.id), at, amount, balance, kind)) a,
    ];
    if (fits.length == 1) return (fits.single.id, AccountReason.balance, false);
  }
  return (null, null, p.hasAccountId);
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

bool _numberMatches(LedgerAccount a, ParsedTransaction p) {
  if (a.bankId != null && p.bankId != null && a.bankId != p.bankId) return false;
  if (p.cardLast4 != null && a.cardLast4 == p.cardLast4) return true;
  final ref = p.accountRef;
  return ref != null && a.accountRef != null && _digits(a.accountRef!) == _digits(ref);
}

bool _fitsChain(List<LedgerItem> seq, DateTime at, int amount, int balance, EntryKind? kind) {
  final prior = balanceAt(seq, at, backwardFirst: false);
  if (prior == null) return false;
  return switch (kind) {
    EntryKind.income => prior + amount == balance,
    EntryKind.expense => prior - amount == balance,
    null => (balance - prior).abs() == amount,
  };
}

bool _isLikelyDuplicate(
    List<LedgerItem> seq, int amount, EntryKind? kind, int? balance, DateTime at) {
  for (final item in seq) {
    if (item is! EntryItem) continue;
    final e = item.entry;
    if (e.amountRial != amount || (kind != null && e.kind != kind)) continue;
    final eb = e.bankBalanceAfter;
    if (balance != null && eb != null) {
      if (eb == balance) return true;
      continue;
    }
    if (e.occurredAt.difference(at).abs() <= _dupWindow) return true;
  }
  return false;
}

/// راهنمای یک پنجره‌ی اختلاف (۶.۳).
class WindowHints {
  /// پیامک‌های منتظر یا ردشده‌ی داخلِ بازه که مبلغشان دقیقاً اختلاف را توضیح می‌دهد.
  final List<String> explainingSmsKeys;

  /// اختلاف = ۲ برابرِ مبلغِ این تراکنش‌ها با علامتِ برعکس: احتمالاً نوعشان برعکس است.
  final List<String> reversedEntryIds;

  /// نارنجی: پیامکِ منتظر در بازه هست (شاید فقط باید تأیید شود)؛ وگرنه قرمز.
  final bool hasPendingInRange;

  const WindowHints({
    required this.explainingSmsKeys,
    required this.reversedEntryIds,
    required this.hasPendingInRange,
  });
}

WindowHints analyzeWindow(DiscrepancyWindow w, Iterable<SmsItem> sms) {
  final diff = w.diffRial;
  final lo = w.start.subtract(_slack), hi = w.end.add(_slack);
  final explaining = <String>[];
  var pending = false;
  for (final s in sms) {
    if (s.status == SmsStatus.accepted) continue;
    final g = s.suggestion;
    if (g.accountId != null && g.accountId != w.accountId) continue;
    final t = g.occurredAt ?? s.receivedAt;
    if (t.isBefore(lo) || t.isAfter(hi)) continue;
    if (s.status == SmsStatus.pending) pending = true;
    final a = g.amountRial;
    if (a == null) continue;
    final explains = switch (g.kind) {
      EntryKind.income => a == diff,
      EntryKind.expense => -a == diff,
      null => a == diff.abs(),
    };
    if (explains) explaining.add(s.key);
  }
  return WindowHints(
    explainingSmsKeys: explaining,
    reversedEntryIds: [for (final e in w.entries) if (diff == -2 * e.signed) e.id],
    hasPendingInRange: pending,
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ledger/suggestion_test.dart`
Expected: PASS (17 tests). If the DigiPay or Pasargad parse assertions fail, first print `parser.parse(...)` in the test to confirm what the v1 parser returns — do not change the parser in this task.

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/ledger/suggestion.dart mobile/test/ledger/suggestion_test.dart
git commit -m "ledger v2: پیشنهادِ حساب/نوع/تکراری/تراکنش‌نیست و راهنمای پنجره‌ی اختلاف (فقط پیشنهاد)"
```

---

### Task 4: SMS intake (keys, start date, same-SMS rule, server decisions, re-suggest)

**Files:**
- Create: `mobile/lib/core/ledger/sms_intake.dart`
- Test: `mobile/test/ledger/sms_intake_test.dart`

**Interfaces:**
- Consumes: Task 1 models; Task 3 `suggest`, `SuggestionContext`; existing `SmsParser`, `kParserVersion`, `AllowedSender`, `findAllowedSender`, `canonicalSender`, `normalizeForParsing`, `JalaliDate`.
- Produces: `const kSameSmsWindow`, `String ledgerSenderKey(String)`, `String smsContentHash({required String sender, required String body})`, `String smsItemKey(String contentHash, DateTime receivedAt)`, `bool isSameSms(String hashA, DateTime atA, String hashB, DateTime atB)`, `DateTime ledgerStartFor(DateTime now)`, `class IncomingSms {sender, body, receivedAt}`, `sealed class IntakeResult` with `IntakeIgnored(reason)` (`notAllowed`, `beforeStart`), `IntakeKnown(item, {bodyFilled})`, `IntakeNew(item)`, `IntakeResult intakeSms(IncomingSms, {required DateTime startDate, required Iterable<AllowedSender> allowed, required Iterable<SmsItem> existing, Iterable<SmsDecision> serverDecisions, required SuggestionContext ctx, SmsParser parser})`, `SmsItem? resuggest(SmsItem, {required Iterable<AllowedSender> allowed, required Iterable<SmsItem> others, required SuggestionContext ctx, SmsParser parser, int parserVersion})`.

- [ ] **Step 1: Write the failing test** — `mobile/test/ledger/sms_intake_test.dart`

```dart
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/ledger/suggestion.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const allowed = [AllowedSender(id: 's1', address: 'Bank Mellat', bankId: 'mellat')];
  const mellat = LedgerAccount(
      id: 'm1', ownerName: 'مهدی', label: 'ملت', bankId: 'mellat', accountRef: '1000005596');
  const ctx = SuggestionContext(accounts: [mellat]);
  const body = 'حساب1000005596\nبرداشت63,881,900\nمانده36,400,179\n05/07/01-13:05';
  final at = DateTime.utc(2026, 9, 23, 9, 35, 10);
  final start = ledgerStartFor(DateTime.utc(2026, 9, 24, 10));

  IntakeResult take(IncomingSms sms,
          {List<SmsItem> existing = const [], List<SmsDecision> decisions = const []}) =>
      intakeSms(sms,
          startDate: start,
          allowed: allowed,
          existing: existing,
          serverDecisions: decisions,
          ctx: ctx);

  SmsItem newItem(IntakeResult r) => (r as IntakeNew).item;

  test('start date is the first of the current Jalali month, Iran midnight', () {
    expect(start, DateTime.utc(2026, 9, 22, 20, 30)); // ۱۴۰۵/۰۷/۰۱ ۰۰:۰۰ تهران
  });

  test('sender key ignores +98 / 0 / spacing', () {
    expect(ledgerSenderKey('+98200012345'), ledgerSenderKey('0200012345'));
    expect(ledgerSenderKey('+985000114'), ledgerSenderKey('5000114'));
    expect(ledgerSenderKey('Bank Mellat'), ledgerSenderKey('bankmellat'));
  });

  test('scenario 1: before the start date is not even stored; this month is pending', () {
    final old = take(IncomingSms(sender: 'Bank Mellat', body: body, receivedAt: DateTime.utc(2026, 9, 20)));
    expect(old, isA<IntakeIgnored>());
    expect((old as IntakeIgnored).reason, IntakeIgnored.beforeStart);

    final item = newItem(take(IncomingSms(sender: 'Bank Mellat', body: body, receivedAt: at)));
    expect(item.status, SmsStatus.pending);
    expect(item.suggestion.accountId, 'm1');
    expect(item.key, smsItemKey(item.contentHash, at));
  });

  test('a sender that is not allowed is ignored', () {
    final r = take(IncomingSms(sender: 'Digikala', body: body, receivedAt: at));
    expect((r as IntakeIgnored).reason, IntakeIgnored.notAllowed);
  });

  test('scenario 10: live + inbox a few minutes apart are one SMS', () {
    final live = newItem(take(IncomingSms(sender: 'Bank Mellat', body: body, receivedAt: at)));
    final inbox = take(
        IncomingSms(sender: 'Bank Mellat', body: body, receivedAt: at.add(const Duration(minutes: 6))),
        existing: [live]);
    expect(inbox, isA<IntakeKnown>());
    expect((inbox as IntakeKnown).item.key, live.key);
  });

  test('scenario 11: the same text two hours later is a separate, likely-duplicate SMS', () {
    final first = newItem(take(IncomingSms(sender: 'Bank Mellat', body: body, receivedAt: at)));
    final again = newItem(take(
        IncomingSms(sender: 'Bank Mellat', body: body, receivedAt: at.add(const Duration(hours: 2))),
        existing: [first]));
    expect(again.key, isNot(first.key));
    expect(again.suggestion.likelyDuplicate, isTrue);
    expect(again.status, SmsStatus.pending);
  });

  test('scenario 7: a server decision is restored with its key (reinstall)', () {
    final hash = smsContentHash(sender: 'Bank Mellat', body: body);
    final decision = SmsDecision(
      key: 'original-key',
      contentHash: hash,
      receivedAt: at.subtract(const Duration(minutes: 3)),
      status: SmsStatus.rejected,
      rejectReason: RejectReason.notTx,
      decidedAt: at,
    );
    final item =
        newItem(take(IncomingSms(sender: 'Bank Mellat', body: body, receivedAt: at), decisions: [decision]));
    expect(item.key, 'original-key');
    expect(item.status, SmsStatus.rejected);
    expect(item.rejectReason, RejectReason.notTx);
  });

  test('an existing item without text gets its text back, decision untouched', () {
    final hash = smsContentHash(sender: 'Bank Mellat', body: body);
    final bare = SmsItem(
      key: 'k',
      contentHash: hash,
      sender: 'Bank Mellat',
      receivedAt: at,
      suggestion: const SmsSuggestion(),
      status: SmsStatus.accepted,
      entryId: 'e1',
      parserVersion: 4,
    );
    final r = take(IncomingSms(sender: 'Bank Mellat', body: body, receivedAt: at), existing: [bare])
        as IntakeKnown;
    expect(r.bodyFilled, isTrue);
    expect(r.item.body, body);
    expect(r.item.status, SmsStatus.accepted);
    expect(r.item.entryId, 'e1');
  });

  group('scenario 9: better parser only changes pending suggestions', () {
    SmsItem stored(SmsStatus status) => SmsItem(
          key: 'k-$status',
          contentHash: 'h-$status',
          sender: 'Bank Mellat',
          receivedAt: at,
          body: body,
          suggestion: const SmsSuggestion(),
          status: status,
          parserVersion: 1,
        );

    test('pending with an old parser version is re-suggested', () {
      final fresh = resuggest(stored(SmsStatus.pending), allowed: allowed, others: const [], ctx: ctx)!;
      expect(fresh.suggestion.accountId, 'm1');
      expect(fresh.parserVersion, kParserVersion);
      expect(fresh.status, SmsStatus.pending);
    });

    test('decided items are never touched (I2)', () {
      expect(resuggest(stored(SmsStatus.accepted), allowed: allowed, others: const [], ctx: ctx), isNull);
      expect(resuggest(stored(SmsStatus.rejected), allowed: allowed, others: const [], ctx: ctx), isNull);
    });

    test('already on the current parser: nothing to do', () {
      final current = stored(SmsStatus.pending).withSuggestion(const SmsSuggestion(), kParserVersion);
      expect(resuggest(current, allowed: allowed, others: const [], ctx: ctx), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ledger/sms_intake_test.dart`
Expected: FAIL — `sms_intake.dart` not found.

- [ ] **Step 3: Implement** — `mobile/lib/core/ledger/sms_intake.dart`

```dart
/// ورودِ پیامک به دفتر (docs/v2-design.md ۵.۱ و ۵.۲): فقط یک `SmsItem` می‌سازد، هرگز تراکنش (ت۲).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../features/senders/data/allowed_sender.dart';
import '../sms/digit_utils.dart';
import '../sms/jalali.dart';
import '../sms/sms_parser.dart';
import 'models.dart';
import 'suggestion.dart';

/// زمانِ دریافتِ زنده و ستونِ `date` صندوق چند ثانیه تا چند دقیقه فرق دارند.
const kSameSmsWindow = Duration(minutes: 10);

final _withCountryCode = RegExp(r'^98[0-9]{7,}$');

/// شکلِ پایدارِ فرستنده برای کلید: «+98…»، «0…» و بی‌پیش‌شماره یکی‌اند.
String ledgerSenderKey(String raw) {
  final s = canonicalSender(raw);
  return _withCountryCode.hasMatch(s) ? s.substring(2) : s;
}

/// عمداً با [normalizeForParsing] و نه `cleanForParsing`: کلید با بهترشدنِ پارسر عوض نمی‌شود.
String smsContentHash({required String sender, required String body}) => sha256
    .convert(utf8.encode('${ledgerSenderKey(sender)}|${normalizeForParsing(body)}'))
    .toString();

String smsItemKey(String contentHash, DateTime receivedAt) =>
    '$contentHash:${receivedAt.toUtc().millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute}';

bool isSameSms(String hashA, DateTime atA, String hashB, DateTime atB) =>
    hashA == hashB && atA.difference(atB).abs() <= kSameSmsWindow;

/// تاریخِ شروع (ت۱): اولِ ماهِ شمسیِ جاری، ساعتِ ۰۰:۰۰ تهران، به UTC.
DateTime ledgerStartFor(DateTime now) {
  final j = JalaliDate.fromDateTime(now);
  return JalaliDate(j.year, j.month, 1).toUtcStart();
}

class IncomingSms {
  final String sender;
  final String body;
  final DateTime receivedAt;
  const IncomingSms({required this.sender, required this.body, required this.receivedAt});
}

sealed class IntakeResult {
  const IntakeResult();
}

class IntakeIgnored extends IntakeResult {
  static const notAllowed = 'not_allowed';
  static const beforeStart = 'before_start';

  final String reason;
  const IntakeIgnored(this.reason);
}

/// همین پیامک قبلاً هست؛ تصمیمش دست‌نخورده. [bodyFilled]: متنش خالی بود و پر شد.
class IntakeKnown extends IntakeResult {
  final SmsItem item;
  final bool bodyFilled;
  const IntakeKnown(this.item, {this.bodyFilled = false});
}

class IntakeNew extends IntakeResult {
  final SmsItem item;
  const IntakeNew(this.item);
}

IntakeResult intakeSms(
  IncomingSms sms, {
  required DateTime startDate,
  required Iterable<AllowedSender> allowed,
  required Iterable<SmsItem> existing,
  Iterable<SmsDecision> serverDecisions = const [],
  required SuggestionContext ctx,
  SmsParser parser = const SmsParser(),
}) {
  final sender = findAllowedSender(allowed, sms.sender);
  if (sender == null) return const IntakeIgnored(IntakeIgnored.notAllowed);
  if (sms.receivedAt.isBefore(startDate)) return const IntakeIgnored(IntakeIgnored.beforeStart);

  final hash = smsContentHash(sender: sms.sender, body: sms.body);
  var resent = false;
  for (final e in existing) {
    if (e.contentHash != hash) continue;
    if (isSameSms(hash, sms.receivedAt, e.contentHash, e.receivedAt)) {
      return e.body == null ? IntakeKnown(e.withBody(sms.body), bodyFilled: true) : IntakeKnown(e);
    }
    if (e.receivedAt.isBefore(sms.receivedAt)) resent = true;
  }

  final parsed = parser.parse(
      sender: sms.sender, body: sms.body, bankId: sender.bankId, receivedAt: sms.receivedAt);
  final suggestion = suggest(parsed, receivedAt: sms.receivedAt, ctx: ctx, resent: resent);

  SmsDecision? decision;
  for (final d in serverDecisions) {
    if (isSameSms(hash, sms.receivedAt, d.contentHash, d.receivedAt)) {
      decision = d;
      break;
    }
  }
  return IntakeNew(SmsItem(
    key: decision?.key ?? smsItemKey(hash, sms.receivedAt),
    contentHash: hash,
    sender: sms.sender,
    receivedAt: sms.receivedAt,
    body: sms.body,
    suggestion: suggestion,
    status: decision?.status ?? SmsStatus.pending,
    entryId: decision?.entryId,
    rejectReason: decision?.rejectReason,
    decidedAt: decision?.decidedAt,
    parserVersion: kParserVersion,
  ));
}

/// پیشنهادِ تازه برای پیامکِ **منتظر** با پارسرِ جدیدتر؛ تصمیم‌دارها هرگز (I2). null = کاری نیست.
SmsItem? resuggest(
  SmsItem item, {
  required Iterable<AllowedSender> allowed,
  required Iterable<SmsItem> others,
  required SuggestionContext ctx,
  SmsParser parser = const SmsParser(),
  int parserVersion = kParserVersion,
}) {
  final body = item.body;
  if (item.status != SmsStatus.pending || body == null || item.parserVersion >= parserVersion) {
    return null;
  }
  final sender = findAllowedSender(allowed, item.sender);
  final parsed = parser.parse(
      sender: item.sender, body: body, bankId: sender?.bankId, receivedAt: item.receivedAt);
  final resent = others.any((o) =>
      o.key != item.key && o.contentHash == item.contentHash && o.receivedAt.isBefore(item.receivedAt));
  return item.withSuggestion(
      suggest(parsed, receivedAt: item.receivedAt, ctx: ctx, resent: resent), parserVersion);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ledger/sms_intake_test.dart`
Expected: PASS (11 tests).

- [ ] **Step 5: Commit**

```bash
git add mobile/lib/core/ledger/sms_intake.dart mobile/test/ledger/sms_intake_test.dart
git commit -m "ledger v2: ورودِ پیامک (کلیدِ پایدار، قاعده‌ی ۱۰ دقیقه، تاریخِ شروع، تصمیمِ سرور)"
```

---

### Task 5: Schema v11 + LedgerRepository

**Files:**
- Create: `mobile/lib/core/ledger/ledger_schema.dart`
- Create: `mobile/lib/core/ledger/ledger_repository.dart`
- Modify: `mobile/lib/core/database/app_database.dart` (`kDbVersion` 10→11; `migrateSchema` block `oldVersion < 11`; end of `createSchema`)
- Test: `mobile/test/ledger/ledger_repository_test.dart`

**Interfaces:**
- Consumes: Tasks 1–4; `openAppDatabase`, `migrateSchema`, `createSchema` (existing); test helper `initSqfliteFfiForTests` (`test/helpers/db_test_helper.dart`).
- Produces: `Future<void> createLedgerTables(DatabaseExecutor db)`; `const kLedgerV2Setting = 'ledger_v2'`, `const kLedgerStartSetting = 'ledger_start_date'`; `class LedgerRepository(Database db, {required String deviceId, Uuid uuid, DateTime Function()? clock})` with `isEnabled()`, `setEnabled(bool)`, `startDate()`, `ensureStartDate({DateTime? fromServer})`, `accounts()`, `setArchived(String, bool)`, `entries({String? accountId})`, `checkpoints({String? accountId})`, `ledger(String accountId)`, `suggestionContext()`, `smsItems({SmsStatus? status})`, `smsItem(String key)`, `intakeAll(Iterable<IncomingSms>, {required List<AllowedSender> allowed, Iterable<SmsDecision> serverDecisions, DateTime? serverStartDate})`, `refreshPendingSuggestions({required List<AllowedSender> allowed, int parserVersion})`, user actions `acceptSms(...)`, `rejectSms(key, reason)`, `addEntry(...)`, `updateEntry(Entry)`, `deleteEntry(String id)`, `addCheckpoint(...)`, `deleteCheckpoint(String id)`.

- [ ] **Step 1: Write the failing test** — `mobile/test/ledger/ledger_repository_test.dart`

```dart
import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/ledger/ledger_math.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/ledger/suggestion.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

void main() {
  const allowed = [AllowedSender(id: 's1', address: 'Bank Mellat', bankId: 'mellat')];
  final now = DateTime.utc(2026, 9, 24, 10); // ۱۴۰۵/۰۷/۰۲
  late Database db;
  late LedgerRepository repo;

  IncomingSms mellat(String amountLine, int balance, DateTime at) => IncomingSms(
      sender: 'Bank Mellat',
      body: 'حساب1000005596\n$amountLine\nمانده${_fmt(balance)}',
      receivedAt: at);

  Future<void> addWallet(Database d) => d.insert('wallets', {
        'id': 'm1',
        'owner_name': 'مهدی',
        'label': 'ملت',
        'bank_id': 'mellat',
        'account_ref': '1000005596',
        'created_at': now.toIso8601String(),
      });

  Future<(Database, LedgerRepository)> freshDb() async {
    final d = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    await addWallet(d);
    return (d, LedgerRepository(d, deviceId: 'dev', clock: () => now));
  }

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    (db, repo) = await freshDb();
  });

  tearDown(() => db.close());

  final t1 = DateTime.utc(2026, 9, 23, 7), t2 = DateTime.utc(2026, 9, 23, 8), t3 = DateTime.utc(2026, 9, 23, 9);

  test('flag is off by default; start date is stored once', () async {
    expect(await repo.isEnabled(), isFalse);
    expect(await repo.startDate(), isNull);
    final start = await repo.ensureStartDate();
    expect(start, DateTime.utc(2026, 9, 22, 20, 30));
    expect(await repo.ensureStartDate(fromServer: DateTime.utc(2020)), start);
  });

  test('scenario 8: migrating v10 → v11 creates empty ledger tables, v1 data untouched', () async {
    for (final t in ['sms_items', 'ledger_entries', 'ledger_checkpoints']) {
      await db.execute('DROP TABLE $t');
    }
    await db.insert('transactions', {
      'id': 'old',
      'kind': 'expense',
      'amount_rial': 5,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    await migrateSchema(db, 10, 11);
    expect(await repo.entries(), isEmpty);
    expect(await repo.smsItems(), isEmpty);
    expect((await db.query('transactions')).single['id'], 'old');
    expect((await repo.accounts()).single.archived, isFalse);
  });

  test('intake stores pending items only and never creates entries (I1, scenario 1)', () async {
    await repo.intakeAll([
      mellat('برداشت100,000', 900000, t2),
      mellat('برداشت50,000', 850000, t3),
      mellat('برداشت1,000', 5, DateTime.utc(2026, 9, 1)), // ماهِ قبل
    ], allowed: allowed);
    final items = await repo.smsItems();
    expect(items, hasLength(2));
    expect(items.every((i) => i.status == SmsStatus.pending), isTrue);
    expect(await repo.entries(), isEmpty);
  });

  test('scenario 2: accept all → balance = last bank SMS, no window', () async {
    await repo.intakeAll([mellat('برداشت100,000', 900000, t2), mellat('برداشت50,000', 850000, t3)],
        allowed: allowed);
    for (final i in await repo.smsItems()) {
      final g = i.suggestion;
      await repo.acceptSms(i.key, accountId: g.accountId!, kind: g.kind!, amountRial: g.amountRial!);
    }
    final seq = await repo.ledger('m1');
    expect(currentBalance(seq)!.balanceRial, 850000);
    expect(discrepancies(seq), isEmpty);
    expect((await repo.smsItems()).every((i) => i.status == SmsStatus.accepted), isTrue);
  });

  test('scenario 3: rejecting a real SMS opens a window; accepting it closes it', () async {
    await repo.intakeAll([
      mellat('برداشت100,000', 900000, t1),
      mellat('برداشت200,000', 700000, t2),
      mellat('برداشت50,000', 650000, t3),
    ], allowed: allowed);
    final items = (await repo.smsItems())..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    final middle = items[1];
    for (final i in [items[0], items[2]]) {
      await repo.acceptSms(i.key, accountId: 'm1', kind: EntryKind.expense, amountRial: i.suggestion.amountRial!);
    }
    await repo.rejectSms(middle.key, RejectReason.notTx);

    final w = discrepancies(await repo.ledger('m1')).single;
    expect(w.diffRial, -200000);
    final hints = analyzeWindow(w, await repo.smsItems());
    expect(hints.explainingSmsKeys, [middle.key]);
    expect((await repo.smsItem(middle.key))!.status, SmsStatus.rejected); // هنوز تصمیمِ کاربر

    await repo.acceptSms(middle.key, accountId: 'm1', kind: EntryKind.expense, amountRial: 200000);
    expect(discrepancies(await repo.ledger('m1')), isEmpty);
  });

  test('scenario 7: reinstall restores decisions and creates nothing', () async {
    await repo.intakeAll([mellat('برداشت100,000', 900000, t1), mellat('برداشت9,999', 1, t2)],
        allowed: allowed);
    final items = (await repo.smsItems())..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    final entry = await repo.acceptSms(items[0].key,
        accountId: 'm1', kind: EntryKind.expense, amountRial: 100000);
    await repo.rejectSms(items[1].key, RejectReason.other);
    final decisions = [for (final i in await repo.smsItems()) i.decision];
    final start = await repo.startDate();

    final (db2, repo2) = await freshDb();
    addTearDown(db2.close);
    await db2.insert('ledger_entries', entry.toMap()); // از سرور (فاز ۴)
    await repo2.intakeAll([
      mellat('برداشت100,000', 900000, t1.add(const Duration(minutes: 2))),
      mellat('برداشت9,999', 1, t2),
      mellat('برداشت50,000', 850000, t3),
    ], allowed: allowed, serverDecisions: decisions, serverStartDate: start);

    final restored = {for (final i in await repo2.smsItems()) i.key: i};
    expect(restored[items[0].key]!.status, SmsStatus.accepted);
    expect(restored[items[0].key]!.entryId, entry.id);
    expect(restored[items[1].key]!.status, SmsStatus.rejected);
    expect(restored.values.where((i) => i.status == SmsStatus.pending), hasLength(1));
    expect(await repo2.entries(), hasLength(1));
    expect(await repo2.startDate(), start);
  });

  test('scenario 9: refreshing suggestions touches pending items only', () async {
    await repo.intakeAll([mellat('برداشت100,000', 900000, t1), mellat('برداشت50,000', 850000, t2)],
        allowed: allowed);
    final items = (await repo.smsItems())..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    await repo.acceptSms(items[0].key, accountId: 'm1', kind: EntryKind.expense, amountRial: 100000);
    await db.update('sms_items', {'parser_version': 0});

    expect(await repo.refreshPendingSuggestions(allowed: allowed), 1);
    final after = {for (final i in await repo.smsItems()) i.key: i};
    expect(after[items[0].key]!.parserVersion, 0);
    expect(after[items[0].key]!.status, SmsStatus.accepted);
    expect(after[items[1].key]!.parserVersion, kParserVersion);
  });

  test('deleting an SMS entry is the user rejecting that SMS', () async {
    await repo.intakeAll([mellat('برداشت100,000', 900000, t1)], allowed: allowed);
    final item = (await repo.smsItems()).single;
    final e = await repo.acceptSms(item.key, accountId: 'm1', kind: EntryKind.expense, amountRial: 100000);
    await repo.deleteEntry(e.id);
    expect(await repo.entries(), isEmpty);
    final back = (await repo.smsItem(item.key))!;
    expect(back.status, SmsStatus.rejected);
    expect(back.rejectReason, RejectReason.other);
  });

  test('accepting twice is refused; rejecting an accepted SMS is refused', () async {
    await repo.intakeAll([mellat('برداشت100,000', 900000, t1)], allowed: allowed);
    final key = (await repo.smsItems()).single.key;
    await repo.acceptSms(key, accountId: 'm1', kind: EntryKind.expense, amountRial: 100000);
    expect(() => repo.acceptSms(key, accountId: 'm1', kind: EntryKind.expense, amountRial: 1),
        throwsStateError);
    expect(() => repo.rejectSms(key, RejectReason.other), throwsStateError);
  });

  test('scenario 5 through the repository: anchor, manual entry, reconcile, adjustment', () async {
    await repo.addCheckpoint(accountId: 'm1', balanceRial: 10000000, at: t1);
    await repo.addEntry(accountId: 'm1', kind: EntryKind.expense, amountRial: 1000000, occurredAt: t2);
    expect(currentBalance(await repo.ledger('m1'))!.balanceRial, 9000000);
    await repo.addCheckpoint(accountId: 'm1', balanceRial: 8500000, at: t3);
    expect(discrepancies(await repo.ledger('m1')).single.diffRial, -500000);

    expect(
        () => repo.addEntry(
            accountId: 'm1',
            kind: EntryKind.expense,
            amountRial: 500000,
            occurredAt: t3,
            source: EntrySource.adjustment),
        throwsArgumentError);
    await repo.addEntry(
        accountId: 'm1',
        kind: EntryKind.expense,
        amountRial: 500000,
        occurredAt: t3,
        source: EntrySource.adjustment,
        note: 'کارمزد');
    expect(discrepancies(await repo.ledger('m1')), isEmpty);
  });

  test('archived account: its SMS are suggested as not-a-transaction', () async {
    await repo.setArchived('m1', true);
    await repo.intakeAll([mellat('برداشت100,000', 900000, t1)], allowed: allowed);
    final s = (await repo.smsItems()).single.suggestion;
    expect(s.notTxReason, NotTxReason.archived);
    expect(await repo.entries(), isEmpty);
  });
}

String _fmt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ledger/ledger_repository_test.dart`
Expected: FAIL — `ledger_repository.dart` not found.

- [ ] **Step 3: Implement the schema** — `mobile/lib/core/ledger/ledger_schema.dart`

```dart
/// جدول‌های دفترِ نسخه‌ی ۲ (schema نسخه‌ی ۱۱). نقطه‌ی مانده‌ی بانکی ذخیره نمی‌شود؛
/// از `ledger_entries.bank_balance_after` مشتق می‌شود.
library;

import 'package:sqflite/sqflite.dart';

Future<void> createLedgerTables(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ledger_entries (
      id TEXT PRIMARY KEY,
      account_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      is_transfer INTEGER NOT NULL DEFAULT 0,
      transfer_pair_id TEXT,
      amount_rial INTEGER NOT NULL,
      occurred_at TEXT NOT NULL,
      bank_balance_after INTEGER,
      source TEXT NOT NULL,
      sms_key TEXT,
      note TEXT,
      created_by_device TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      sync_status TEXT NOT NULL DEFAULT 'pending'
    )
  ''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_le_account ON ledger_entries(account_id, occurred_at)');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS ledger_checkpoints (
      id TEXT PRIMARY KEY,
      account_id TEXT NOT NULL,
      at TEXT NOT NULL,
      balance_rial INTEGER NOT NULL,
      note TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      sync_status TEXT NOT NULL DEFAULT 'pending'
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sms_items (
      key TEXT PRIMARY KEY,
      content_hash TEXT NOT NULL,
      sender TEXT NOT NULL,
      received_at TEXT NOT NULL,
      body TEXT,
      sugg_kind TEXT,
      sugg_amount INTEGER,
      sugg_balance INTEGER,
      sugg_occurred_at TEXT,
      sugg_account_id TEXT,
      sugg_account_reason TEXT,
      sugg_not_tx TEXT,
      sugg_duplicate INTEGER NOT NULL DEFAULT 0,
      sugg_new_account INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending',
      entry_id TEXT,
      reject_reason TEXT,
      decided_at TEXT,
      parser_version INTEGER NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'pending'
    )
  ''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_sms_hash ON sms_items(content_hash)');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_sms_status ON sms_items(status)');
}
```

- [ ] **Step 4: Wire schema v11** — in `mobile/lib/core/database/app_database.dart`

Add import after the `uuid` import:

```dart
import '../ledger/ledger_schema.dart';
```

Change the version:

```dart
const int kDbVersion = 11;
```

Append to the end of `migrateSchema` (after the `oldVersion < 10` block):

```dart
  if (oldVersion < 11) {
    // نسخه ۱۱: دفترِ نسخه‌ی ۲ (پشتِ پرچمِ ledger_v2؛ docs/v2-design.md). هیچ تراکنشی نمی‌سازد.
    await _ensureColumn(db, 'wallets', 'archived', 'INTEGER NOT NULL DEFAULT 0');
    await createLedgerTables(db);
  }
```

Append to the end of `createSchema` (after `_createAllowedSendersTable(db);`):

```dart
  await _ensureColumn(db, 'wallets', 'archived', 'INTEGER NOT NULL DEFAULT 0');
  await createLedgerTables(db);
```

- [ ] **Step 5: Implement the repository** — `mobile/lib/core/ledger/ledger_repository.dart`

```dart
/// تنها راهِ نوشتن در جدول‌های دفترِ نسخه‌ی ۲. تراکنش فقط با متدهای «کارِ کاربر» ساخته،
/// عوض یا حذف می‌شود: [acceptSms]، [addEntry]، [updateEntry]، [deleteEntry] (I1).
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../features/senders/data/allowed_sender.dart';
import '../sms/sms_parser.dart';
import 'ledger_math.dart';
import 'models.dart';
import 'sms_intake.dart';
import 'suggestion.dart';

const kLedgerV2Setting = 'ledger_v2';
const kLedgerStartSetting = 'ledger_start_date';

class LedgerRepository {
  LedgerRepository(this.db,
      {required this.deviceId, Uuid uuid = const Uuid(), DateTime Function()? clock})
      : _uuid = uuid,
        _clock = clock ?? DateTime.now;

  final Database db;
  final String deviceId;
  final Uuid _uuid;
  final DateTime Function() _clock;

  DateTime _now() => _clock().toUtc();

  // --- تنظیمات ---

  Future<String?> _setting(String key) async {
    final rows =
        await db.query('settings', columns: ['value'], where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _setSetting(String key, String value) => db.insert(
      'settings', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<bool> isEnabled() async => await _setting(kLedgerV2Setting) == '1';

  Future<void> setEnabled(bool on) => _setSetting(kLedgerV2Setting, on ? '1' : '0');

  Future<DateTime?> startDate() async {
    final v = await _setting(kLedgerStartSetting);
    return v == null ? null : DateTime.parse(v).toUtc();
  }

  /// تاریخِ شروع (ت۱): ذخیره‌شده؛ وگرنه از سرور؛ وگرنه اولِ ماهِ شمسیِ جاری.
  Future<DateTime> ensureStartDate({DateTime? fromServer}) async {
    final stored = await startDate();
    if (stored != null) return stored;
    final start = (fromServer ?? ledgerStartFor(_now())).toUtc();
    await _setSetting(kLedgerStartSetting, start.toIso8601String());
    return start;
  }

  // --- خواندن ---

  Future<List<LedgerAccount>> accounts() async {
    final rows = await db.query('wallets', where: 'is_deleted = 0', orderBy: 'created_at');
    return rows.map(LedgerAccount.fromWalletRow).toList();
  }

  Future<void> setArchived(String accountId, bool archived) => db.update(
      'wallets', {'archived': archived ? 1 : 0},
      where: 'id = ?', whereArgs: [accountId]);

  Future<List<Entry>> entries({String? accountId}) async {
    final rows = await db.query('ledger_entries',
        where: accountId == null ? 'deleted_at IS NULL' : 'deleted_at IS NULL AND account_id = ?',
        whereArgs: accountId == null ? null : [accountId]);
    return rows.map(Entry.fromMap).toList();
  }

  Future<Entry?> _entry(String id) async {
    final rows = await db.query('ledger_entries', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Entry.fromMap(rows.first);
  }

  Future<List<Checkpoint>> checkpoints({String? accountId}) async {
    final rows = await db.query('ledger_checkpoints',
        where: accountId == null ? 'deleted_at IS NULL' : 'deleted_at IS NULL AND account_id = ?',
        whereArgs: accountId == null ? null : [accountId]);
    return rows.map(Checkpoint.fromMap).toList();
  }

  Future<List<LedgerItem>> ledger(String accountId) async =>
      orderLedger(await entries(accountId: accountId), await checkpoints(accountId: accountId));

  Future<SuggestionContext> suggestionContext() async =>
      SuggestionContext.build(await accounts(), await entries(), await checkpoints());

  Future<List<SmsItem>> smsItems({SmsStatus? status}) async {
    final rows = await db.query('sms_items',
        where: status == null ? null : 'status = ?',
        whereArgs: status == null ? null : [status.name],
        orderBy: 'received_at DESC');
    return rows.map(SmsItem.fromMap).toList();
  }

  Future<SmsItem?> smsItem(String key) async {
    final rows = await db.query('sms_items', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : SmsItem.fromMap(rows.first);
  }

  // --- ورودِ پیامک (فقط sms_items؛ هرگز تراکنش) ---

  Future<List<IntakeResult>> intakeAll(
    Iterable<IncomingSms> batch, {
    required List<AllowedSender> allowed,
    Iterable<SmsDecision> serverDecisions = const [],
    DateTime? serverStartDate,
  }) async {
    final start = await ensureStartDate(fromServer: serverStartDate);
    final existing = await smsItems();
    final ctx = await suggestionContext();
    final sorted = [...batch]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    final results = <IntakeResult>[];
    for (final sms in sorted) {
      final r = intakeSms(sms,
          startDate: start,
          allowed: allowed,
          existing: existing,
          serverDecisions: serverDecisions,
          ctx: ctx);
      switch (r) {
        case IntakeNew(:final item):
          await db.insert('sms_items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
          existing.add(item);
        case IntakeKnown(:final item, :final bodyFilled) when bodyFilled:
          await db.update('sms_items', {'body': item.body}, where: 'key = ?', whereArgs: [item.key]);
          existing[existing.indexWhere((e) => e.key == item.key)] = item;
        case IntakeKnown() || IntakeIgnored():
          break;
      }
      results.add(r);
    }
    return results;
  }

  /// پیشنهادِ پیامک‌های منتظر با پارسرِ تازه؛ تصمیم‌دارها دست‌نخورده (I2).
  Future<int> refreshPendingSuggestions(
      {required List<AllowedSender> allowed, int parserVersion = kParserVersion}) async {
    final all = await smsItems();
    final ctx = await suggestionContext();
    var n = 0;
    for (final item in all) {
      final fresh =
          resuggest(item, allowed: allowed, others: all, ctx: ctx, parserVersion: parserVersion);
      if (fresh == null) continue;
      n += await db.update(
          'sms_items', {...fresh.suggestion.toColumns(), 'parser_version': fresh.parserVersion},
          where: 'key = ? AND status = ?', whereArgs: [item.key, SmsStatus.pending.name]);
    }
    return n;
  }

  // --- کارِ کاربر ---

  /// «ثبت»: یک تراکنش از پیامک (منتظر یا ردشده) می‌سازد. مانده‌ی بانک از پیشنهاد.
  Future<Entry> acceptSms(
    String key, {
    required String accountId,
    required EntryKind kind,
    required int amountRial,
    DateTime? occurredAt,
    int? bankBalanceAfter,
    String? note,
  }) async {
    if (amountRial <= 0) throw ArgumentError.value(amountRial, 'amountRial');
    final item = await smsItem(key);
    if (item == null) throw StateError('SMS item $key not found');
    if (item.status == SmsStatus.accepted) throw StateError('SMS item $key already accepted');
    final now = _now();
    final entry = Entry(
      id: _uuid.v4(),
      accountId: accountId,
      kind: kind,
      amountRial: amountRial,
      occurredAt: (occurredAt ?? item.suggestion.occurredAt ?? item.receivedAt).toUtc(),
      bankBalanceAfter: bankBalanceAfter ?? item.suggestion.balanceRial,
      source: EntrySource.sms,
      smsKey: key,
      note: note,
      createdByDevice: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await db.transaction((txn) async {
      await txn.insert('ledger_entries', entry.toMap());
      await txn.update(
          'sms_items',
          {
            'status': SmsStatus.accepted.name,
            'entry_id': entry.id,
            'reject_reason': null,
            'decided_at': now.toIso8601String(),
            'sync_status': 'pending',
          },
          where: 'key = ?',
          whereArgs: [key]);
    });
    return entry;
  }

  /// «تراکنش نیست» / «تکراری است». پیامکِ ثبت‌شده را باید با حذفِ تراکنشش رد کرد.
  Future<void> rejectSms(String key, RejectReason reason) async {
    final item = await smsItem(key);
    if (item == null) throw StateError('SMS item $key not found');
    if (item.status == SmsStatus.accepted) {
      throw StateError('SMS item $key is accepted; delete its entry instead');
    }
    await _markRejected(db, key, reason);
  }

  Future<void> _markRejected(DatabaseExecutor ex, String key, RejectReason reason) => ex.update(
      'sms_items',
      {
        'status': SmsStatus.rejected.name,
        'reject_reason': reason.code,
        'entry_id': null,
        'decided_at': _now().toIso8601String(),
        'sync_status': 'pending',
      },
      where: 'key = ?',
      whereArgs: [key]);

  /// افزودنِ دستی یا «اصلاح» (اصلاح یادداشتِ اجباری دارد؛ ۶.۳).
  Future<Entry> addEntry({
    required String accountId,
    required EntryKind kind,
    required int amountRial,
    required DateTime occurredAt,
    String? note,
    EntrySource source = EntrySource.manual,
  }) async {
    if (amountRial <= 0) throw ArgumentError.value(amountRial, 'amountRial');
    if (source == EntrySource.sms) throw ArgumentError('SMS entries are created by acceptSms');
    if (source == EntrySource.adjustment && (note == null || note.trim().isEmpty)) {
      throw ArgumentError('an adjustment needs a note');
    }
    final now = _now();
    final entry = Entry(
      id: _uuid.v4(),
      accountId: accountId,
      kind: kind,
      amountRial: amountRial,
      occurredAt: occurredAt.toUtc(),
      source: source,
      note: note,
      createdByDevice: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('ledger_entries', entry.toMap());
    return entry;
  }

  Future<void> updateEntry(Entry e) async {
    if (e.amountRial <= 0) throw ArgumentError.value(e.amountRial, 'amountRial');
    await db.update('ledger_entries', {...e.copyWith(updatedAt: _now()).toMap(), 'sync_status': 'pending'},
        where: 'id = ?', whereArgs: [e.id]);
  }

  /// حذفِ نرم. تراکنشِ پیامکی: یعنی کاربر آن پیامک را رد کرده (`other`).
  Future<void> deleteEntry(String id) async {
    final e = await _entry(id);
    if (e == null || e.isDeleted) return;
    final now = _now();
    await db.transaction((txn) async {
      await txn.update(
          'ledger_entries',
          {'deleted_at': now.toIso8601String(), 'updated_at': now.toIso8601String(), 'sync_status': 'pending'},
          where: 'id = ?',
          whereArgs: [id]);
      if (e.smsKey != null) await _markRejected(txn, e.smsKey!, RejectReason.other);
    });
  }

  /// نقطه‌ی مانده‌ی دستی: «موجودیِ الان» یا «تطبیق با موجودیِ واقعی».
  Future<Checkpoint> addCheckpoint(
      {required String accountId, required int balanceRial, DateTime? at, String? note}) async {
    final now = _now();
    final cp = Checkpoint(
      id: _uuid.v4(),
      accountId: accountId,
      at: (at ?? now).toUtc(),
      balanceRial: balanceRial,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('ledger_checkpoints', cp.toMap());
    return cp;
  }

  Future<void> deleteCheckpoint(String id) async {
    final now = _now().toIso8601String();
    await db.update('ledger_checkpoints', {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ?', whereArgs: [id]);
  }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/ledger/ledger_repository_test.dart`
Expected: PASS (11 tests).

- [ ] **Step 7: Run the whole suite + analyzer (v1 must not regress)**

Run: `flutter test` then `flutter analyze`
Expected: all tests pass (previous 463 + new ledger tests); analyzer: `No issues found!`. If `test/db/migration_test.dart` asserts the old version number, update only that expectation to 11.

- [ ] **Step 8: Commit**

```bash
git add mobile/lib/core/ledger/ledger_schema.dart mobile/lib/core/ledger/ledger_repository.dart mobile/lib/core/database/app_database.dart mobile/test/ledger/ledger_repository_test.dart
git commit -m "ledger v2: جدول‌ها (schema 11) و مخزنِ دفتر؛ تراکنش فقط با کارِ کاربر"
```

---

### Task 6: Docs, version, push

**Files:**
- Modify: `docs/v2-design.md` §4.2 (bank checkpoints derived, not stored)
- Modify: `TODO.md` (v2 phase 1 ✅ with test counts)
- Modify: `mobile/pubspec.yaml` (`version: 1.0.23+24`)

- [ ] **Step 1: Design note** — in `docs/v2-design.md` §4.2 replace the line starting `(نقطه‌ی بانکی از روی تراکنش ساخته/حذف می‌شود؛` with:

```markdown
(نقطه‌ی بانکی **ذخیره نمی‌شود**: همان `bank_balance_after` تراکنشِ ثبت‌شده است و با ویرایش/حذفِ تراکنش خودبه‌خود
عوض می‌شود؛ جدولِ `ledger_checkpoints` فقط نقطه‌های دستی را دارد و کاربر ویرایش یا حذفشان می‌کند.)
```

- [ ] **Step 2: TODO** — replace the `⬜ **فاز ۱ — هسته‌ی خالص:**` line in `TODO.md` with a ✅ entry listing: files in `lib/core/ledger/`, schema v11 (no UI, flag off), scenarios covered by unit tests (1–14 core; 15 is phase 5), and the exact `flutter test` count from Task 5 Step 7. Update the "آخرین به‌روزرسانی" date line to `۱۴۰۵/۰۷/۰۳ (2026-09-25)`.

- [ ] **Step 3: Bump version** — `mobile/pubspec.yaml`: `version: 1.0.23+24`.

- [ ] **Step 4: Commit and push**

```bash
git add docs/v2-design.md TODO.md mobile/pubspec.yaml
git commit -m "نسخه‌ی ۲ فاز ۱ تمام: هسته‌ی دفتر با تست؛ نسخه 1.0.23"
git push origin main
```

## Self-Review Notes

- Spec coverage (§11 phase 1): models ✅ T1, `ledger_math` ✅ T2, `suggestion` ✅ T3, `sms_intake` ✅ T4, tables + migration + repository behind flag ✅ T5. Scenarios: 1 (T4, T5), 2 (T2, T5), 3 (T2, T3, T5), 4 (T3), 5 (T2, T5), 6 (T2), 7 (T4, T5), 8 (T5), 9 (T4, T5), 10 (T4), 11 (T4), 12 (T3), 13 (T3), 14 (T1). Scenario 15 (two members) needs the server → phase 5.
- Out of scope for phase 1 by design: `entry_categories` and category prefill (phase 2 sheet), server sync + outbox (phase 4), transfer pairing (`transfer_pair_id` column exists, no logic).
- Type consistency checked: `SuggestionContext.build`, `balanceAt(..., backwardFirst:)`, `IntakeKnown(item, bodyFilled:)`, `resuggest(..., others:)`, `RejectReason.code` used identically across tasks.
