import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/features/ledger/ledger_notifications.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

void main() {
  const allowed = [AllowedSender(id: 's1', address: 'Bank Mellat', bankId: 'mellat')];
  final now = DateTime.utc(2026, 9, 24, 10);
  late Database db;
  late LedgerRepository repo;
  final notified = <(SmsItem, LedgerAccount?)>[];

  IncomingSms sms(String body, DateTime at) =>
      IncomingSms(sender: 'Bank Mellat', body: body, receivedAt: at);

  Future<List<SmsItem>> take(IncomingSms s) => ledgerIntakeAndNotify(repo, s,
      allowed: allowed, notify: (item, account) async => notified.add((item, account)));

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    notified.clear();
    db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    await db.insert('wallets', {
      'id': 'm1',
      'owner_name': 'مهدی',
      'label': 'ملت',
      'bank_id': 'mellat',
      'account_ref': '1000005596',
      'created_at': now.toIso8601String(),
    });
    repo = LedgerRepository(db, deviceId: 'dev', clock: () => now);
  });

  tearDown(() => db.close());

  test('payload round-trip; v1 payloads are not ledger keys', () {
    expect(ledgerKeyOf(ledgerPayload('abc:1')), 'abc:1');
    expect(ledgerKeyOf('some-transaction-id'), isNull);
    expect(ledgerKeyOf(null), isNull);
  });

  test('a new SMS is stored pending and notified once, with its account', () async {
    final s = sms('حساب1000005596\nبرداشت100,000\nمانده900,000', DateTime.utc(2026, 9, 23, 7));
    expect(await take(s), hasLength(1));
    expect(await take(s), isEmpty); // همان پیامک از صندوق: دوباره نوتیفیکیشن نه
    expect(notified, hasLength(1));
    expect(notified.single.$2!.id, 'm1');
    expect(await repo.entries(), isEmpty);

    final (title, body) = ledgerNotificationText(notified.single.$1, notified.single.$2);
    expect(title, 'ملت: برداشت ۱۰٬۰۰۰ تومان');
    expect(body, contains('منتظرِ تأیید'));
    expect('$title $body', isNot(contains('1000005596'))); // متنِ پیامک روی صفحه‌ی قفل نه
  });

  test('"accept" button records the suggestion; "not a transaction" rejects', () async {
    await take(sms('حساب1000005596\nبرداشت100,000\nمانده900,000', DateTime.utc(2026, 9, 23, 7)));
    await take(sms('حساب1000005596\nبرداشت50,000\nمانده850,000', DateTime.utc(2026, 9, 23, 8)));
    final a = notified[0].$1, b = notified[1].$1;

    expect(await applyLedgerAction(repo, kLedgerActionAccept, a.key), isTrue);
    expect(await applyLedgerAction(repo, kLedgerActionReject, b.key), isTrue);
    expect((await repo.entries()).single.amountRial, 100000);
    expect((await repo.smsItem(b.key))!.status, SmsStatus.rejected);

    // دوباره زدن (نوتیفیکیشنِ کهنه) کاری نمی‌کند.
    expect(await applyLedgerAction(repo, kLedgerActionAccept, a.key), isFalse);
    expect(await applyLedgerAction(repo, kLedgerActionAccept, b.key), isFalse);
    expect(await repo.entries(), hasLength(1));
  });

  test('"accept" does nothing for an incomplete suggestion', () async {
    await take(sms('حساب2000000009\nبرداشت100,000\nمانده900,000', DateTime.utc(2026, 9, 23, 7)));
    final item = notified.single.$1;
    expect(item.suggestion.isComplete, isFalse);
    expect(await applyLedgerAction(repo, kLedgerActionAccept, item.key), isFalse);
    expect((await repo.smsItem(item.key))!.status, SmsStatus.pending);
  });
}
