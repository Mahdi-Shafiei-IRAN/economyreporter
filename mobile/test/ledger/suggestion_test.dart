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
