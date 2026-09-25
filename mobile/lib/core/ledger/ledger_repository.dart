/// تنها راهِ نوشتن در جدول‌های دفترِ نسخه‌ی ۲. تراکنش فقط با متدهای «کارِ کاربر» ساخته،
/// عوض یا حذف می‌شود: [LedgerRepository.acceptSms]، [LedgerRepository.addEntry]،
/// [LedgerRepository.updateEntry]، [LedgerRepository.deleteEntry] (I1).
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../features/senders/data/allowed_sender.dart';
import '../sms/sms_parser.dart';
import 'ledger_math.dart';
import 'models.dart';
import 'sms_intake.dart';
import 'suggestion.dart';

const kLedgerV2Setting = 'ledger_v2';
const kLedgerStartSetting = 'ledger_start_date';

class LedgerRepository {
  LedgerRepository(this.db,
      {required this.deviceId, Uuid uuid = const Uuid(), DateTime Function()? clock})
      : _uuid = uuid,
        _clock = clock ?? DateTime.now;

  final Database db;
  final String deviceId;
  final Uuid _uuid;
  final DateTime Function() _clock;

  DateTime _now() => _clock().toUtc();

  // --- تنظیمات ---

  Future<String?> _setting(String key) async {
    final rows =
        await db.query('settings', columns: ['value'], where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> _setSetting(String key, String value) => db.insert(
      'settings', {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<bool> isEnabled() async => await _setting(kLedgerV2Setting) == '1';

  Future<void> setEnabled(bool on) => _setSetting(kLedgerV2Setting, on ? '1' : '0');

  Future<DateTime?> startDate() async {
    final v = await _setting(kLedgerStartSetting);
    return v == null ? null : DateTime.parse(v).toUtc();
  }

  /// تاریخِ شروع (ت۱): ذخیره‌شده؛ وگرنه از سرور؛ وگرنه اولِ ماهِ شمسیِ جاری.
  Future<DateTime> ensureStartDate({DateTime? fromServer}) async {
    final stored = await startDate();
    if (stored != null) return stored;
    final start = (fromServer ?? ledgerStartFor(_now())).toUtc();
    await _setSetting(kLedgerStartSetting, start.toIso8601String());
    return start;
  }

  // --- خواندن ---

  Future<List<LedgerAccount>> accounts() async {
    final rows = await db.query('wallets', where: 'is_deleted = 0', orderBy: 'created_at');
    return rows.map(LedgerAccount.fromWalletRow).toList();
  }

  Future<void> setArchived(String accountId, bool archived) => db.update(
      'wallets', {'archived': archived ? 1 : 0},
      where: 'id = ?', whereArgs: [accountId]);

  Future<List<Entry>> entries({String? accountId}) async {
    final rows = await db.query('ledger_entries',
        where: accountId == null ? 'deleted_at IS NULL' : 'deleted_at IS NULL AND account_id = ?',
        whereArgs: accountId == null ? null : [accountId]);
    return rows.map(Entry.fromMap).toList();
  }

  Future<Entry?> _entry(String id) async {
    final rows = await db.query('ledger_entries', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Entry.fromMap(rows.first);
  }

  Future<List<Checkpoint>> checkpoints({String? accountId}) async {
    final rows = await db.query('ledger_checkpoints',
        where: accountId == null ? 'deleted_at IS NULL' : 'deleted_at IS NULL AND account_id = ?',
        whereArgs: accountId == null ? null : [accountId]);
    return rows.map(Checkpoint.fromMap).toList();
  }

  Future<List<LedgerItem>> ledger(String accountId) async =>
      orderLedger(await entries(accountId: accountId), await checkpoints(accountId: accountId));

  Future<SuggestionContext> suggestionContext() async =>
      SuggestionContext.build(await accounts(), await entries(), await checkpoints());

  Future<List<SmsItem>> smsItems({SmsStatus? status}) async {
    final rows = await db.query('sms_items',
        where: status == null ? null : 'status = ?',
        whereArgs: status == null ? null : [status.name],
        orderBy: 'received_at DESC');
    return rows.map(SmsItem.fromMap).toList();
  }

  Future<SmsItem?> smsItem(String key) async {
    final rows = await db.query('sms_items', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : SmsItem.fromMap(rows.first);
  }

  // --- ورودِ پیامک (فقط sms_items؛ هرگز تراکنش) ---

  Future<List<IntakeResult>> intakeAll(
    Iterable<IncomingSms> batch, {
    required List<AllowedSender> allowed,
    Iterable<SmsDecision> serverDecisions = const [],
    DateTime? serverStartDate,
  }) async {
    final start = await ensureStartDate(fromServer: serverStartDate);
    final existing = await smsItems();
    final ctx = await suggestionContext();
    final sorted = [...batch]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    final results = <IntakeResult>[];
    for (final sms in sorted) {
      final r = intakeSms(sms,
          startDate: start,
          allowed: allowed,
          existing: existing,
          serverDecisions: serverDecisions,
          ctx: ctx);
      switch (r) {
        case IntakeNew(:final item):
          await db.insert('sms_items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
          existing.add(item);
        case IntakeKnown(:final item, :final bodyFilled) when bodyFilled:
          await db.update('sms_items', {'body': item.body}, where: 'key = ?', whereArgs: [item.key]);
          existing[existing.indexWhere((e) => e.key == item.key)] = item;
        case IntakeKnown() || IntakeIgnored():
          break;
      }
      results.add(r);
    }
    return results;
  }

  /// پیشنهادِ پیامک‌های منتظر با پارسرِ تازه؛ تصمیم‌دارها دست‌نخورده (I2).
  Future<int> refreshPendingSuggestions(
      {required List<AllowedSender> allowed, int parserVersion = kParserVersion}) async {
    final all = await smsItems();
    final ctx = await suggestionContext();
    var n = 0;
    for (final item in all) {
      final fresh =
          resuggest(item, allowed: allowed, others: all, ctx: ctx, parserVersion: parserVersion);
      if (fresh == null) continue;
      n += await db.update(
          'sms_items', {...fresh.suggestion.toColumns(), 'parser_version': fresh.parserVersion},
          where: 'key = ? AND status = ?', whereArgs: [item.key, SmsStatus.pending.name]);
    }
    return n;
  }

  // --- کارِ کاربر ---

  /// «ثبت»: یک تراکنش از پیامک (منتظر یا ردشده) می‌سازد. مانده‌ی بانک از پیشنهاد.
  Future<Entry> acceptSms(
    String key, {
    required String accountId,
    required EntryKind kind,
    required int amountRial,
    DateTime? occurredAt,
    int? bankBalanceAfter,
    String? note,
  }) async {
    if (amountRial <= 0) throw ArgumentError.value(amountRial, 'amountRial');
    final item = await smsItem(key);
    if (item == null) throw StateError('SMS item $key not found');
    if (item.status == SmsStatus.accepted) throw StateError('SMS item $key already accepted');
    final now = _now();
    final entry = Entry(
      id: _uuid.v4(),
      accountId: accountId,
      kind: kind,
      amountRial: amountRial,
      occurredAt: (occurredAt ?? item.suggestion.occurredAt ?? item.receivedAt).toUtc(),
      bankBalanceAfter: bankBalanceAfter ?? item.suggestion.balanceRial,
      source: EntrySource.sms,
      smsKey: key,
      note: note,
      createdByDevice: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await db.transaction((txn) async {
      await txn.insert('ledger_entries', entry.toMap());
      await txn.update(
          'sms_items',
          {
            'status': SmsStatus.accepted.name,
            'entry_id': entry.id,
            'reject_reason': null,
            'decided_at': now.toIso8601String(),
            'sync_status': 'pending',
          },
          where: 'key = ?',
          whereArgs: [key]);
    });
    return entry;
  }

  /// «تراکنش نیست» / «تکراری است». پیامکِ ثبت‌شده را باید با حذفِ تراکنشش رد کرد.
  Future<void> rejectSms(String key, RejectReason reason) async {
    final item = await smsItem(key);
    if (item == null) throw StateError('SMS item $key not found');
    if (item.status == SmsStatus.accepted) {
      throw StateError('SMS item $key is accepted; delete its entry instead');
    }
    await _markRejected(db, key, reason);
  }

  Future<void> _markRejected(DatabaseExecutor ex, String key, RejectReason reason) => ex.update(
      'sms_items',
      {
        'status': SmsStatus.rejected.name,
        'reject_reason': reason.code,
        'entry_id': null,
        'decided_at': _now().toIso8601String(),
        'sync_status': 'pending',
      },
      where: 'key = ?',
      whereArgs: [key]);

  /// افزودنِ دستی یا «اصلاح» (اصلاح یادداشتِ اجباری دارد؛ ۶.۳).
  Future<Entry> addEntry({
    required String accountId,
    required EntryKind kind,
    required int amountRial,
    required DateTime occurredAt,
    String? note,
    EntrySource source = EntrySource.manual,
  }) async {
    if (amountRial <= 0) throw ArgumentError.value(amountRial, 'amountRial');
    if (source == EntrySource.sms) throw ArgumentError('SMS entries are created by acceptSms');
    if (source == EntrySource.adjustment && (note == null || note.trim().isEmpty)) {
      throw ArgumentError('an adjustment needs a note');
    }
    final now = _now();
    final entry = Entry(
      id: _uuid.v4(),
      accountId: accountId,
      kind: kind,
      amountRial: amountRial,
      occurredAt: occurredAt.toUtc(),
      source: source,
      note: note,
      createdByDevice: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('ledger_entries', entry.toMap());
    return entry;
  }

  Future<void> updateEntry(Entry e) async {
    if (e.amountRial <= 0) throw ArgumentError.value(e.amountRial, 'amountRial');
    await db.update(
        'ledger_entries', {...e.copyWith(updatedAt: _now()).toMap(), 'sync_status': 'pending'},
        where: 'id = ?', whereArgs: [e.id]);
  }

  /// حذفِ نرم. تراکنشِ پیامکی: یعنی کاربر آن پیامک را رد کرده (`other`).
  Future<void> deleteEntry(String id) async {
    final e = await _entry(id);
    if (e == null || e.isDeleted) return;
    final now = _now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
          'ledger_entries', {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
          where: 'id = ?', whereArgs: [id]);
      if (e.smsKey != null) await _markRejected(txn, e.smsKey!, RejectReason.other);
    });
  }

  /// نقطه‌ی مانده‌ی دستی: «موجودیِ الان» یا «تطبیق با موجودیِ واقعی».
  Future<Checkpoint> addCheckpoint(
      {required String accountId, required int balanceRial, DateTime? at, String? note}) async {
    final now = _now();
    final cp = Checkpoint(
      id: _uuid.v4(),
      accountId: accountId,
      at: (at ?? now).toUtc(),
      balanceRial: balanceRial,
      note: note,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('ledger_checkpoints', cp.toMap());
    return cp;
  }

  Future<void> deleteCheckpoint(String id) async {
    final now = _now().toIso8601String();
    await db.update(
        'ledger_checkpoints', {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ?', whereArgs: [id]);
  }
}
