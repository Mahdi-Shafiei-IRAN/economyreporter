import 'package:economy/core/ledger/account_candidates.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/ledger/suggestion.dart';
import 'package:economy/core/sms/sms_parser.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const allowed = [
    AllowedSender(id: 's1', address: 'Bank Mellat', bankId: 'mellat'),
    AllowedSender(id: 's2', address: '+985000114', bankId: 'pasargad'),
  ];
  const mellat = LedgerAccount(
      id: 'm1', ownerName: 'مهدی', label: 'ملت', bankId: 'mellat', accountRef: '1000005596');
  final start = DateTime.utc(2026, 9, 22, 20, 30);
  const parser = SmsParser();

  List<SmsItem> intake(List<IncomingSms> sms, List<LedgerAccount> accounts) {
    final items = <SmsItem>[];
    for (final s in sms) {
      final r = intakeSms(s,
          startDate: start,
          allowed: allowed,
          existing: items,
          ctx: SuggestionContext(accounts: accounts));
      if (r is IntakeNew) items.add(r.item);
    }
    return items;
  }

  List<AccountCandidate> find(List<SmsItem> items, List<LedgerAccount> accounts) =>
      findAccountCandidates(
        pending: items,
        accounts: accounts,
        parse: (i) => parser.parse(
            sender: i.sender,
            body: i.body!,
            bankId: findAllowedSender(allowed, i.sender)?.bankId,
            receivedAt: i.receivedAt),
      );

  IncomingSms mellatSms(String ref, String line, String bal, int hour) => IncomingSms(
      sender: 'Bank Mellat',
      body: 'حساب$ref\n$line\nمانده$bal',
      receivedAt: DateTime.utc(2026, 9, 23, hour));

  test('an unknown account number becomes one candidate with its latest balance', () {
    final items = intake([
      mellatSms('2000000001', 'برداشت50,000', '450,000', 7),
      mellatSms('2000000001', 'برداشت10,000', '440,000', 9),
      mellatSms('1000005596', 'برداشت1,000', '1', 8), // حسابِ شناخته
    ], [mellat]);
    final c = find(items, [mellat]).single;
    expect(c.bankId, 'mellat');
    expect(c.accountRef, '2000000001');
    expect(c.smsCount, 2);
    expect(c.lastBalanceRial, 440000);
    expect(c.hasNumber, isTrue);
  });

  test('a bank with number-less SMS and no account at all is a candidate', () {
    const body = '*بانکداري ديجيتالي پاسارگاد*\nمبلغ 1,000,000 ریال از حساب دیجیتال با موفقیت '
        'پرداخت گردید.\nموجودی حساب دیجیتال: 49,000,000 ریال';
    final sms = IncomingSms(sender: '+985000114', body: body, receivedAt: DateTime.utc(2026, 9, 23, 7));
    final c = find(intake([sms], [mellat]), [mellat]).single;
    expect(c.bankId, 'pasargad');
    expect(c.hasNumber, isFalse);
    expect(c.lastBalanceRial, 49000000);

    const pas = LedgerAccount(
        id: 'p1', ownerName: 'زهرا', label: 'پاسارگاد', bankId: 'pasargad', archived: true);
    expect(find(intake([sms], [mellat, pas]), [mellat, pas]), isEmpty);
  });

  test('not-a-transaction SMS (one-time password) are not candidates', () {
    final items = intake([
      IncomingSms(
          sender: 'Bank Mellat',
          body: 'رمز پویا: 123456 حساب2000000001 مبلغ 5,000 ریال',
          receivedAt: DateTime.utc(2026, 9, 23, 7)),
    ], const []);
    expect(find(items, const []), isEmpty);
  });

  test('decided SMS are not candidates', () {
    final items = intake([mellatSms('2000000001', 'برداشت50,000', '450,000', 7)], [mellat]);
    final rejected = SmsItem.fromMap({
      ...items.single.toMap(),
      'status': SmsStatus.rejected.name,
      'reject_reason': 'not_tx',
    });
    expect(find([rejected], [mellat]), isEmpty);
  });
}
