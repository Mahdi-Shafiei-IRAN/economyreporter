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

    test('force re-suggests a current pending item (accounts changed), never a decided one', () {
      final current = stored(SmsStatus.pending).withSuggestion(const SmsSuggestion(), kParserVersion);
      expect(resuggest(current, allowed: allowed, others: const [], ctx: ctx, force: true)!
          .suggestion
          .accountId, 'm1');
      expect(
          resuggest(stored(SmsStatus.accepted), allowed: allowed, others: const [], ctx: ctx, force: true),
          isNull);
    });
  });
}
