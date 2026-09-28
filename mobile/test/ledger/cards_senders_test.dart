/// طرح ۱۲.۱۰: حذفِ کارت با تراکنش‌هایش، وضعیتِ هر فرستنده، و فرستنده‌های صندوق برای افزودنِ دستی.
library;

import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/sms/raw_sms.dart';
import 'package:economy/core/store/app_store.dart';
import 'package:economy/features/ledger/banks_view.dart';
import 'package:economy/features/ledger/ledger_controller.dart';
import 'package:economy/features/ledger/sender_ops.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:economy/features/senders/data/sender_candidates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28, 10); // ۱۴۰۵/۰۷/۰۶
  final t1 = DateTime.utc(2026, 9, 23, 7), t2 = DateTime.utc(2026, 9, 27, 8);
  late Database db;
  late AppStore store;
  late LedgerController c;
  var inbox = <RawSms>[];

  RawSms sms(String sender, String account, String line, String balance, DateTime at) =>
      RawSms(sender: sender, body: 'حساب$account\n$line\nمانده$balance', receivedAt: at);

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    store = AppStore(db);
    for (final (id, owner, user, bank, ref) in const [
      ('m1', 'مهدی', 'u1', 'mellat', '1000005596'),
      ('z1', 'زهرا', 'u2', 'saman', null),
    ]) {
      await db.insert('wallets', {
        'id': id,
        'owner_name': owner,
        'owner_user_id': user,
        'label': id == 'm1' ? 'ملت' : 'سامان',
        'bank_id': bank,
        'account_ref': ref,
        'created_at': now.toIso8601String(),
      });
    }
    inbox = [
      sms('Bank Mellat', '1000005596', 'برداشت100,000', '900,000', t1),
      // همان بانک و همان حساب، از سرشماره‌ی دیگر.
      sms('+98200045', '1000005596', 'واریز300,000', '1,200,000', t2),
      // حسابی که هنوز ساخته نشده.
      sms('B.Pasargad', '2000000001', 'برداشت50,000', '450,000', t2),
      const RawSms(sender: 'Digikala', body: 'خرید شما ثبت شد'),
      const RawSms(sender: 'Digikala', body: 'کد تخفیف'),
    ];
    c = LedgerController(
      LedgerRepository(db, deviceId: 'dev', clock: () => now),
      allowedSenders: store.allowedSenders,
      readInbox: () async => [
        for (final r in inbox) IncomingSms(sender: r.sender, body: r.body, receivedAt: r.receivedAt ?? now),
      ],
      clock: () => now,
      people: () => (meName: 'مهدی', meUserId: 'u1', members: const []),
      senders: ledgerSenderOps(store, readInbox: () async => inbox, me: () async => (meName: 'مهدی', meUserId: 'u1')),
    );
    await c.setEnabled(true);
    for (final (address, bank) in const [
      ('Bank Mellat', 'mellat'),
      ('+98200045', 'mellat'),
      ('B.Pasargad', 'pasargad'),
      ('Saman', 'saman'),
    ]) {
      await c.allowSender(address, bank);
    }
  });

  tearDown(() => db.close());

  AllowedSender sender(String address) => c.banks.firstWhere((b) => b.address == address);

  group('which card did each sender go to', () {
    test('two senders of one bank can feed the same card; an unknown account and a silent sender explain themselves',
        () async {
      await c.setBalanceNow('m1', 1200000);
      final mellatItem = c.pending.firstWhere((i) => i.sender == 'Bank Mellat');
      await c.acceptSuggested(mellatItem);

      final a = c.senderStatus(sender('Bank Mellat'));
      expect((a.total, a.accepted, a.pending), (1, 1, 0));
      expect(a.accounts.map((x) => x.id), ['m1']);

      final b = c.senderStatus(sender('+98200045'));
      expect((b.total, b.pending), (1, 1));
      expect(b.accounts.map((x) => x.id), ['m1']); // همان کارت → دو فرستنده، یک کارت
      expect(senderStatusText(b), contains('کارت: ملت ۵۵۹۶'));

      final p = c.senderStatus(sender('B.Pasargad'));
      expect(p.accounts, isEmpty);
      expect(p.unknownAccount, 1);
      expect(senderStatusText(p), contains('حسابش هنوز ساخته نشده'));

      final s = c.senderStatus(sender('Saman'));
      expect(s.total, 0);
      expect(senderStatusText(s), contains('پیامکی از این فرستنده خوانده نشده'));
    });
  });

  group('deleting a card', () {
    test('its entries, balance points and card go together; its SMS become rejected; all of it syncs', () async {
      await c.setBalanceNow('m1', 1200000);
      for (final i in [...c.pending.where((i) => i.suggestion.accountId == 'm1')]) {
        await c.acceptSuggested(i);
      }
      await c.addManual(accountId: 'm1', kind: EntryKind.expense, amountRial: 7000, occurredAt: now);
      expect(c.entryCountOf('m1'), 3);
      expect(c.monthExpense, 107000);
      final smsKeys = [for (final e in await c.repo.entries(accountId: 'm1')) if (e.smsKey != null) e.smsKey!];
      expect(smsKeys, hasLength(2));

      expect(await c.deleteAccount('m1'), 3);

      expect(c.accounts.map((v) => v.account.id), ['z1']);
      expect(await c.repo.entries(accountId: 'm1'), isEmpty);
      expect(await c.repo.checkpoints(accountId: 'm1'), isEmpty);
      expect(c.monthExpense, 0);
      expect(c.monthIncome, 0);
      for (final k in smsKeys) {
        expect((await c.repo.smsItem(k))!.status, SmsStatus.rejected);
      }
      // حذف به سرور هم می‌رود: کیف، تراکنش‌ها، نقطه و تصمیم‌ها منتظرِ ارسال.
      final wallet = (await db.query('wallets', where: "id = 'm1'")).single;
      expect((wallet['is_deleted'], wallet['sync_status']), (1, 'pending'));
      expect((await c.repo.pendingEntries()).where((e) => e.accountId == 'm1' && e.isDeleted), hasLength(3));
      expect(await c.repo.pendingCheckpoints(), isNotEmpty);
      expect(await c.repo.pendingDecisions(), hasLength(2));
      expect(c.dashboard(now).shown.expand((p) => p.cards).map((x) => x.account.id), ['z1']);
    });

    test("another member's card cannot be deleted from this phone", () async {
      await expectLater(c.deleteAccount('z1'), throwsStateError);
      expect(c.accounts.map((v) => v.account.id), containsAll(['m1', 'z1']));
    });

    test('entries of a card deleted elsewhere (server) are not counted', () async {
      await c.addManual(accountId: 'm1', kind: EntryKind.expense, amountRial: 7000, occurredAt: now);
      await db.update('wallets', {'is_deleted': 1}, where: "id = 'm1'");
      await c.load();
      expect(c.monthExpense, 0);
      expect(c.dashboard(now).expenseRial, 0);
    });
  });

  test('inbox senders for manual adding: every sender that is not chosen yet, busiest first', () async {
    final list = listInboxSenders(inbox: inbox, allowed: c.banks);
    expect(list.map((s) => s.address), ['Digikala']);
    expect(list.single.count, 2);
    expect((await c.inboxSenders()).single.address, 'Digikala');

    final all = listInboxSenders(inbox: [...inbox, const RawSms(sender: '0200045', body: 'x')], allowed: const []);
    expect(all.firstWhere((s) => s.address == '+98200045').count, 2); // +98… و 0… یک فرستنده
  });
}
