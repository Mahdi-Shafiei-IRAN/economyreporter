/// فاز ۴: همگام‌سازیِ دفتر و بازگشت بعد از نصبِ دوباره (سناریوهای ۷ و ۹ و ۱۴).
library;

import 'package:dio/dio.dart';
import 'package:economy/core/database/app_database.dart';
import 'package:economy/core/ledger/ledger_math.dart';
import 'package:economy/core/ledger/ledger_repository.dart';
import 'package:economy/core/ledger/ledger_sync.dart';
import 'package:economy/core/ledger/models.dart';
import 'package:economy/core/ledger/sms_intake.dart';
import 'package:economy/core/sync/remote_sync_api.dart';
import 'package:economy/features/senders/data/allowed_sender.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/db_test_helper.dart';

/// سرورِ حافظه‌ای با همان قاعده‌های `apps.ledger` (upsert، stale، cursor).
class FakeLedgerServer implements LedgerRemote {
  final Map<String, Map<String, Map<String, dynamic>>> tables = {
    'entries': {},
    'checkpoints': {},
    'decisions': {},
  };
  Map<String, dynamic> settings = {'enabled': false, 'start_date': null, 'setup_done': false};
  final List<Map<String, dynamic>> pushedLog = [];
  int _tick = 0;
  bool offline = false;

  String _key(String what, Map<String, dynamic> item) =>
      what == 'decisions' ? item['key'] as String : item['id'] as String;

  String? _versionOf(String what, Map<String, dynamic> row) =>
      (what == 'decisions' ? row['decided_at'] : row['client_updated_at']) as String?;

  void _check() {
    if (offline) {
      throw DioException(
          requestOptions: RequestOptions(path: '/'), type: DioExceptionType.connectionError);
    }
  }

  @override
  Future<List<Map<String, dynamic>>> push(String what, List<Map<String, dynamic>> items) async {
    _check();
    pushedLog.addAll(items);
    final table = tables[what]!;
    return [
      for (final item in items)
        () {
          final k = _key(what, item);
          final existing = table[k];
          final incoming = _versionOf(what, item);
          final current = existing == null ? null : _versionOf(what, existing);
          if (existing != null && current != null && incoming != null &&
              DateTime.parse(current).isAfter(DateTime.parse(incoming))) {
            return what == 'decisions'
                ? {'key': k, 'status': 'stale', 'decision': existing}
                : {...existing, 'status': 'stale'};
          }
          table[k] = {...item, '_order': ++_tick};
          return {if (what == 'decisions') 'key': k else 'id': k, 'status': existing == null ? 'created' : 'updated'};
        }(),
    ];
  }

  @override
  Future<PullPage> pull(String what, {String? since}) async {
    _check();
    final after = since == null ? 0 : int.parse(since);
    final rows = tables[what]!.values.where((r) => (r['_order'] as int) > after).toList()
      ..sort((a, b) => (a['_order'] as int).compareTo(b['_order'] as int));
    return PullPage(
      results: [for (final r in rows) Map<String, dynamic>.from(r)..remove('_order')],
      cursor: rows.isEmpty ? since : '${rows.last['_order']}',
    );
  }

  @override
  Future<Map<String, dynamic>> getSettings() async {
    _check();
    return Map.of(settings);
  }

  /// مثلِ سرور: زودترین تاریخِ شروع و «راهنما دیده شده» می‌ماند.
  @override
  Future<void> putSettings(Map<String, Object?> s) async {
    _check();
    final old = settings;
    settings = {...settings, ...s};
    final a = old['start_date'] as String?, b = s['start_date'] as String?;
    if (a != null && (b == null || DateTime.parse(a).isBefore(DateTime.parse(b)))) {
      settings['start_date'] = a;
    }
    if (old['setup_done'] == true) settings['setup_done'] = true;
  }
}

