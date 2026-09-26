/// چیزهای غیرِدفتریِ گوشی (جای مخزنِ تراکنش‌های نسخه‌ی ۱؛ طرح ۱۲.۸): تنظیمات، فرستنده‌های پیامکِ
/// بانک، و همگام‌سازیِ کیف‌ها (حساب‌ها) و بودجه‌ها. دفترِ نسخه‌ی ۲ در `core/ledger/` است.
///
/// جدول‌های نسخه‌ی ۱ (`transactions`، `outbox`، …) یک نسخه فقط‌خواندنی روی گوشی می‌مانند (پیش‌پرِ دسته‌ها
/// در برگه‌ی ثبت)؛ دیگر نوشته یا به سرور فرستاده نمی‌شوند.
library;

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../features/senders/data/allowed_sender.dart';

class SettingKeys {
  SettingKeys._();
  static const meUserId = 'me_user_id';
  static const meName = 'me_name';

  /// JSON: [{"id": "...", "name": "..."}]
  static const familyMembers = 'family_members';

  /// نقشِ من در خانواده: 'owner' (مدیر) یا 'member' (عضو عادی).
  static const myRole = 'my_role';

  /// شناسه‌ی ثابتِ این گوشی.
  static const deviceId = 'device_id';

  /// JSON: فرستنده‌هایی که کاربر «بانک نیست» زده تا دیگر پیشنهاد نشوند.
  static const dismissedSenders = 'dismissed_senders';

  /// JSON وضعیتِ آخرین همگام‌سازیِ کیف‌ها و بودجه.
  static const lastSync = 'last_sync';

  /// cursorِ دریافتِ کیف‌ها و بودجه‌ها از سرور.
  static const walletCursor = 'wallet_cursor';
  static const budgetCursor = 'budget_cursor';

  /// cursorِ دریافتِ تراکنش‌های نسخه‌ی ۱ (دیگر خوانده نمی‌شود؛ با عوض شدنِ کاربر پاک می‌شود).
  static const pullCursor = 'pull_cursor';
}

class AppStore {
  final Database db;
  final Uuid _uuid;
  final DateTime Function() _clock;

  AppStore(this.db, {Uuid uuid = const Uuid(), DateTime Function()? clock})
      : _uuid = uuid,
        _clock = clock ?? DateTime.now;

  String _nowIso() => _clock().toUtc().toIso8601String();

  // --- تنظیمات ---------------------------------------------------------------

