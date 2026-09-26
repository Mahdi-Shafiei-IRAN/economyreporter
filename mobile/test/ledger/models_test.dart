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

  test('a suggestion is complete only with account, kind and a positive amount', () {
    const full = SmsSuggestion(kind: EntryKind.expense, amountRial: 5, accountId: 'a');
    expect(full.isComplete, isTrue);
    expect(const SmsSuggestion(kind: EntryKind.expense, amountRial: 5).isComplete, isFalse);
    expect(const SmsSuggestion(amountRial: 5, accountId: 'a').isComplete, isFalse);
    expect(const SmsSuggestion(kind: EntryKind.expense, amountRial: 0, accountId: 'a').isComplete,
        isFalse);
    expect(
        const SmsSuggestion(kind: EntryKind.expense, amountRial: 5, accountId: 'a', notTxReason: 'otp')
            .isComplete,
        isFalse);
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
