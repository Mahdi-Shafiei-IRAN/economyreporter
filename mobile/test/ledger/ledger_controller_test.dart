import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/ledger/suggestion.dart';
import 'package:economy/features/ledger/ledger_controller.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

void main() {
  const allowed = [AllowedSender(id: 's1', address: 'Bank Mellat', bankId: 'mellat')];
  final now = DateTime.utc(2026, 9, 24, 10); // ۱۴۰۵/۰۷/۰۲
  final t1 = DateTime.utc(2026, 9, 23, 7), t2 = DateTime.utc(2026, 9, 23, 8);
  late Database db;
  late LedgerController c;
  var inbox = <IncomingSms>[];

  IncomingSms mellat(String account, String line, String balance, DateTime at) => IncomingSms(
      sender: 'Bank Mellat', body: 'حساب$account\n$line\nمانده$balance', receivedAt: at);

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    await db.insert('wallets', {
      'id': 'm1',
      'owner_name': 'مهدی',
      'label': 'ملت',
      'bank_id': 'mellat',
      'account_ref': '1000005596',
      'created_at': now.toIso8601String(),
    });
    inbox = [
      mellat('1000005596', 'برداشت100,000', '900,000', t1),
      mellat('1000005596', 'واریز300,000', '1,200,000', t2),
      mellat('1000005596', 'برداشت1,000', '5', DateTime.utc(2026, 9, 1)), // ماهِ قبل
    ];
    c = LedgerController(LedgerRepository(db, deviceId: 'dev', clock: () => now),
        allowedSenders: () async => allowed, readInbox: () async => inbox, clock: () => now);
    await c.load();
  });

  tearDown(() => db.close());

  test('off by default; turning on reads this month as pending, nothing recorded', () async {
    expect(c.enabled, isFalse);
    await c.setEnabled(true);
    expect(c.enabled, isTrue);
    expect(c.startDate, DateTime.utc(2026, 9, 22, 20, 30));
    expect(c.pendingCount, 2);
    expect(await c.repo.entries(), isEmpty);
    final v = c.accounts.single;
    expect(v.needsAnchor, isTrue);
    expect(v.lastBankBalance, 1200000);
  });

  test('phase 2 done-condition: balance now = last bank SMS, accepting keeps it, no window', () async {
    await c.setEnabled(true);
    final v = c.accounts.single;
    await c.setBalanceNow('m1', v.lastBankBalance!);
    expect(c.accounts.single.balance!.balanceRial, 1200000);

    await c.acceptMany(c.readyToAccept);
    expect(c.pendingCount, 0);
    expect(c.accounts.single.balance!.balanceRial, 1200000);
    expect(c.accounts.single.discrepancyCount, 0);
    expect(c.monthIncome, 300000);
    expect(c.monthExpense, 100000);
  });

  test('a newer pending SMS is shown next to the balance, not added to it', () async {
    await c.setEnabled(true);
    await c.setBalanceNow('m1', 1200000);
    await c.intake([mellat('1000005596', 'برداشت200,000', '1,000,000', now.add(const Duration(hours: 1)))]);
    final v = c.accounts.single;
    expect(v.balance!.balanceRial, 1200000);
    expect(v.unconfirmedBalance, 1000000);
  });

  test('reject and accept with edits', () async {
    await c.setEnabled(true);
    final items = [...c.pending]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    await c.reject(items[0], RejectReason.notTx);
    await c.accept(items[1], accountId: 'm1', kind: EntryKind.income, amountRial: 300000, note: 'حقوق');
    expect(c.pendingCount, 0);
    final e = (await c.repo.entries()).single;
    expect(e.note, 'حقوق');
    expect(e.bankBalanceAfter, 1200000);
  });

  test('unknown account number: prefill, create account (with balance) re-suggests it', () async {
    inbox = [mellat('2000000001', 'برداشت50,000', '450,000', t1)];
    await c.setEnabled(true);
    final item = c.pending.single;
    expect(item.suggestion.unknownAccountNumber, isTrue);
    final p = c.prefillFrom(item);
    expect(p.bankId, 'mellat');
    expect(p.accountRef, '2000000001');
    expect(p.balanceRial, 450000);

    final a = await c.createAccount(
        ownerName: 'زهرا', label: 'ملت ۲', bankId: p.bankId, accountRef: p.accountRef, balanceRial: 450000);
    expect(c.pending.single.suggestion.accountId, a.id);
    expect(c.pending.single.suggestion.isComplete, isTrue);
    expect(c.accounts.firstWhere((v) => v.account.id == a.id).balance!.balanceRial, 450000);
  });

  test('archived account: its SMS go to a separate list and can be rejected in one go', () async {
    await c.setEnabled(true);
    await c.setArchived('m1', true);
    expect(c.pendingCount, 0);
    expect(c.pendingArchived, hasLength(2));
    expect(c.pendingArchived.first.suggestion.notTxReason, NotTxReason.archived);
    expect(await c.rejectArchived(), 2);
    expect(c.pending, isEmpty);
    expect(await c.repo.entries(), isEmpty);
  });

  test('jalaliMonthRange: first of this month to first of next', () {
    final (from, to) = jalaliMonthRange(now);
    expect(from, DateTime.utc(2026, 9, 22, 20, 30));
    expect(to, DateTime.utc(2026, 10, 22, 20, 30)); // ۱ آبان
  });
}