  Future<String?> getSetting(String key) async {
    final rows =
        await db.query('settings', columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await db.delete('settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- فرستنده‌های پیامکِ بانک --------------------------------------------------

  Future<List<AllowedSender>> allowedSenders() async {
    final rows = await db.query('allowed_senders', orderBy: 'created_at');
    return rows.map(AllowedSender.fromMap).toList();
  }

  /// همان فرستنده با شکلِ دیگر (مثلاً +98… و 0…) دوباره اضافه نمی‌شود.
  Future<AllowedSender> addAllowedSender(String address,
      {String? bankId, String? ownerName, String? ownerUserId}) async {
    final existing = findAllowedSender(await allowedSenders(), address);
    if (existing != null) return existing;
    final sender = AllowedSender(
      id: _uuid.v4(),
      address: address.trim(),
      bankId: bankId,
      ownerName: ownerName,
      ownerUserId: ownerUserId,
    );
    await db.insert('allowed_senders', {...sender.toMap(), 'created_at': _nowIso()});
    return sender;
  }

  Future<void> deleteAllowedSender(String id) =>
      db.delete('allowed_senders', where: 'id = ?', whereArgs: [id]);

  // --- همگام‌سازیِ کیف‌ها و بودجه‌ها ----------------------------------------------

  Future<List<Map<String, Object?>>> pendingWallets() =>
      db.query('wallets', where: "sync_status = 'pending'");

  /// کیفِ سرور؛ ویرایشِ محلیِ ارسال‌نشده با نسخه‌ی سرور خراب نمی‌شود.
  Future<void> applyRemoteWallet(Map<String, dynamic> j) async {
    final id = j['id'].toString();
    final local = await db.query('wallets',
        columns: ['sync_status'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (local.isNotEmpty && local.first['sync_status'] == 'pending') return;
    final map = <String, Object?>{
      'id': id,
      'owner_user_id': _str(j['owner_user_id']),
      'owner_name': (j['owner_name'] ?? '').toString(),
      'label': (j['label'] ?? '').toString(),
      'bank_id': _str(j['bank_id']),
      'card_last4': _str(j['card_last4']),
      'account_ref': _str(j['account_ref']),
      'is_deleted': j['is_deleted'] == true ? 1 : 0,
      'updated_at': _str(j['updated_at']),
      'client_updated_at': _str(j['client_updated_at']),
      'sync_status': 'synced',
    };
    // سرورِ قدیمی این فیلد را ندارد؛ نبودنش «کنارگذاشته»ی محلی را پاک نمی‌کند.
    if (j.containsKey('archived')) map['archived'] = j['archived'] == true ? 1 : 0;
    if (local.isEmpty) {
      map['created_at'] = _nowIso();
      await db.insert('wallets', map);
    } else {
      await db.update('wallets', map, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<List<Map<String, Object?>>> pendingBudgets() =>
      db.query('budgets', where: "sync_status = 'pending'");

  Future<void> applyRemoteBudget(Map<String, dynamic> j) async {
    final id = j['id'].toString();
    final local = await db.query('budgets',
        columns: ['sync_status'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (local.isNotEmpty && local.first['sync_status'] == 'pending') return;
    final map = <String, Object?>{
      'id': id,
      'category_name': (j['category_name'] ?? '').toString(),
      'period': (j['period'] ?? 'monthly').toString(),
      'limit_rial': (j['limit_rial'] as num?)?.toInt() ?? 0,
      'is_deleted': j['is_deleted'] == true ? 1 : 0,
      'updated_at': _str(j['updated_at']),
      'client_updated_at': _str(j['client_updated_at']),
      'sync_status': 'synced',
    };
    if (local.isEmpty) {
      map['created_at'] = _nowIso();
      await db.insert('budgets', map);
    } else {
      await db.update('budgets', map, where: 'id = ?', whereArgs: [id]);
    }
  }

  /// سرور کیف/بودجه‌ای را نپذیرفت یا پذیرفت.
  Future<void> setRowStatus(String table, String id, String status) =>
      db.update(table, {'sync_status': status}, where: 'id = ?', whereArgs: [id]);

  /// شناسه‌ی تازه برای کیف/بودجه‌ای که شناسه‌اش روی سرور مالِ خانواده‌ی دیگری است. تراکنش‌ها و
  /// نقطه‌های دفتر هم به شناسه‌ی تازه‌ی کیف می‌روند.
  Future<void> rekeyRow(String table, String oldId) async {
    final newId = _uuid.v4();
    final now = _nowIso();
    await db.transaction((txn) async {
      await txn.update(table, {'id': newId, 'sync_status': 'pending'},
          where: 'id = ?', whereArgs: [oldId]);
      if (table == 'wallets') {
        for (final t in const ['ledger_entries', 'ledger_checkpoints']) {
          await txn.update(t, {'account_id': newId, 'updated_at': now, 'sync_status': 'pending'},
              where: 'account_id = ?', whereArgs: [oldId]);
        }
        await txn.update('sms_items', {'sugg_account_id': newId},
            where: 'sugg_account_id = ?', whereArgs: [oldId]);
      }
    });
  }

  // --- عوض شدنِ کاربر روی همین گوشی -------------------------------------------------

  /// ورود با کاربرِ دیگر (مثلاً از «کاربر تست» به حسابِ واقعی): کیف‌های «من» مالِ کاربرِ تازه؛ کیفِ
  /// عضوی که در خانواده‌ی تازه نیست بی‌صاحب؛ cursorها از نو تا همه‌ی کیف‌ها و بودجه‌های خانواده‌ی
  /// تازه دریافت شوند. دفترِ کاربرِ قبلی را `LedgerRepository.resetForAccountSwitch` پاک می‌کند.
  Future<void> switchAccount({
    required String previousUserId,
    required String userId,
    required String userName,
    Set<String>? memberIds,
  }) async {
    await db.transaction((txn) async {
      await txn.update('wallets', {'owner_user_id': userId, 'owner_name': userName},
          where: 'owner_user_id = ?', whereArgs: [previousUserId]);
      if (memberIds != null) {
        final keep = {...memberIds, userId}.toList();
        await txn.update(
          'wallets',
          {'owner_user_id': null},
          where: 'owner_user_id IS NOT NULL AND owner_user_id NOT IN '
              '(${List.filled(keep.length, '?').join(',')})',
          whereArgs: keep,
        );
      }
      await txn.delete('settings', where: 'key IN (?, ?, ?, ?)', whereArgs: [
        SettingKeys.pullCursor,
        SettingKeys.walletCursor,
        SettingKeys.budgetCursor,
        SettingKeys.lastSync,
      ]);
    });
  }

  static String? _str(Object? v) => (v == null || (v is String && v.isEmpty)) ? null : v.toString();
}
