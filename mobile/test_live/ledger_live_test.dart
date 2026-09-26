/// تستِ زنده‌ی همگام‌سازیِ دفترِ نسخه‌ی ۲ با سرورِ واقعیِ Django (سناریوی ۷: حذف و نصبِ دوباره).
/// جزو تست‌های عادی نیست.
///
/// اجرا: سرورِ آزمایشی با دیتابیسِ جدا و کاربرِ 09120000001 با رمزِ Live@12345 در یک خانواده:
///   LIVE_API=http://127.0.0.1:8765/api/v1 flutter test test_live/ledger_live_test.dart
library;

import 'dart:io';

import 'package:economy/core/auth/auth_repository.dart';
import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/ledger/ledger_math.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/ledger_sync.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/network/api_client.dart';
import 'package:economy/core/store/app_store.dart';
import 'package:economy/core/sync/remote_sync_api.dart';
import 'package:economy/core/sync/sync_service.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../test/helpers/db_test_helper.dart';
import '../test/helpers/in_memory_token_store.dart';

class _Phone {
  final LedgerRepository ledger;
  final LedgerSyncService ledgerSync;
  final SyncService walletSync; // کیف‌ها (حساب‌ها) و بودجه

  _Phone(this.ledger, this.ledgerSync, this.walletSync);

  static Future<_Phone> login(String base, String deviceId) async {
    final tokens = InMemoryTokenStore();
    final api = ApiClient(baseUrl: base, tokenStore: tokens);
    await AuthRepository(api, tokens).login(phone: '09120000001', password: 'Live@12345');
    final db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    final ledger = LedgerRepository(db, deviceId: deviceId);
    return _Phone(
      ledger,
      LedgerSyncService(ledger, DioLedgerRemote(api.dio)),
      SyncService(store: AppStore(db), api: DioRemoteSyncApi(api.dio)),
    );
  }

  Future<void> syncAll() async {
    expect((await walletSync.sync()).failure, isNull);
    final r = await ledgerSync.sync();
    expect(r.error, isNull);
    expect(r.failed, 0);
  }
}

void main() {
  final base = Platform.environment['LIVE_API'];
  setUpAll(initSqfliteFfiForTests);

  test('reinstall restores accounts, archived, entries, categories, checkpoints, decisions, settings',
      () async {
    const allowed = [AllowedSender(id: 's1', address: 'Bank Mellat', bankId: 'mellat')];
    final now = DateTime.now().toUtc();
    // مبلغ و شماره‌ی حساب در هر اجرا یکتا تا دیتابیسِ آزمایشی تکراری نبیند.
    final ref = '10${now.millisecondsSinceEpoch % 100000000}';
    IncomingSms sms(String line, String bal, Duration ago) => IncomingSms(
        sender: 'Bank Mellat', body: 'حساب$ref\n$line\nمانده$bal', receivedAt: now.subtract(ago));
    final inbox = [
      sms('برداشت100,000', '900,000', const Duration(minutes: 50)),
      sms('برداشت9,999', '1', const Duration(minutes: 40)),
      sms('برداشت50,000', '850,000', const Duration(minutes: 30)),
    ];

    final a = await _Phone.login(base!, 'live-A-${now.millisecondsSinceEpoch}');
    await a.ledger.setEnabled(true);
    final acc = await a.ledger.createAccount(
        ownerName: 'مهدی', label: 'ملت', bankId: 'mellat', accountRef: ref);
    final ignored = await a.ledger.createAccount(ownerName: 'مهدی', label: 'کنار', bankId: 'saman');
    await a.ledger.setArchived(ignored.id, true);
    await a.ledger.intakeAll(inbox, allowed: allowed);
    final items = (await a.ledger.smsItems())..sort((x, y) => x.receivedAt.compareTo(y.receivedAt));
    final bread = (await a.ledger.categories()).firstWhere((c) => c.name == 'نان').id;
    await a.ledger.acceptSms(items[0].key,
        accountId: acc.id, kind: EntryKind.expense, amountRial: 100000, categoryIds: [bread], note: 'نان');
    await a.ledger.rejectSms(items[1].key, RejectReason.notTx);
    await a.ledger.acceptSuggested(items[2].key);
    await a.ledger.addCheckpoint(accountId: acc.id, balanceRial: 850000, at: now);
    await a.ledger.setSetupDone();
    await a.syncAll();
    expect(await a.ledger.unsyncedCount(), 0);

    // «حذف و نصبِ دوباره»: گوشیِ تازه با همان کاربر.
    // مثلِ main.dart: گوشیِ تازه خودش نسخه‌ی ۲ را روشن و تاریخِ این ماه را می‌گذارد؛ سرور زودتری را نگه می‌دارد.
    final b = await _Phone.login(base, 'live-B-${now.millisecondsSinceEpoch}');
    await b.ledger.setEnabled(true);
    await b.ledger.ensureStartDate();
    await b.syncAll();
    expect(await b.ledger.isSetupDone(), isTrue);
    expect(await b.ledger.startDate(), await a.ledger.startDate());

    final accounts = {for (final x in await b.ledger.accounts()) x.id: x};
    expect(accounts[acc.id]!.accountRef, ref);
    expect(accounts[ignored.id]!.archived, isTrue);

    await b.ledger.intakeAll(inbox, allowed: allowed);
    final bItems = {for (final i in await b.ledger.smsItems()) i.key: i};
    expect(bItems[items[0].key]!.status, SmsStatus.accepted);
    expect(bItems[items[1].key]!.status, SmsStatus.rejected);
    expect(bItems[items[2].key]!.status, SmsStatus.accepted);

    final entries = await b.ledger.entries(accountId: acc.id);
    expect(entries, hasLength(2));
    final breadEntry = entries.firstWhere((e) => e.note == 'نان');
    expect((await b.ledger.allocations())[breadEntry.id]!.single.name, 'نان');
    expect(breadEntry.bankBalanceAfter, 900000);
    expect(currentBalance(await b.ledger.ledger(acc.id))!.balanceRial, 850000);
    expect(discrepancies(await b.ledger.ledger(acc.id)), isEmpty);

    // چیزی برای ارسالِ دوباره روی گوشیِ تازه نمانده.
    expect(await b.ledger.unsyncedCount(), 0);
  });
}
