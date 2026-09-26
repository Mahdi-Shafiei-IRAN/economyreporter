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
      await repo.acceptSms(i.key,
          accountId: 'm1', kind: EntryKind.expense, amountRial: i.suggestion.amountRial!);
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

  test('a new account is a synced wallet; forced refresh re-suggests pending SMS for it', () async {
    await db.delete('wallets');
    await repo.intakeAll([mellat('برداشت100,000', 900000, t1)], allowed: allowed);
    expect((await repo.smsItems()).single.suggestion.unknownAccountNumber, isTrue);

    final a = await repo.createAccount(
        ownerName: ' مهدی ', label: 'ملت', bankId: 'mellat', accountRef: '1000005596', cardLast4: '');
    expect(a.cardLast4, isNull);
    final row = (await db.query('wallets')).single;
    expect(row['sync_status'], 'pending');
    expect(row['owner_name'], 'مهدی');

    expect(await repo.refreshPendingSuggestions(allowed: allowed), 0);
    expect(await repo.refreshPendingSuggestions(allowed: allowed, force: true), 1);
    expect((await repo.smsItems()).single.suggestion.accountId, a.id);
  });

  test('acceptSuggested uses the suggestion; an incomplete one is refused', () async {
    await repo.intakeAll([
      mellat('برداشت100,000', 900000, t1),
      IncomingSms(sender: 'Bank Mellat', body: 'رمز پویا: 123456', receivedAt: t2),
    ], allowed: allowed);
    final items = {for (final i in await repo.smsItems()) i.suggestion.looksLikeTx: i};
    final e = await repo.acceptSuggested(items[true]!.key);
    expect(e.amountRial, 100000);
    expect(e.bankBalanceAfter, 900000);
    expect(() => repo.acceptSuggested(items[false]!.key), throwsStateError);
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
