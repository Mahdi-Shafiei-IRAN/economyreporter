/// حریمِ خصوصی (I6، سناریوی ۱۴): از هر چیزی که از گوشی به سرور می‌رود — کیف‌ها، بودجه، دفتر، تصمیمِ
/// پیامک، تنظیمات و گزارشِ سلامت — نه متنِ پیامک، نه فرستنده و نه شماره‌ی کاملِ کارت.
library;

import 'dart:convert';

import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/ledger_sync.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/store/app_store.dart';
import 'package:economy/core/sync/remote_sync_api.dart';
import 'package:economy/core/sync/sync_service.dart';
import 'package:economy/features/ledger/ledger_controller.dart';
import 'package:economy/features/ledger/ledger_health.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

/// هر چه به سرور می‌رود اینجا جمع می‌شود.
final _sent = <Object?>[];

class _Remote implements RemoteSyncApi, LedgerRemote {
  List<Map<String, dynamic>> _ok(List<Map<String, dynamic>> items) {
    _sent.addAll(items);
    return [for (final i in items) {'id': i['id'], 'key': i['key'], 'status': 'created'}];
  }

  @override
  Future<List<Map<String, dynamic>>> syncWallets({required List<Map<String, dynamic>> wallets}) async =>
      _ok(wallets);

  @override
  Future<List<Map<String, dynamic>>> syncBudgets({required List<Map<String, dynamic>> budgets}) async =>
      _ok(budgets);

  @override
  Future<PullPage> pullWallets({String? since}) async => PullPage.empty;

  @override
  Future<PullPage> pullBudgets({String? since}) async => PullPage.empty;

  @override
  Future<List<Map<String, dynamic>>> push(String what, List<Map<String, dynamic>> items) async => _ok(items);

  @override
  Future<PullPage> pull(String what, {String? since}) async => PullPage.empty;

  @override
  Future<Map<String, dynamic>> getSettings() async => {};

  @override
  Future<void> putSettings(Map<String, Object?> settings) async => _sent.add(settings);
}

void main() {
  final now = DateTime.utc(2026, 9, 24, 10);
  const pan = '6104337812345678';
  final inbox = [
    IncomingSms(
      sender: 'Bank Mellat',
      body: 'حساب1000005596\nبرداشت100,000\nمانده900,000\nکارت $pan',
      receivedAt: DateTime.utc(2026, 9, 23, 7),
    ),
    IncomingSms(
      sender: '+98200045678',
      body: 'خرید از فروشگاهِ کوروش مبلغ 250,000 ریال کارت ${pan.substring(12)}',
      receivedAt: DateTime.utc(2026, 9, 23, 8),
    ),
  ];

  setUpAll(initSqfliteFfiForTests);

  test('nothing sent to the server contains SMS text, sender or a full card number', () async {
    final db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    addTearDown(db.close);
    final store = AppStore(db, clock: () => now);
    final ledger = LedgerRepository(db, deviceId: 'dev', clock: () => now);
    await store.addAllowedSender('Bank Mellat', bankId: 'mellat');
    await store.addAllowedSender('+98200045678', bankId: 'saman');
    final c = LedgerController(ledger,
        allowedSenders: store.allowedSenders, readInbox: () async => inbox, clock: () => now);
    await c.setEnabled(true);
    await c.createAccount(ownerName: 'مهدی', label: 'ملت', bankId: 'mellat', accountRef: '1000005596',
        balanceRial: 1000000);
    final saman = await c.createAccount(
        ownerName: 'مهدی', label: 'سامان', bankId: 'saman', cardLast4: pan.substring(12));
    await c.setBudget('نان', 5000000);
    for (final i in [...c.pending]) {
      if (i.suggestion.isComplete) {
        await c.acceptSuggested(i);
      } else {
        await c.accept(i, accountId: saman.id, kind: EntryKind.expense, amountRial: 250000, note: 'خرید');
      }
    }
    expect(c.pendingCount, 0);

    _sent.clear();
    final remote = _Remote();
    expect((await SyncService(store: store, api: remote).sync()).failure, isNull);
    expect((await LedgerSyncService(ledger, remote).sync()).error, isNull);
    _sent.add(ledgerHealthReport(c).toJson());

    final everything = jsonEncode(_sent);
    expect(_sent.length, greaterThan(6)); // دو کیف، بودجه، تنظیمات، دو تراکنش، نقطه، دو تصمیم، سلامت
    for (final sms in inbox) {
      expect(everything.contains(sms.sender), isFalse, reason: sms.sender);
      for (final line in sms.body.split('\n')) {
        expect(everything.contains(line), isFalse, reason: line);
      }
    }
    expect(everything.contains(pan), isFalse);
    expect(everything.contains('کوروش'), isFalse);
    for (final m in _sent.whereType<Map>()) {
      expect(m.keys.toSet().intersection({'body', 'sender', 'sms_body', 'sms_sender', 'text'}), isEmpty);
    }
  });
}
