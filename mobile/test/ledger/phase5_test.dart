/// فاز ۵: سلامت روی نسخه‌ی ۲، پاک شدنِ دفتر با عوض شدنِ کاربر، انتخابِ بانک‌ها با مخزنِ واقعی.
library;

import 'dart:convert';

import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/diagnostics/device_health.dart';
import 'package:economy/core/family/health_api.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/sms/raw_sms.dart';
import 'package:economy/core/store/app_store.dart';
import 'package:economy/features/ledger/ledger_controller.dart';
import 'package:economy/features/ledger/ledger_health.dart';
import 'package:economy/features/ledger/sender_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

class _FakeHealthApi implements HealthApi {
  final List<DeviceHealthReport> sent = [];
  bool offline = false;

  @override
  Future<void> report({required String deviceId, required DeviceHealthReport report}) async {
    if (offline) throw StateError('offline');
    sent.add(report);
  }

  @override
  Future<List<RemoteDeviceHealth>> family() async => const [];
}

void main() {
  var now = DateTime.utc(2026, 9, 28, 10); // ۱۴۰۵/۰۷/۰۶
  final t1 = DateTime.utc(2026, 9, 23, 7), t2 = DateTime.utc(2026, 9, 27, 8);
  late Database db;
  late AppStore store;
  late LedgerController c;
  var inbox = <RawSms>[];

  RawSms mellat(String line, String balance, DateTime at) => RawSms(
      sender: 'Bank Mellat', body: 'حساب1000005596\n$line\nمانده$balance', receivedAt: at);

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    now = DateTime.utc(2026, 9, 28, 10);
    db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    store = AppStore(db);
    await db.insert('wallets', {
      'id': 'm1',
      'owner_name': 'مهدی',
      'label': 'ملت',
      'bank_id': 'mellat',
      'account_ref': '1000005596',
      'created_at': now.toIso8601String(),
    });
    inbox = [
      mellat('برداشت100,000', '900,000', t1),
      mellat('واریز300,000', '1,200,000', t2),
      const RawSms(sender: 'Digikala', body: 'خرید مبلغ 990,000 ریال با کد تخفیف'),
    ];
    c = LedgerController(
      LedgerRepository(db, deviceId: 'dev', clock: () => now),
      allowedSenders: store.allowedSenders,
      readInbox: () async => [
        for (final r in inbox) IncomingSms(sender: r.sender, body: r.body, receivedAt: r.receivedAt ?? now),
      ],
      clock: () => now,
      senders: ledgerSenderOps(store,
          readInbox: () async => inbox, me: () async => (meName: 'مهدی', meUserId: 'u1')),
    );
    await c.setEnabled(true);
  });

  tearDown(() => db.close());

  group('choosing banks with the real repository', () {
    test('bank senders are suggested; allow → SMS become pending; dismiss hides; remove undoes', () async {
      final cands = await c.senders!.candidates();
      expect(cands.map((s) => s.address), ['Bank Mellat', 'Digikala']);
      expect(cands.first.bankId, 'mellat');

      await c.allowSender('Bank Mellat', 'mellat');
      expect(c.banks.single.ownerUserId, 'u1');
      expect(c.pending, hasLength(2));

      await c.senders!.dismiss('Digikala');
      expect(await c.senders!.candidates(), isEmpty);

      await c.senders!.remove(c.banks.single.id);
      expect(await store.allowedSenders(), isEmpty);
    });
  });

  group('health on v2', () {
    test('issues come from the ledger; nothing identifying leaves the phone', () async {
      await c.allowSender('Bank Mellat', 'mellat');
      final r = ledgerHealthReport(c, appVersion: '1.0.28');
      final codes = r.issues.map((i) => i.code).toSet();
      expect(codes, containsAll(['pending_old', 'no_anchor', 'sync_stale']));
      expect(codes, isNot(contains('no_senders')));
      expect(r.level, HealthLevel.warn);
      expect(r.banks.single.name, 'بانک ملت');
      expect(r.banks.single.sms, 2);
      expect(r.banks.single.missing, 2);
      expect(r.accounts.single.title, contains('ملت'));

      final json = jsonEncode(r.toJson());
      for (final secret in ['1000005596', 'Bank Mellat', 'برداشت100', 'مانده900', '900,000', '1,200,000', 'Digikala']) {
        expect(json.contains(secret), isFalse, reason: secret);
      }

      await c.setBalanceNow('m1', 1200000);
      await c.acceptMany(c.readyToAccept);
      final ok = ledgerHealthReport(c);
      expect(ok.issues.map((i) => i.code), ['sync_stale']);
    });

    test('no bank chosen is a problem', () {
      expect(ledgerHealthReport(c).level, HealthLevel.bad);
    });

    test('sent at most every 6 hours (unless forced); offline is silent', () async {
      final api = _FakeHealthApi();
      expect(await reportLedgerHealthIfDue(c, api: api, deviceId: 'dev'), isTrue);
      now = now.add(const Duration(hours: 5));
      expect(await reportLedgerHealthIfDue(c, api: api, deviceId: 'dev'), isFalse);
      expect(await reportLedgerHealthIfDue(c, api: api, deviceId: 'dev', force: true), isTrue);
      now = now.add(const Duration(hours: 7));
      api.offline = true;
      expect(await reportLedgerHealthIfDue(c, api: api, deviceId: 'dev'), isFalse);
      expect(api.sent, hasLength(2));
    });
  });

  test('another user on this phone: the previous ledger is wiped, accounts and banks stay', () async {
    await c.allowSender('Bank Mellat', 'mellat');
    await c.setBalanceNow('m1', 1200000);
    await c.acceptMany(c.readyToAccept);
    await c.finishSetup();
    await c.repo.setSyncCursor('entries', '5');
    expect(await c.repo.entries(), isNotEmpty);

    await c.repo.resetForAccountSwitch();
    await c.load();
    expect(await c.repo.entries(), isEmpty);
    expect(await c.repo.checkpoints(), isEmpty);
    expect(await c.repo.smsItems(), isEmpty);
    expect(await c.repo.syncCursor('entries'), isNull);
    expect(await c.repo.startDate(), isNull);
    expect(c.setupDone, isFalse);
    expect(await c.repo.unsyncedCount(), 0);
    expect(c.accounts.single.account.id, 'm1');
    expect(c.banks, hasLength(1));

    // صندوق دوباره خوانده می‌شود: همه منتظرِ تأییدِ کاربرِ تازه.
    await c.syncInbox();
    expect(c.pending, hasLength(2));
    expect(c.pending.every((i) => i.status == SmsStatus.pending), isTrue);
  });
}