void main() {
  const allowed = [AllowedSender(id: 's1', address: 'Bank Mellat', bankId: 'mellat')];
  final now = DateTime.utc(2026, 9, 24, 10);
  final t1 = DateTime.utc(2026, 9, 23, 7), t2 = DateTime.utc(2026, 9, 23, 8), t3 = DateTime.utc(2026, 9, 23, 9);

  IncomingSms mellat(String line, String balance, DateTime at) => IncomingSms(
      sender: 'Bank Mellat', body: 'حساب1000005596\n$line\nمانده$balance', receivedAt: at);

  final inbox = [
    mellat('برداشت100,000', '900,000', t1),
    mellat('برداشت9,999', '1', t2), // «تراکنش نیست» (کاربر رد کرد)
    mellat('برداشت50,000', '850,000', t3),
  ];

  setUpAll(initSqfliteFfiForTests);

  /// یک «گوشی»: دیتابیسِ تازه با همان حساب (کیف‌ها با همگام‌سازیِ نسخه‌ی ۱ برمی‌گردند).
  Future<(LedgerRepository, LedgerSyncService)> phone(FakeLedgerServer server,
      {String device = 'A', DateTime? at}) async {
    final db = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    addTearDown(db.close);
    await db.insert('wallets', {
      'id': 'm1',
      'owner_name': 'مهدی',
      'label': 'ملت',
      'bank_id': 'mellat',
      'account_ref': '1000005596',
      'created_at': now.toIso8601String(),
    });
    final repo = LedgerRepository(db, deviceId: device, clock: () => at ?? now);
    return (repo, LedgerSyncService(repo, server, clock: () => at ?? now));
  }

  Future<Map<String, String>> catIds(LedgerRepository r) async =>
      {for (final c in await r.categories()) c.name: c.id};

  test('scenario 7: uninstall + reinstall brings back everything; only new SMS are pending', () async {
    final server = FakeLedgerServer();
    final (a, syncA) = await phone(server);
    await a.setEnabled(true);
    await a.intakeAll(inbox, allowed: allowed);
    final items = (await a.smsItems())..sort((x, y) => x.receivedAt.compareTo(y.receivedAt));
    await a.acceptSms(items[0].key,
        accountId: 'm1',
        kind: EntryKind.expense,
        amountRial: 100000,
        categoryIds: [(await catIds(a))['نان']!]);
    await a.rejectSms(items[1].key, RejectReason.notTx);
    await a.acceptSuggested(items[2].key);
    await a.addCheckpoint(accountId: 'm1', balanceRial: 850000, at: now);
    await a.setSetupDone();
    final r = await syncA.sync();
    expect(r.error, isNull);
    expect(r.sent, 2 + 1 + 3);

    // گوشیِ تازه (نصبِ دوباره) در ماهِ بعد: اپ در شروع نسخه‌ی ۲ را روشن و تاریخِ این ماه را می‌گذارد
    // (مثلِ main.dart)؛ اول همگام‌سازی، بعد صندوق — یا برعکس (پایینی).
    final (b, syncB) = await phone(server, device: 'B', at: now.add(const Duration(days: 40)));
    await b.setEnabled(true);
    await b.ensureStartDate();
    expect(await b.startDate(), isNot(await a.startDate()));
    await syncB.sync();
    // سرور تاریخِ شروعِ اصلی را نگه داشت و گوشی همان را گرفت (I5).
    expect(await b.isSetupDone(), isTrue);
    expect(await b.startDate(), await a.startDate());
    expect(DateTime.parse(server.settings['start_date'] as String), await a.startDate());
    await b.intakeAll([...inbox, mellat('برداشت5,000', '845,000', now.add(const Duration(hours: 1)))],
        allowed: allowed);

    final bItems = {for (final i in await b.smsItems()) i.key: i};
    expect(bItems[items[0].key]!.status, SmsStatus.accepted);
    expect(bItems[items[1].key]!.status, SmsStatus.rejected);
    expect(bItems[items[1].key]!.rejectReason, RejectReason.notTx);
    expect(bItems.values.where((i) => i.status == SmsStatus.pending), hasLength(1));
    expect(await b.entries(), hasLength(2));
    final breadEntry = (await b.entries()).firstWhere((e) => e.amountRial == 100000);
    expect((await b.allocations())[breadEntry.id]!.single.name, 'نان');
    expect(currentBalance(await b.ledger('m1'))!.balanceRial, currentBalance(await a.ledger('m1'))!.balanceRial);
    // دریافت چیزی برای ارسالِ دوباره نمی‌سازد.
    server.pushedLog.clear();
    await syncB.sync();
    expect(server.pushedLog, isEmpty);
  });

  test('reinstall, inbox read BEFORE sync: pending items take the server decisions', () async {
    final server = FakeLedgerServer();
    final (a, syncA) = await phone(server);
    await a.setEnabled(true);
    await a.intakeAll(inbox, allowed: allowed);
    final items = (await a.smsItems())..sort((x, y) => x.receivedAt.compareTo(y.receivedAt));
    await a.rejectSms(items[1].key, RejectReason.notTx);
    await a.acceptSuggested(items[0].key);
    await syncA.sync();

    final (b, syncB) = await phone(server, device: 'B');
    await b.setEnabled(true); // کاربر خودش روشن کرد و صندوق خوانده شد
    // پیامکِ اول چند دقیقه دیرتر از صندوقِ گوشیِ تازه خوانده می‌شود (کلیدِ متفاوت).
    await b.intakeAll([
      IncomingSms(sender: inbox[0].sender, body: inbox[0].body, receivedAt: t1.add(const Duration(minutes: 3))),
      inbox[1],
      inbox[2],
    ], allowed: allowed);
    expect((await b.smsItems()).every((i) => i.status == SmsStatus.pending), isTrue);

    await syncB.sync();
    final bItems = await b.smsItems();
    expect(bItems.where((i) => i.status == SmsStatus.pending), hasLength(1));
    final first = bItems.firstWhere((i) => i.contentHash == items[0].contentHash);
    expect(first.status, SmsStatus.accepted);
    expect(first.key, items[0].key); // همان کلیدِ سرور تا دوباره فرستاده نشود
    expect((await b.smsItem(items[1].key))!.status, SmsStatus.rejected);
  });

  test('an edit made while offline is sent later; nothing is lost', () async {
    final server = FakeLedgerServer();
    final (a, syncA) = await phone(server);
    await a.setEnabled(true);
    server.offline = true;
    final e = await a.addEntry(accountId: 'm1', kind: EntryKind.expense, amountRial: 7000, occurredAt: t1);
    final r = await syncA.sync();
    expect(r.error, 'به سرور وصل نشد');
    expect(await a.pendingEntries(), hasLength(1));
    expect(await a.syncStatus(), contains('به سرور وصل نشد'));

    server.offline = false;
    await syncA.sync();
    expect(await a.pendingEntries(), isEmpty);
    expect(server.tables['entries']![e.id]!['amount_rial'], 7000);
  });

  test('conflict: the newer edit wins on both phones', () async {
    final server = FakeLedgerServer();
    var clockA = now, clockB = now;
    final dbA = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    final dbB = await openAppDatabase(path: inMemoryDatabasePath, singleInstance: false);
    addTearDown(dbA.close);
    addTearDown(dbB.close);
    final a = LedgerRepository(dbA, deviceId: 'A', clock: () => clockA);
    final b = LedgerRepository(dbB, deviceId: 'B', clock: () => clockB);
    final syncA = LedgerSyncService(a, server), syncB = LedgerSyncService(b, server);
    await a.setEnabled(true);
    final e = await a.addEntry(accountId: 'm1', kind: EntryKind.expense, amountRial: 1000, occurredAt: t1);
    await syncA.sync();
    await syncB.sync();

    clockB = now.add(const Duration(minutes: 5));
    await b.updateEntry((await b.entries()).single.copyWith(note: 'جدیدتر (B)'));
    clockA = now.add(const Duration(minutes: 1));
    await a.updateEntry((await a.entries()).single.copyWith(note: 'قدیمی‌تر (A)'));

    await syncB.sync(); // B زودتر رسید
    await syncA.sync(); // A دیرتر ولی ویرایشش قدیمی‌تر → stale → نسخه‌ی B
    expect((await a.entries()).single.note, 'جدیدتر (B)');
    expect(server.tables['entries']![e.id]!['note'], 'جدیدتر (B)');
    expect(await a.pendingEntries(), isEmpty);
  });

  test('scenario 14: nothing sent to the server contains SMS text or sender', () async {
    final server = FakeLedgerServer();
    final (a, syncA) = await phone(server);
    await a.setEnabled(true);
    await a.intakeAll(inbox, allowed: allowed);
    for (final i in await a.smsItems()) {
      if (i.suggestion.isComplete) {
        await a.acceptSuggested(i.key);
      } else {
        await a.rejectSms(i.key, RejectReason.notTx);
      }
    }
    await syncA.sync();
    expect(server.pushedLog, isNotEmpty);
    final everything = server.pushedLog.map((m) => m.toString()).join('\n');
    for (final sms in inbox) {
      expect(everything.contains(sms.body), isFalse);
      for (final line in sms.body.split('\n')) {
        expect(everything.contains(line), isFalse, reason: line);
      }
    }
    expect(everything.contains('Bank Mellat'), isFalse);
    for (final m in server.pushedLog) {
      expect(m.keys.toSet().intersection({'body', 'sender', 'sms_body', 'sms_sender'}), isEmpty);
    }
  });

  test('settings: v2 stays on whatever the server says; start date = the earliest one', () async {
    final server = FakeLedgerServer()
      ..settings = {'enabled': false, 'start_date': '2026-08-22T20:30:00.000Z', 'setup_done': true};
    final (a, syncA) = await phone(server);
    await a.setEnabled(true);
    await a.ensureStartDate(); // ۱ مهرِ همین گوشی
    await syncA.sync();
    expect(await a.isEnabled(), isTrue);
    expect(await a.startDate(), DateTime.utc(2026, 8, 22, 20, 30)); // ۱ شهریور، از سرور
    expect(await a.isSetupDone(), isTrue);
    expect(server.settings['start_date'], '2026-08-22T20:30:00.000Z');
  });
}
