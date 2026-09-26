/// تنها راهِ نوشتن در جدول‌های دفترِ نسخه‌ی ۲. تراکنش فقط با متدهای «کارِ کاربر» ساخته،
/// عوض یا حذف می‌شود: [LedgerRepository.acceptSms]، [LedgerRepository.addEntry]،
/// [LedgerRepository.updateEntry]، [LedgerRepository.deleteEntry] (I1).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../features/budgets/data/budget.dart';
import '../../features/categories/data/category.dart';
import '../../features/senders/data/allowed_sender.dart';
import '../family/family_api.dart';
import '../sms/digit_utils.dart';
import '../sms/sms_parser.dart';
import 'ledger_math.dart';
import 'models.dart';
import 'sms_intake.dart';
import 'suggestion.dart';

const kLedgerV2Setting = 'ledger_v2';
const kLedgerStartSetting = 'ledger_start_date';
const kLedgerSetupDoneSetting = 'ledger_setup_done';
const kLedgerSettingsDirty = 'ledger_settings_dirty';

/// شناسه‌ی کاربرِ همین گوشی (ProfileService می‌نویسد؛ همان `SettingKeys.meUserId`).
const kMeUserIdSetting = 'me_user_id';

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

  /// تنظیمِ کلید-مقدارِ دلخواه (مثلاً زمانِ آخرین گزارشِ سلامت).
  Future<String?> value(String key) => _setting(key);

  Future<void> setValue(String key, String value) => _setSetting(key, value);

  Future<bool> isEnabled() async => await _setting(kLedgerV2Setting) == '1';

  Future<void> setEnabled(bool on) async {
    await _setSetting(kLedgerV2Setting, on ? '1' : '0');
    await _markSettingsDirty();
  }

  /// راهنمای سه‌قدمیِ اولین اجرا دیده/رد شده؟
  Future<bool> isSetupDone() async => await _setting(kLedgerSetupDoneSetting) == '1';

  Future<void> setSetupDone() async {
    await _setSetting(kLedgerSetupDoneSetting, '1');
    await _markSettingsDirty();
  }

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
    if (fromServer == null) await _markSettingsDirty();
    return start;
  }

  // --- همگام‌سازی (فاز ۴؛ docs/v2-design.md ۱۲.۷) ---

  Future<void> _markSettingsDirty() => _setSetting(kLedgerSettingsDirty, '1');

  /// تنظیماتی که باید به سرور برود (null = چیزی عوض نشده).
  Future<Map<String, Object?>?> dirtySettings() async {
    if (await _setting(kLedgerSettingsDirty) != '1') return null;
    return {
      'enabled': await isEnabled(),
      'start_date': (await startDate())?.toIso8601String(),
      'setup_done': await isSetupDone(),
    };
  }

  Future<void> markSettingsSent() => _setSetting(kLedgerSettingsDirty, '0');

  /// تنظیماتِ سرور (نصبِ دوباره، I5): تاریخِ شروع = زودترینِ گوشی و سرور، و «راهنما دیده شده» اگر
  /// یک‌بار دیده شده. پس گوشیِ تازه که در شروع تاریخِ این ماه را گذاشته، تاریخِ اصلی را پس می‌گیرد.
  /// از فاز ۵ نسخه‌ی ۲ همیشه روشن است؛ `enabled`ِ سرور (برای کاربرانِ قدیمی false) نادیده گرفته می‌شود.
  Future<void> applyRemoteSettings(Map<String, dynamic> j) async {
    final start = j['start_date'];
    if (start is String && start.isNotEmpty) {
      final remote = DateTime.parse(start).toUtc();
      final local = await startDate();
      if (local == null || remote.isBefore(local)) {
        await _setSetting(kLedgerStartSetting, remote.toIso8601String());
      }
    }
    if (j['setup_done'] == true) await _setSetting(kLedgerSetupDoneSetting, '1');
  }

  /// خروج و ورود با کاربرِ دیگر روی همین گوشی: دادهٔ دفترِ کاربرِ قبلی پاک می‌شود (روی سرور به نامِ
  /// خودش هست) تا به نامِ کاربرِ تازه فرستاده نشود (طرح ۱۲.۸). حساب‌ها (کیف‌ها) را نسخه‌ی ۱ جابه‌جا می‌کند.
  Future<void> resetForAccountSwitch() async {
    await db.transaction((txn) async {
      for (final t in const [
        'ledger_entries',
        'ledger_checkpoints',
        'ledger_entry_categories',
        'sms_items',
        'ledger_remote_decisions',
      ]) {
        await txn.delete(t);
      }
      await txn.delete('settings', where: "key LIKE 'ledger_cursor_%'");
      await txn.delete('settings', where: 'key IN (?, ?, ?, ?, ?)', whereArgs: [
        kLedgerStartSetting,
        kLedgerSetupDoneSetting,
        kLedgerSettingsDirty,
        'ledger_last_sync',
        'ledger_health_reported_at',
      ]);
    });
  }

  /// ردیف‌هایی که هنوز به سرور نرفته‌اند (تراکنش، نقطه، تصمیمِ پیامک).
  Future<int> unsyncedCount() async {
    int count(List<Map<String, Object?>> r) => r.first['n'] as int? ?? 0;
    return count(await db.rawQuery(
            "SELECT COUNT(*) AS n FROM ledger_entries WHERE sync_status = 'pending'")) +
        count(await db.rawQuery(
            "SELECT COUNT(*) AS n FROM ledger_checkpoints WHERE sync_status = 'pending'")) +
        count(await db.rawQuery(
            "SELECT COUNT(*) AS n FROM sms_items WHERE sync_status = 'pending' AND status != 'pending'"));
  }

  /// نتیجه‌ی آخرین همگام‌سازی (JSON) برای نمایش در تنظیمات.
  Future<String?> syncStatus() => _setting('ledger_last_sync');

  Future<void> setSyncStatus(String json) => _setSetting('ledger_last_sync', json);

  Future<String?> syncCursor(String what) => _setting('ledger_cursor_$what');

  Future<void> setSyncCursor(String what, String cursor) => _setSetting('ledger_cursor_$what', cursor);

  Future<List<Entry>> pendingEntries() async => [
        for (final r in await db.query('ledger_entries', where: "sync_status = 'pending'"))
          Entry.fromMap(r),
      ];

  Future<List<Checkpoint>> pendingCheckpoints() async => [
        for (final r in await db.query('ledger_checkpoints', where: "sync_status = 'pending'"))
          Checkpoint.fromMap(r),
      ];

  /// تصمیم‌های پیامک که هنوز به سرور نرفته‌اند (پیامکِ هنوز منتظر، تصمیم ندارد).
  Future<List<SmsItem>> pendingDecisions() async => [
        for (final r in await db.query('sms_items',
            where: "sync_status = 'pending' AND status != ?", whereArgs: [SmsStatus.pending.name]))
          SmsItem.fromMap(r),
      ];

  /// نامِ دسته‌های یک تراکنش (دسته‌ها با نام همگام می‌شوند؛ شناسه روی هر گوشی فرق دارد).
  Future<List<String>> categoryNamesOf(String entryId) async => [
        for (final r in await db.rawQuery('''
          SELECT c.name AS n FROM ledger_entry_categories lec
          JOIN categories c ON c.id = lec.category_id WHERE lec.entry_id = ? ORDER BY c.name
        ''', [entryId]))
          r['n']! as String,
      ];

  /// «ارسال شد» — فقط اگر ردیف در این فاصله دوباره ویرایش نشده باشد.
  Future<void> markEntrySent(Entry e, {bool rejected = false}) => db.update(
      'ledger_entries', {'sync_status': rejected ? 'rejected' : 'synced'},
      where: 'id = ? AND updated_at = ?', whereArgs: [e.id, e.toMap()['updated_at']]);

  Future<void> markCheckpointSent(Checkpoint c, {bool rejected = false}) => db.update(
      'ledger_checkpoints', {'sync_status': rejected ? 'rejected' : 'synced'},
      where: 'id = ? AND updated_at = ?', whereArgs: [c.id, c.toMap()['updated_at']]);

  Future<void> markDecisionSent(SmsItem i) => db.update('sms_items', {'sync_status': 'synced'},
      where: 'key = ? AND status = ? AND decided_at IS ?',
      whereArgs: [i.key, i.status.name, i.decidedAt?.toIso8601String()]);

  Future<String> _categoryIdByName(DatabaseExecutor ex, String name) async {
    final rows = await ex.query('categories', columns: ['id'], where: 'name = ?', whereArgs: [name], limit: 1);
    if (rows.isNotEmpty) return rows.first['id']! as String;
    final id = _uuid.v4();
    await ex.insert('categories',
        {'id': id, 'name': name, 'is_system': 0, 'created_at': _now().toIso8601String()});
    return id;
  }

  DateTime? _remoteTime(Object? v) =>
      (v is String && v.isNotEmpty) ? DateTime.parse(v).toUtc() : null;

  /// ردیفِ محلیِ «در صفِ ارسال» که از نسخه‌ی سرور جدیدتر است دست نمی‌خورد (ارسال می‌شود).
  Future<bool> _localIsNewer(String table, String id, DateTime? remoteClientUpdated) async {
    final rows = await db.query(table,
        columns: ['sync_status', 'updated_at'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty || rows.first['sync_status'] != 'pending') return false;
    final local = DateTime.parse(rows.first['updated_at']! as String).toUtc();
    return remoteClientUpdated == null || local.isAfter(remoteClientUpdated);
  }

  Future<void> applyRemoteEntry(Map<String, dynamic> j) async {
    final id = j['id'].toString();
    final clientUpdated = _remoteTime(j['client_updated_at']);
    if (await _localIsNewer('ledger_entries', id, clientUpdated)) return;
    final updated = clientUpdated ?? _now();
    final existing = await _entry(id);
    final e = Entry(
      id: id,
      accountId: j['account_id'].toString(),
      kind: EntryKind.values.byName(j['kind'] as String),
      isTransfer: j['is_transfer'] == true,
      transferPairId: j['transfer_pair_id']?.toString(),
      amountRial: (j['amount_rial'] as num).toInt(),
      occurredAt: _remoteTime(j['occurred_at'])!,
      bankBalanceAfter: (j['bank_balance_after'] as num?)?.toInt(),
      source: EntrySource.values.byName(j['source'] as String),
      smsKey: (j['sms_key'] as String?)?.isEmpty ?? true ? null : j['sms_key'] as String,
      note: (j['note'] as String?)?.isEmpty ?? true ? null : j['note'] as String,
      createdByDevice: j['created_by_device'] as String?,
      createdAt: existing?.createdAt ?? updated,
      updatedAt: updated,
      deletedAt: _remoteTime(j['deleted_at']),
    );
    final names = [for (final n in (j['categories'] as List? ?? const [])) n.toString()];
    await db.transaction((txn) async {
      await txn.insert('ledger_entries', {...e.toMap(), 'sync_status': 'synced'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await _writeCategories(txn, e, [for (final n in names) await _categoryIdByName(txn, n)]);
    });
  }

  Future<void> applyRemoteCheckpoint(Map<String, dynamic> j) async {
    final id = j['id'].toString();
    final clientUpdated = _remoteTime(j['client_updated_at']);
    if (await _localIsNewer('ledger_checkpoints', id, clientUpdated)) return;
    final updated = clientUpdated ?? _now();
    final cp = Checkpoint(
      id: id,
      accountId: j['account_id'].toString(),
      at: _remoteTime(j['at'])!,
      balanceRial: (j['balance_rial'] as num).toInt(),
      note: (j['note'] as String?)?.isEmpty ?? true ? null : j['note'] as String,
      createdAt: updated,
      updatedAt: updated,
      deletedAt: _remoteTime(j['deleted_at']),
    );
    await db.insert('ledger_checkpoints', {...cp.toMap(), 'sync_status': 'synced'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// تصمیمِ سرور: نگه داشته می‌شود تا پیامکش از صندوق خوانده شود، و اگر همان پیامک اینجا «منتظر»
  /// است همین حالا گرفته می‌شود (نصبِ دوباره یا گوشیِ دوم؛ I5).
  Future<void> applyRemoteDecision(Map<String, dynamic> j) async {
    final d = SmsDecision.fromPayload({
      ...j,
      'reject_reason': (j['reject_reason'] as String?)?.isEmpty ?? true ? null : j['reject_reason'],
    });
    await db.insert(
        'ledger_remote_decisions',
        {
          'key': d.key,
          'content_hash': d.contentHash,
          'received_at': d.receivedAt.toIso8601String(),
          'status': d.status.name,
          'reject_reason': d.rejectReason?.code,
          'entry_id': d.entryId,
          'decided_at': d.decidedAt?.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (d.status == SmsStatus.pending) return;
    for (final item in await db.query('sms_items',
        where: 'content_hash = ? AND status = ?', whereArgs: [d.contentHash, SmsStatus.pending.name])) {
      final local = SmsItem.fromMap(item);
      if (!isSameSms(local.contentHash, local.receivedAt, d.contentHash, d.receivedAt)) continue;
      final taken = local.key != d.key &&
          (await db.query('sms_items', where: 'key = ?', whereArgs: [d.key], limit: 1)).isNotEmpty;
      await db.update(
          'sms_items',
          {
            if (!taken) 'key': d.key,
            'status': d.status.name,
            'entry_id': d.entryId,
            'reject_reason': d.rejectReason?.code,
            'decided_at': d.decidedAt?.toIso8601String(),
            'sync_status': 'synced',
          },
          where: 'key = ?',
          whereArgs: [local.key]);
    }
  }

  Future<List<SmsDecision>> remoteDecisions() async => [
        for (final r in await db.query('ledger_remote_decisions'))
          SmsDecision.fromPayload({
            'key': r['key'],
            'content_hash': r['content_hash'],
            'received_at': r['received_at'],
            'status': r['status'],
            'reject_reason': r['reject_reason'],
            'entry_id': r['entry_id'],
            'decided_at': r['decided_at'],
          }),
      ];

  // --- خواندن ---

  Future<List<LedgerAccount>> accounts() async {
    final rows = await db.query('wallets', where: 'is_deleted = 0', orderBy: 'created_at');
    return rows.map(LedgerAccount.fromWalletRow).toList();
  }

  /// حسابِ تازه = کیفِ تازه (`wallets`، با همان ستون‌های همگام‌سازیِ نسخه‌ی ۱ تا به سرور برود).
  Future<LedgerAccount> createAccount({
    required String ownerName,
    required String label,
    String? ownerUserId,
    String? bankId,
    String? cardLast4,
    String? accountRef,
  }) async {
    String? clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    final now = _now().toIso8601String();
    final account = LedgerAccount(
      id: _uuid.v4(),
      ownerName: ownerName.trim(),
      ownerUserId: ownerUserId,
      label: label.trim(),
      bankId: bankId,
      cardLast4: clean(cardLast4),
      accountRef: clean(accountRef),
    );
    await db.insert('wallets', {
      'id': account.id,
      'owner_name': account.ownerName,
      'owner_user_id': account.ownerUserId,
      'label': account.label,
      'bank_id': account.bankId,
      'card_last4': account.cardLast4,
      'account_ref': account.accountRef,
      'created_at': now,
      'updated_at': now,
      'client_updated_at': now,
      'is_deleted': 0,
      'sync_status': 'pending',
      'archived': 0,
    });
    return account;
  }

  /// «پیگیری نشود» — همراهِ کیف به سرور می‌رود (همگام‌سازیِ کیف‌ها).
  Future<void> setArchived(String accountId, bool archived) {
    final now = _now().toIso8601String();
    return db.update(
        'wallets',
        {
          'archived': archived ? 1 : 0,
          'updated_at': now,
          'client_updated_at': now,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [accountId]);
  }

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

  /// من و اعضای خانواده (ProfileService از سرور می‌گیرد و در تنظیمات نگه می‌دارد).
  Future<({String? meName, String? meUserId, List<FamilyMember> members})> people() async => (
        meName: await _setting('me_name'),
        meUserId: await _setting(kMeUserIdSetting),
        members: FamilyMember.decodeList(await _setting('family_members')),
      );

  /// نقشِ من در خانواده ('owner' = مدیر).
  Future<String?> myRole() => _setting('my_role');

  /// پیامکِ این گوشی مالِ حساب‌های کاربرِ همین گوشی است؛ حساب‌های بقیه‌ی خانواده (که مدیر از سرور
  /// می‌گیرد) در پیشنهاد شرکت نمی‌کنند.
  Future<List<LedgerAccount>> myAccounts() async {
    final me = await _setting(kMeUserIdSetting);
    return [
      for (final a in await accounts())
        if (a.ownerUserId == null || me == null || a.ownerUserId == me) a,
    ];
  }

  Future<SuggestionContext> suggestionContext() async =>
      SuggestionContext.build(await myAccounts(), await entries(), await checkpoints());

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
    final decisions = [...serverDecisions, ...await remoteDecisions()];
    final sorted = [...batch]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    final results = <IntakeResult>[];
    for (final sms in sorted) {
      final r = intakeSms(sms,
          startDate: start,
          allowed: allowed,
          existing: existing,
          serverDecisions: decisions,
          ctx: ctx);
      switch (r) {
        case IntakeNew(:final item):
          await db.insert(
              'sms_items',
              {
                ...item.toMap(),
                // تصمیمی که از سرور آمده دوباره فرستاده نمی‌شود.
                'sync_status': item.status == SmsStatus.pending ? 'pending' : 'synced',
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
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

  /// پیشنهادِ پیامک‌های منتظر با پارسرِ تازه (یا همه با [force]، بعد از عوض شدنِ حساب‌ها،
  /// نقطه‌ها یا تراکنش‌ها)؛ تصمیم‌دارها دست‌نخورده (I2).
  Future<int> refreshPendingSuggestions(
      {required List<AllowedSender> allowed,
      int parserVersion = kParserVersion,
      bool force = false}) async {
    final all = await smsItems();
    final ctx = await suggestionContext();
    var n = 0;
    for (final item in all) {
      final fresh = resuggest(item,
          allowed: allowed, others: all, ctx: ctx, parserVersion: parserVersion, force: force);
      if (fresh == null) continue;
      n += await db.update(
          'sms_items', {...fresh.suggestion.toColumns(), 'parser_version': fresh.parserVersion},
          where: 'key = ? AND status = ?', whereArgs: [item.key, SmsStatus.pending.name]);
    }
    return n;
  }

  // --- کارِ کاربر ---

  // --- دسته‌ها و بودجه ---

  Future<List<Category>> categories() async {
    final rows = await db.query('categories', orderBy: 'is_system DESC, name');
    return rows.map(Category.fromMap).toList();
  }

  /// شناسه‌ی تراکنش ← دسته‌هایش.
  Future<Map<String, List<EntryCategory>>> allocations() async {
    final rows = await db.rawQuery('''
      SELECT lec.entry_id AS e, lec.category_id AS c, cat.name AS n, lec.amount_rial AS a
      FROM ledger_entry_categories lec JOIN categories cat ON cat.id = lec.category_id
      ORDER BY cat.name
    ''');
    final out = <String, List<EntryCategory>>{};
    for (final r in rows) {
      out.putIfAbsent(r['e']! as String, () => []).add(EntryCategory(
          categoryId: r['c']! as String, name: r['n']! as String, amountRial: r['a']! as int));
    }
    return out;
  }

  /// دسته‌های یک تراکنش (کارِ کاربر)؛ مبلغ به تساوی تقسیم می‌شود.
  Future<void> setEntryCategories(String entryId, List<String> categoryIds) async {
    final e = await _entry(entryId);
    if (e == null) return;
    await _writeCategories(db, e, categoryIds);
    await db.update('ledger_entries', {'updated_at': _now().toIso8601String(), 'sync_status': 'pending'},
        where: 'id = ?', whereArgs: [entryId]);
  }

  Future<void> _writeCategories(DatabaseExecutor ex, Entry e, List<String> categoryIds) async {
    await ex.delete('ledger_entry_categories', where: 'entry_id = ?', whereArgs: [e.id]);
    final ids = categoryIds.toSet().toList();
    final parts = splitEqually(e.amountRial, ids.length);
    for (var i = 0; i < ids.length; i++) {
      await ex.insert('ledger_entry_categories',
          {'entry_id': e.id, 'category_id': ids[i], 'amount_rial': parts[i]});
    }
  }

  Future<List<String>> _categoryIdsOf(String entryId) async => [
        for (final r in await db.query('ledger_entry_categories',
            columns: ['category_id'], where: 'entry_id = ?', whereArgs: [entryId]))
          r['category_id']! as String,
      ];

  /// دسته‌هایی که نسخه‌ی ۱ به همین پیامک داده بود (پیش‌پرِ برگه‌ی ثبت؛ طرح ۹.۳).
  Future<List<String>> v1CategoryIdsFor(SmsItem item) async {
    final body = item.body;
    if (body == null) return const [];
    // همان اثرانگشتِ محتوای نسخه‌ی ۱ (`sms_content_hash` در transactions).
    final hash = sha256
        .convert(utf8.encode('${item.sender.trim()}|${normalizeForParsing(body)}'))
        .toString();
    final rows = await db.rawQuery('''
      SELECT DISTINCT tc.category_id AS c FROM transaction_categories tc
      JOIN transactions t ON t.id = tc.transaction_id
      WHERE t.sms_content_hash = ? AND t.deleted_at IS NULL
    ''', [hash]);
    return [for (final r in rows) r['c']! as String];
  }

  Future<List<Budget>> budgets() async {
    final rows = await db.query('budgets', where: 'is_deleted = 0');
    return rows.map(Budget.fromMap).toList();
  }

  /// سقفِ ماهانه‌ی یک دسته؛ null یا صفر = برداشتنِ سقف. (همان جدولِ نسخه‌ی ۱ که همگام می‌شود.)
  Future<void> setBudget(String categoryName, int? limitRial) async {
    final now = _now().toIso8601String();
    final existing = await db.query('budgets',
        where: 'category_name = ? AND is_deleted = 0', whereArgs: [categoryName], limit: 1);
    final remove = limitRial == null || limitRial <= 0;
    if (existing.isNotEmpty) {
      await db.update(
          'budgets',
          {
            if (remove) 'is_deleted': 1 else 'limit_rial': limitRial,
            'updated_at': now,
            'client_updated_at': now,
            'sync_status': 'pending',
          },
          where: 'id = ?',
          whereArgs: [existing.first['id']]);
    } else if (!remove) {
      await db.insert('budgets', {
        'id': _uuid.v4(),
        'category_name': categoryName,
        'period': 'monthly',
        'limit_rial': limitRial,
        'is_deleted': 0,
        'updated_at': now,
        'client_updated_at': now,
        'sync_status': 'pending',
        'created_at': now,
      });
    }
  }

  /// «ثبت»: یک تراکنش از پیامک (منتظر یا ردشده) می‌سازد. مانده‌ی بانک از پیشنهاد.
  Future<Entry> acceptSms(
    String key, {
    required String accountId,
    required EntryKind kind,
    required int amountRial,
    DateTime? occurredAt,
    int? bankBalanceAfter,
    String? note,
    bool isTransfer = false,
    List<String> categoryIds = const [],
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
      isTransfer: isTransfer,
      createdByDevice: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await db.transaction((txn) async {
      await txn.insert('ledger_entries', entry.toMap());
      await _writeCategories(txn, entry, categoryIds);
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

  /// «ثبت» با همان پیشنهاد (دکمه‌ی نوتیفیکیشن، کشیدن، تأییدِ گروهی). پیشنهادِ ناقص = خطا.
  Future<Entry> acceptSuggested(String key) async {
    final g = (await smsItem(key))?.suggestion;
    if (g == null || !g.isComplete) throw StateError('SMS item $key has no complete suggestion');
    return acceptSms(key, accountId: g.accountId!, kind: g.kind!, amountRial: g.amountRial!);
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
    bool isTransfer = false,
    List<String> categoryIds = const [],
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
      isTransfer: isTransfer,
      createdByDevice: deviceId,
      createdAt: now,
      updatedAt: now,
    );
    await db.transaction((txn) async {
      await txn.insert('ledger_entries', entry.toMap());
      await _writeCategories(txn, entry, categoryIds);
    });
    return entry;
  }

  /// ویرایشِ کاربر. [categoryIds] null = همان دسته‌های قبلی، با تقسیمِ دوباره روی مبلغِ تازه.
  Future<void> updateEntry(Entry e, {List<String>? categoryIds}) async {
    if (e.amountRial <= 0) throw ArgumentError.value(e.amountRial, 'amountRial');
    final ids = categoryIds ?? await _categoryIdsOf(e.id);
    await db.transaction((txn) async {
      await txn.update(
          'ledger_entries', {...e.copyWith(updatedAt: _now()).toMap(), 'sync_status': 'pending'},
          where: 'id = ?', whereArgs: [e.id]);
      await _writeCategories(txn, e, ids);
    });
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
