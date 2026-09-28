/// طرح ۱۲.۹: دادهٔ صفحه‌ی اصلی — تفکیکِ عضو، کارت، ماه و روز.
library;

import 'package:economy/core/ledger/dashboard.dart';
import 'package:economy/core/ledger/ledger_math.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // مهر ۱۴۰۵ = ۲۲ سپتامبر ۲۰:۳۰ UTC تا ۲۲ اکتبر ۲۰:۳۰ UTC.
  final from = DateTime.utc(2026, 9, 22, 20, 30), to = DateTime.utc(2026, 10, 22, 20, 30);
  const mellat = LedgerAccount(id: 'm1', ownerName: 'مهدی', ownerUserId: 'u1', label: 'ملت', bankId: 'mellat');
  const cash = LedgerAccount(id: 'm2', ownerName: 'مهدی', ownerUserId: 'u1', label: 'نقد');
  const saman = LedgerAccount(id: 'z1', ownerName: 'زهرا', ownerUserId: 'u2', label: 'سامان', bankId: 'saman');
  const legacy = LedgerAccount(id: 'b1', ownerName: 'بابا', label: 'تجارت'); // بی‌شناسه‌ی کاربر

  var n = 0;
  Entry e(String acc, EntryKind k, int amount, DateTime at, {bool transfer = false}) => Entry(
        id: 'e${n++}',
        accountId: acc,
        kind: k,
        amountRial: amount,
        occurredAt: at,
        source: EntrySource.manual,
        createdAt: at,
        updatedAt: at,
        isTransfer: transfer,
      );
  Checkpoint cp(String acc, int balance, DateTime at) =>
      Checkpoint(id: 'c${n++}', accountId: acc, at: at, balanceRial: balance, createdAt: at, updatedAt: at);

  final d1 = DateTime.utc(2026, 9, 25, 8); // ۳ مهر
  final d2 = DateTime.utc(2026, 9, 27, 21); // ۶ مهر ساعتِ ۰۰:۳۰ (به وقتِ ایران)
  final ledgers = {
    'm1': orderLedger([
      e('m1', EntryKind.expense, 100000, d1),
      e('m1', EntryKind.income, 500000, d2),
      e('m1', EntryKind.expense, 70000, DateTime.utc(2026, 9, 20)), // شهریور
    ], [cp('m1', 1000000, DateTime.utc(2026, 9, 19))]),
    'm2': orderLedger([e('m2', EntryKind.expense, 30000, d1, transfer: true)], []),
    'z1': orderLedger([e('z1', EntryKind.expense, 200000, d2)], [cp('z1', 700000, from)]),
    'b1': orderLedger([], []),
  };

  Dashboard build({String? person, String? account}) => buildDashboard(
        accounts: const [saman, legacy, mellat, cash],
        ledgers: ledgers,
        isMine: (a) => a.ownerUserId == 'u1',
        from: from,
        to: to,
        personKey: person,
        accountId: account,
      );

  test('the whole family: me first, net = income − expense of this month (no transfers)', () {
    final d = build();
    expect(d.people.map((p) => p.name), ['مهدی', 'بابا', 'زهرا']);
    expect(d.people.first.isMe, isTrue);
    expect(d.incomeRial, 500000);
    expect(d.expenseRial, 300000); // ۱۰۰ + ۲۰۰؛ انتقال و شهریور نه
    expect(d.netRial, 200000);
    expect(d.count, 4); // انتقال هم در فهرست هست
    // موجودی: ملت ۱٬۰۰۰ − ۷۰ − ۱۰۰ + ۵۰۰ = ۱٬۳۳۰ هزار؛ سامان ۵۰۰ هزار؛ نقد و تجارت نامعلوم.
    expect(d.balanceRial, 1330000 + 500000);
    expect(d.unknownBalances, 2);
    expect(d.shown.map((p) => p.key), [kMePersonKey, 'name:بابا', 'u2']);
    expect(d.shown.first.cards.map((c) => c.account.id), ['m1', 'm2']);
    expect(d.shown.first.cards.first.entries.map((x) => x.amountRial), [500000, 100000]); // جدیدترین اول
  });

  test('one member, then one card', () {
    final z = build(person: 'u2');
    expect(z.shown.single.name, 'زهرا');
    expect(z.cardChoices.map((a) => a.id), ['z1']);
    expect(z.expenseRial, 200000);
    expect(z.netRial, -200000);
    expect(z.balanceRial, 500000);

    final m = build(person: kMePersonKey, account: 'm1');
    expect(m.cardChoices.map((a) => a.id), ['m1', 'm2']); // تراشه‌ها همه‌ی کارت‌های همان عضو
    expect(m.shown.single.cards.single.account.id, 'm1');
    expect(m.incomeRial, 500000);
    expect(m.expenseRial, 100000);

    // کارتی که مالِ عضوِ انتخاب‌شده نیست نادیده گرفته می‌شود.
    expect(build(person: 'u2', account: 'm1').shown.single.cards.single.account.id, 'z1');
    // عضوِ ناشناس = همه.
    expect(build(person: 'u9').shown, hasLength(3));
  });

  test('days are Iran days, newest first, with their own totals', () {
    final d = build();
    expect(d.days, hasLength(2));
    expect(d.days.first.day, DateTime.utc(2026, 9, 27, 20, 30)); // ۶ مهر به وقتِ ایران
    expect(d.days.first.entries.map((x) => x.account.id).toSet(), {'m1', 'z1'});
    expect(d.days.first.incomeRial, 500000);
    expect(d.days.first.expenseRial, 200000);
    expect(d.days.last.entries.map((x) => x.entry.isTransfer), containsAll([true, false]));
    expect(d.days.last.expenseRial, 100000); // انتقال شمرده نمی‌شود
  });

  test('one person, one chip: my accounts with and without a user id; a member by name', () {
    // بی‌شناسه، روی همین گوشی (با نامِ دیگری ساخته شده بود).
    const oldMine = LedgerAccount(id: 'o1', ownerName: 'Mahdi', label: 'قدیمی');
    const zahraByName = LedgerAccount(id: 'z2', ownerName: 'زهرا', label: 'ملیِ زهرا');
    final d = buildDashboard(
      accounts: const [oldMine, mellat, saman, zahraByName],
      ledgers: ledgers,
      isMine: (a) => a.ownerUserId == null ? a.ownerName == 'Mahdi' : a.ownerUserId == 'u1',
      from: from,
      to: to,
      meName: 'مهدی',
    );
    expect(d.people.map((p) => p.key), [kMePersonKey, 'u2']);
    expect(d.people.first.name, 'مهدی');
    expect(d.shown.last.cards.map((c) => c.account.id), ['z1', 'z2']);
  });

  test('family members come in as people even without a card; an unlinked card joins its owner by name', () {
    const babaByName = LedgerAccount(id: 'b2', ownerName: 'بابا', label: 'ملی');
    final d = buildDashboard(
      accounts: const [mellat, babaByName],
      ledgers: ledgers,
      isMine: (a) => a.ownerUserId == 'u1',
      from: from,
      to: to,
      members: const [(key: 'u2', name: 'زهرا'), (key: 'u3', name: 'بابا')],
    );
    expect(d.people.map((p) => p.key), [kMePersonKey, 'u3', 'u2']);
    expect(d.shown.map((p) => p.key), [kMePersonKey, 'u3']); // زهرا کارتی ندارد
    expect(buildDashboard(
      accounts: const [mellat],
      ledgers: ledgers,
      isMine: (a) => a.ownerUserId == 'u1',
      from: from,
      to: to,
      personKey: 'u2',
      members: const [(key: 'u2', name: 'زهرا')],
    ).shown, isEmpty);
  });

  test('an empty month still lists members and their cards', () {
    final d = buildDashboard(
      accounts: const [mellat],
      ledgers: ledgers,
      isMine: (_) => true,
      from: DateTime.utc(2026, 11, 21, 20, 30),
      to: DateTime.utc(2026, 12, 21, 20, 30),
    );
    expect(d.count, 0);
    expect(d.days, isEmpty);
    expect(d.shown.single.cards.single.entries, isEmpty);
    expect(d.netRial, 0);
  });
}
