/// مخزن تراکنش‌ها روی پایگاه‌داده‌ی محلی.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sms/digit_utils.dart';
import '../../../core/sms/jalali.dart';
import '../../../core/sms/models.dart';
import '../../../core/sms/sms_fingerprint.dart';
import '../../budgets/data/budget.dart';
import '../../categories/data/category.dart';
import '../../senders/data/allowed_sender.dart';
import '../../wallets/data/wallet.dart';
import 'transaction_record.dart';

enum TxInsertStatus { created, duplicate }

class TxInsertOutcome {
  final TxInsertStatus status;
  final String id;
  const TxInsertOutcome(this.status, this.id);

  bool get isCreated => status == TxInsertStatus.created;
  bool get isDuplicate => status == TxInsertStatus.duplicate;
}

/// جمع مالی یک بازه. transfer، نامشخص، بدون مبلغ و «منتظر بازبینی» شمرده نمی‌شوند.
class FinanceSummary {
  final int incomeRial;
  final int expenseRial;
  const FinanceSummary({required this.incomeRial, required this.expenseRial});

  int get balanceRial => incomeRial - expenseRial;

  /// جمعِ یک فهرستِ آماده (همان قاعده‌ی کوئری‌های مخزن).
  factory FinanceSummary.of(Iterable<TransactionRecord> items) {
    var income = 0;
    var expense = 0;
    for (final t in items) {
      if (!countsInTotals(t)) continue;
      if (t.kind == 'income') income += t.amountRial!;
      if (t.kind == 'expense') expense += t.amountRial!;
    }
    return FinanceSummary(incomeRial: income, expenseRial: expense);
  }
}

/// آیا تراکنش در جمع درآمد/هزینه می‌آید؟
bool countsInTotals(TransactionRecord t) =>
    !t.isDeleted &&
    !t.needsReview &&
    t.amountRial != null &&
    (t.kind == 'income' || t.kind == 'expense');

/// کلیدِ کارت برای گروه‌بندیِ موجودی (بانک + شماره‌ی کارت/حساب، وگرنه صاحب).
String _balanceCardKey(TransactionRecord t) {
  final bank = t.bankId ?? '';
  if (t.cardLast4?.isNotEmpty ?? false) return '$bank|c:${t.cardLast4}';
  if (t.accountRef?.isNotEmpty ?? false) return '$bank|a:${t.accountRef}';
  return '$bank|u:${t.ownerUserId ?? t.walletLabel ?? 'unknown'}';
}

/// موجودیِ واقعی: برای هر کارت، «مانده»ی آخرین پیامکِ بانک (که مطلق است و شاملِ
/// موجودیِ ابتدای دوره می‌شود) را می‌گیرد و تراکنش‌های بعد از آن مانده را هم اعمال
/// می‌کند؛ سپس جمعِ همه‌ی کارت‌ها. [asOf] = فقط تا این زمان (پایان دوره).
///
/// چرا؟ چون «خالص = درآمد − هزینه» موجودیِ ابتدای دوره را صفر می‌گیرد و غلط است؛
/// ولی مانده‌ی بانک عددِ واقعیِ حساب است.
int realBalanceRial(Iterable<TransactionRecord> all, {DateTime? asOf}) {
  final byCard = <String, List<TransactionRecord>>{};
  for (final t in all) {
    if (t.isDeleted) continue;
    if (asOf != null && t.effectiveTime.isAfter(asOf)) continue;
    byCard.putIfAbsent(_balanceCardKey(t), () => []).add(t);
  }
  var total = 0;
  for (final list in byCard.values) {
    list.sort((a, b) => a.effectiveTime.compareTo(b.effectiveTime));
    // آخرین تراکنشی که مانده دارد.
    var anchor = -1;
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].balanceAfterRial != null) {
        anchor = i;
        break;
      }
    }
    if (anchor == -1) {
      // هیچ مانده‌ای نداریم؛ بهترین تخمین: جمعِ علامت‌دار (بدون موجودیِ ابتدایی).
      for (final t in list) {
        total += t.signedAmount;
      }
    } else {
      total += list[anchor].balanceAfterRial!;
      // تراکنش‌های بعد از آن مانده را هم اعمال کن (اگر پیامکِ جدیدتری مانده نداشت).
      for (var i = anchor + 1; i < list.length; i++) {
        total += list[i].signedAmount;
      }
    }
  }
  return total;
}

/// کلیدهای جدول تنظیمات.
class SettingKeys {
  SettingKeys._();
  static const meUserId = 'me_user_id';
  static const meName = 'me_name';

  /// JSON: [{"id": "...", "name": "..."}]
  static const familyMembers = 'family_members';
  static const categorizeFrom = 'categorize_from';
  static const pullCursor = 'pull_cursor';

  /// JSON وضعیت آخرین همگام‌سازی.
  static const lastSync = 'last_sync';

  /// JSON: کلید گپ‌های تطبیق مانده که کاربر نادیده گرفته.
  static const dismissedGaps = 'dismissed_gaps';

  /// JSON: کلید گروه‌های تکراری که کاربر «تکراری نیست» زده.
  static const dismissedDuplicates = 'dismissed_dups';

  /// JSON: فرستنده‌هایی که کاربر «بانک نیست» زده تا دیگر پیشنهاد نشوند.
  static const dismissedSenders = 'dismissed_senders';

  /// JSON: جفت‌های انتقالی که کاربر «انتقال نیست» زده.
  static const dismissedTransfers = 'dismissed_transfers';

  /// شناسه‌ی ثابت این گوشی (برای sync).
  static const deviceId = 'device_id';

  /// نمایش متن پیامک روی ردیف تراکنش‌ها ('0' = خاموش).
  static const showSmsText = 'show_sms_text';

  /// نقشِ من در خانواده: 'owner' (مدیر) یا 'member' (عضو عادی).
  static const myRole = 'my_role';

  /// cursor دریافتِ کیف‌ها از سرور.
  static const walletCursor = 'wallet_cursor';

  /// cursor دریافتِ بودجه‌ها از سرور.
  static const budgetCursor = 'budget_cursor';
}

/// پنجره‌ی ضدتکرارِ محتوایی: فقط برای «مسابقهٔ» دریافتِ زنده و خواندنِ صندوق از
/// همان پیامک (چند ثانیه/دقیقه فاصله). کوتاه است چون بعضی بانک‌ها مانده/زمان در
/// پیامک نمی‌نویسند و دو خریدِ واقعیِ هم‌مبلغ متنِ یکسان دارند؛ پنجرهٔ بلند آن‌ها را
/// اشتباهی یکی می‌کرد. «حقوقِ دوباره‌شمرده» (فاصلهٔ زیاد) را صفحهٔ «احتمال تکراری»
/// با تأیید کاربر می‌گیرد، نه ادغامِ خودکار.
const Duration kContentDedupWindow = Duration(minutes: 10);

/// اولین لحظه‌ی ماه شمسیِ بعد از [now] (به وقت ایران)؛ پیش‌فرض شروع دسته‌بندی.
DateTime startOfNextJalaliMonth(DateTime now) {
  final d = JalaliDate.fromDateTime(now);
  final next = d.month == 12
      ? JalaliDate(d.year + 1, 1, 1)
      : JalaliDate(d.year, d.month + 1, 1);
  return next.toUtcStart();
}

/// اثرانگشت محتوای پیامک بدون زمان.
String smsContentHash({required String sender, required String body}) {
  final input = '${sender.trim()}|${normalizeForParsing(body)}';
  return sha256.convert(utf8.encode(input)).toString();
}

/// انتزاع مخزن تراکنش برای تزریق: اپ از SQLite استفاده می‌کند،
/// تست‌های ویجت از یک پیاده‌سازی in-memory (بدون I/O بومی).
abstract class TransactionStore {
  Future<TxInsertOutcome> saveParsed(
    ParsedTransaction parsed, {
    required String sender,
    String? deviceId,
    DateTime? receivedAt,
  });

  /// ثبت دستی (مثلاً تراکنشِ جاافتاده‌ای که پیامکش نرسیده).
  Future<String> addManual({
    required String kind,
    required int amountRial,
    required DateTime at,
    String? description,
    String? bankId,
    String? cardLast4,
    String? accountRef,
  });
  Future<List<TransactionRecord>> getAll({
    int? limit,
    String? kind,
    bool? needsReview,
    String? search,
    DateTime? from,
    DateTime? to,
  });
  Future<TransactionRecord?> getById(String id);
  Future<FinanceSummary> summary({DateTime? from, DateTime? to});
  Future<int> needsReviewCount();
  Future<void> updateTransaction(
    String id, {
    String? kind,
    int? amountRial,
    String? counterparty,
    String? description,
    bool? needsReview,
  });

  /// حذف نرم: تراکنش نامعتبر (ناموفق/پیامک رمز) پنهان می‌شود ولی پیامکش دوباره وارد نمی‌شود.
  Future<void> deleteTransaction(String id);

  /// انتسابِ دستیِ تراکنش به یک کیفِ مشخص (وقتی شخص چند حساب در یک بانک دارد و
  /// پیامک شماره نداشته). این انتساب پایدار است و با حدسِ خودکار بازنویسی نمی‌شود.
  Future<void> assignWalletToTransaction(String txId, Wallet wallet);

  /// برداشتنِ انتسابِ دستی و برگشت به حدسِ خودکار.
  Future<void> clearWalletPin(String txId);

  // --- دسته‌بندی ---
  Future<List<Category>> categories();
  Future<void> categorize(
    String transactionId,
    List<String> categoryIds, {
    String? description,
  });
  Future<List<CategoryTotal>> categoryTotals({DateTime? from, DateTime? to});

  /// تراکنش‌های خودم که از «شروع دسته‌بندی» به بعد‌اند و هنوز دسته ندارند.
  Future<List<TransactionRecord>> uncategorized({int? limit});
  Future<DateTime> categorizeFrom();

  // --- کیف‌ها (کارت/حساب اعضا) ---
  Future<List<Wallet>> wallets();
  Future<void> addWallet(Wallet wallet);
  Future<void> updateWallet(Wallet wallet);
  Future<void> deleteWallet(String id);

  // هم‌گام‌سازی کیف‌ها با سرور.
  Future<List<Map<String, Object?>>> pendingWallets();
  Future<void> markWalletSynced(String id);
  Future<void> applyRemoteWallet(Map<String, dynamic> j);

  // --- بودجه‌ها (سقفِ ماهانه‌ی هر دسته) ---
  Future<List<Budget>> budgets();
  Future<void> addBudget(Budget budget);
  Future<void> updateBudget(Budget budget);
  Future<void> deleteBudget(String id);

  /// بودجه‌ها همراهِ مقدارِ خرج‌شده‌ی همان دسته در بازه.
  Future<List<BudgetUsage>> budgetUsage({DateTime? from, DateTime? to});

  // هم‌گام‌سازی بودجه‌ها با سرور.
  Future<List<Map<String, Object?>>> pendingBudgets();
  Future<void> markBudgetSynced(String id);
  Future<void> applyRemoteBudget(Map<String, dynamic> j);

  // --- فرستنده‌های مجاز پیامک (فقط پیامک این‌ها خودکار ثبت می‌شود) ---
  Future<List<AllowedSender>> allowedSenders();

  /// اگر همین فرستنده (با هر شکلِ نوشتن) از قبل باشد، همان برمی‌گردد.
  Future<AllowedSender> addAllowedSender(String address,
      {String? bankId, String? ownerName, String? ownerUserId});
  Future<void> deleteAllowedSender(String id);

  /// انتساب دوباره‌ی تراکنش‌های همین گوشی به کیف‌ها/کاربر جاری.
  Future<void> reattributeLocal();

  /// ورود با حساب دیگری روی همین گوشی: تراکنش‌های خانواده‌ی قبلی (از گوشی‌های
  /// دیگر) و cursor دریافت پاک می‌شوند؛ تراکنش‌های پیامکِ همین گوشی با شناسه‌ی تازه
  /// برای خانواده‌ی جدید صف می‌شوند (سرور شناسه‌ی قبلی را در خانواده‌ی قبلی دارد)؛
  /// کیف‌های «من» به کاربر جدید می‌رسند و کیفِ عضوی که در خانواده‌ی جدید نیست بی‌حساب
  /// می‌شود. [memberIds] null یعنی اعضا گرفته نشد (کیف‌های دیگر دست نمی‌خورند).
  Future<void> switchAccount({
    required String previousUserId,
    required String userId,
    required String userName,
    Set<String>? memberIds,
  });

  /// حذف تراکنش‌های خانواده که مالِ من نیستند و از سرور آمده‌اند (برای عضوِ عادی که
  /// دیگر نباید جزئیاتِ بقیه را داشته باشد).
  Future<void> purgeRemoteNotOwnedBy(String meUserId);

  /// تعداد تراکنش‌های منتظر ارسال به سرور.
  Future<int> pendingSyncCount();

  // --- تنظیمات ---
  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String? value);
}

class _Attribution {
  final String? ownerUserId;
  final String? ownerName;
  final String? walletLabel;
  const _Attribution(this.ownerUserId, this.ownerName, this.walletLabel);
}

_Attribution _attributionFrom(
  List<Wallet> wallets,
  List<AllowedSender> allowed,
  String? meUserId, {
  String? sender,
  String? cardLast4,
  String? accountRef,
  String? bankId,
}) {
  // اولویت با صاحبِ صریحِ فرستنده (برای پیامک‌های بی‌شماره مثل دیجی‌پی).
  if (sender != null && sender.isNotEmpty) {
    final s = findAllowedSender(allowed, sender);
    if (s != null && s.hasOwner) {
      final w = walletFor(wallets,
          cardLast4: cardLast4, accountRef: accountRef, bankId: bankId);
      return _Attribution(s.ownerUserId ?? meUserId, s.ownerName, w?.label);
    }
  }
  final w = walletFor(wallets,
      cardLast4: cardLast4, accountRef: accountRef, bankId: bankId);
  if (w == null) return _Attribution(meUserId, null, null);
  // کیفِ بدون حساب کاربری (مثلاً مامانی که اپ ندارد) → صاحبِ ویرایش، همین گوشی است.
  return _Attribution(w.ownerUserId ?? meUserId, w.ownerName, w.label);
}

class TransactionRepository implements TransactionStore {
  final Database _db;
  final Uuid _uuid;
  final DateTime Function() _clock;

  TransactionRepository(
    this._db, {
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  })  : _uuid = uuid,
        _clock = clock ?? DateTime.now;

  static const _dateExpr =
      'COALESCE(t.transaction_date, t.sms_received_at, t.client_created_at, t.created_at)';

  static const _allocExpr = '''
    (SELECT GROUP_CONCAT(c.name || char(31) || tc.amount_rial, char(30))
       FROM transaction_categories tc JOIN categories c ON c.id = tc.category_id
      WHERE tc.transaction_id = t.id) AS alloc''';

  String _nowIso() => _clock().toUtc().toIso8601String();

  /// ذخیره‌ی خروجی پارسر. اگر همین پیامک قبلاً ذخیره شده باشد (اثرانگشت یکسان،
  /// یا همان محتوا با فاصله‌ی زمانی کم) رکورد جدید ساخته نمی‌شود — حتی اگر قبلاً
  /// «حذف» شده باشد، تا تراکنش نامعتبر با خواندن دوباره‌ی صندوق برنگردد.
  @override
  Future<TxInsertOutcome> saveParsed(
    ParsedTransaction parsed, {
    required String sender,
    String? deviceId,
    DateTime? receivedAt,
  }) async {
    final now = _clock().toUtc();
    final body = parsed.rawBody;
    final hasBody = body.trim().isNotEmpty;
    final hash = hasBody
        ? smsFingerprint(sender: sender, body: body, receivedAt: receivedAt)
        : null;
    final contentHash = hasBody ? smsContentHash(sender: sender, body: body) : null;

    if (hash != null) {
      final existing = await _db.query(
        'transactions',
        columns: ['id', 'sms_body'],
        where: 'source_message_hash = ?',
        whereArgs: [hash],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as String;
        if (existing.first['sms_body'] == null) {
          // ردیفِ نسخه‌ی قبل: متن و زمان پیامک را تکمیل کن (ترتیب زمانی درست می‌شود).
          await _db.update(
            'transactions',
            {
              'sms_sender': sender,
              'sms_body': body,
              'sms_received_at': receivedAt?.toUtc().toIso8601String(),
              'sms_content_hash': contentHash,
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        return TxInsertOutcome(TxInsertStatus.duplicate, id);
      }
    }
    if (contentHash != null && receivedAt != null) {
      final dup = await _findContentDuplicate(contentHash, receivedAt);
      if (dup != null) return TxInsertOutcome(TxInsertStatus.duplicate, dup);
    }

    final a = await _attributionFor(
      sender: sender,
      cardLast4: parsed.cardLast4,
      accountRef: parsed.accountRef,
      bankId: parsed.bankId,
    );
    final id = _uuid.v4();
    final record = TransactionRecord.fromParsed(
      parsed,
      id: id,
      now: now,
      sourceMessageHash: hash,
      deviceId: deviceId,
      smsReceivedAt: receivedAt,
      smsContentHash: contentHash,
      ownerUserId: a.ownerUserId,
      ownerName: a.ownerName,
      walletLabel: a.walletLabel,
    );
    await _db.insert('transactions', record.toMap());
    await _enqueueOutbox(record);
    return TxInsertOutcome(TxInsertStatus.created, id);
  }

  Future<String?> _findContentDuplicate(String contentHash, DateTime receivedAt) async {
    final rows = await _db.query(
      'transactions',
      columns: ['id', 'sms_received_at'],
      where: 'sms_content_hash = ?',
      whereArgs: [contentHash],
    );
    for (final r in rows) {
      final at = r['sms_received_at'] as String?;
      if (at == null) continue;
      final gap = DateTime.parse(at).difference(receivedAt.toUtc()).abs();
      if (gap <= kContentDedupWindow) return r['id'] as String;
    }
    return null;
  }

  @override
  Future<String> addManual({
    required String kind,
    required int amountRial,
    required DateTime at,
    String? description,
    String? bankId,
    String? cardLast4,
    String? accountRef,
  }) async {
    final now = _clock().toUtc();
    final a = await _attributionFor(
        cardLast4: cardLast4, accountRef: accountRef, bankId: bankId);
    final record = TransactionRecord(
      id: _uuid.v4(),
      kind: kind,
      amountRial: amountRial,
      transactionDate: at.toUtc(),
      clientCreatedAt: now,
      createdAt: now,
      updatedAt: now,
      source: 'manual',
      description: description,
      bankId: bankId,
      cardLast4: cardLast4,
      accountRef: accountRef,
      ownerUserId: a.ownerUserId,
      ownerName: a.ownerName,
      walletLabel: a.walletLabel,
    );
    await _db.insert('transactions', record.toMap());
    await _enqueueOutbox(record);
    return record.id;
  }

  /// درج مستقیم یک رکورد (برای تست).
  Future<void> insert(TransactionRecord record) async {
    await _db.insert('transactions', record.toMap());
    await _enqueueOutbox(record);
  }

  /// صف‌کردن تراکنش برای همگام‌سازی. payload هنگام ارسال از روی ردیفِ فعلی ساخته
  /// می‌شود تا همیشه آخرین نسخه برود. نوع نامشخص تا بازبینی sync نمی‌شود.
  Future<void> _enqueueOutbox(TransactionRecord record) async {
    if (record.kind == 'unknown') return;
    await _db.insert(
      'outbox',
      {
        'transaction_id': record.id,
        'payload': '{}',
        'status': 'pending',
        'retry_count': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<_Attribution> _attributionFor({
    String? sender,
    String? cardLast4,
    String? accountRef,
    String? bankId,
  }) async {
    return _attributionFrom(
      await wallets(),
      await allowedSenders(),
      await getSetting(SettingKeys.meUserId),
      sender: sender,
      cardLast4: cardLast4,
      accountRef: accountRef,
      bankId: bankId,
    );
  }

  Future<List<TransactionRecord>> _select(
    List<String> where,
    List<Object?> args, {
    String orderBy = '$_dateExpr DESC',
    int? limit,
  }) async {
    final rows = await _db.rawQuery(
      'SELECT t.*, $_allocExpr FROM transactions t '
      '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
      'ORDER BY $orderBy ${limit != null ? 'LIMIT $limit' : ''}',
      args,
    );
    return rows.map(TransactionRecord.fromMap).toList();
  }

  @override
  Future<List<TransactionRecord>> getAll({
    int? limit,
    String? kind,
    bool? needsReview,
    String? search,
    DateTime? from,
    DateTime? to,
  }) {
    final where = <String>['t.deleted_at IS NULL'];
    final args = <Object?>[];
    if (kind != null) {
      where.add('t.kind = ?');
      args.add(kind);
    }
    if (needsReview != null) {
      where.add('t.needs_review = ?');
      args.add(needsReview ? 1 : 0);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(t.counterparty LIKE ? OR t.description LIKE ? OR t.bank_id LIKE ? '
          'OR t.owner_name LIKE ? OR t.wallet_label LIKE ?)');
      final q = '%${search.trim()}%';
      args.addAll([q, q, q, q, q]);
    }
    if (from != null) {
      where.add('$_dateExpr >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.add('$_dateExpr < ?');
      args.add(to.toUtc().toIso8601String());
    }
    return _select(where, args, limit: limit);
  }

  @override
  Future<TransactionRecord?> getById(String id) async {
    final list = await _select(['t.id = ?'], [id], limit: 1);
    return list.isEmpty ? null : list.first;
  }

  Future<int> count() async {
    return Sqflite.firstIntValue(
          await _db.rawQuery(
              'SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL'),
        ) ??
        0;
  }

  @override
  Future<int> needsReviewCount() async {
    final me = await getSetting(SettingKeys.meUserId);
    return Sqflite.firstIntValue(
          await _db.rawQuery(
            'SELECT COUNT(*) FROM transactions WHERE needs_review = 1 '
            'AND deleted_at IS NULL '
            '${me == null ? '' : 'AND (owner_user_id IS NULL OR owner_user_id = ?)'}',
            [if (me != null) me],
          ),
        ) ??
        0;
  }

  @override
  Future<void> updateTransaction(
    String id, {
    String? kind,
    int? amountRial,
    String? counterparty,
    String? description,
    bool? needsReview,
  }) async {
    final data = <String, Object?>{
      'updated_at': _nowIso(),
      'sync_status': 'pending',
    };
    if (kind != null) data['kind'] = kind;
    if (amountRial != null) data['amount_rial'] = amountRial;
    if (counterparty != null) data['counterparty'] = counterparty;
    if (description != null) data['description'] = description;
    if (needsReview != null) {
      data['needs_review'] = needsReview ? 1 : 0;
      if (!needsReview) data['review_reason'] = null;
    }
    await _db.update('transactions', data, where: 'id = ?', whereArgs: [id]);

    final record = await getById(id);
    if (record != null) await _enqueueOutbox(record);
  }

  @override
  Future<void> deleteTransaction(String id) async {
    final now = _nowIso();
    await _db.update(
      'transactions',
      {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
      where: 'id = ?',
      whereArgs: [id],
    );
    final record = await getById(id);
    if (record != null) await _enqueueOutbox(record);
  }

  @override
  Future<List<Wallet>> wallets() async {
    final rows = await _db.query('wallets',
        where: 'is_deleted = 0', orderBy: 'owner_name, label');
    return rows.map(Wallet.fromMap).toList();
  }

  @override
  Future<void> addWallet(Wallet wallet) async {
    final now = _nowIso();
    final map = wallet.toMap();
    map['id'] = _uuid.v4();
    map['created_at'] = now;
    map['updated_at'] = now;
    map['client_updated_at'] = now;
    map['is_deleted'] = 0;
    map['sync_status'] = 'pending';
    await _db.insert('wallets', map);
    await reattributeLocal();
  }

  @override
  Future<void> updateWallet(Wallet wallet) async {
    final now = _nowIso();
    final map = wallet.toMap()..remove('id');
    map['updated_at'] = now;
    map['client_updated_at'] = now;
    map['sync_status'] = 'pending';
    await _db.update('wallets', map, where: 'id = ?', whereArgs: [wallet.id]);
    await reattributeLocal();
  }

  @override
  Future<void> deleteWallet(String id) async {
    // حذف نرم تا حذف به گوشی‌های دیگر هم برسد.
    final now = _nowIso();
    await _db.update(
      'wallets',
      {
        'is_deleted': 1,
        'updated_at': now,
        'client_updated_at': now,
        'sync_status': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await reattributeLocal();
  }

  @override
  Future<List<Map<String, Object?>>> pendingWallets() async {
    return _db.query('wallets', where: "sync_status = 'pending'");
  }

  @override
  Future<void> markWalletSynced(String id) async {
    await _db.update('wallets', {'sync_status': 'synced'},
        where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> applyRemoteWallet(Map<String, dynamic> j) async {
    final id = j['id'].toString();
    // ویرایشِ محلیِ ارسال‌نشده را با نسخه‌ی سرور خراب نکن.
    final local = await _db.query('wallets',
        columns: ['sync_status'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (local.isNotEmpty && local.first['sync_status'] == 'pending') return;

    String? s(Object? v) =>
        (v == null || (v is String && v.isEmpty)) ? null : v.toString();
    final map = <String, Object?>{
      'id': id,
      'owner_user_id': s(j['owner_user_id']),
      'owner_name': (j['owner_name'] ?? '').toString(),
      'label': (j['label'] ?? '').toString(),
      'bank_id': s(j['bank_id']),
      'card_last4': s(j['card_last4']),
      'account_ref': s(j['account_ref']),
      'is_deleted': j['is_deleted'] == true ? 1 : 0,
      'updated_at': s(j['updated_at']),
      'client_updated_at': s(j['client_updated_at']),
      'sync_status': 'synced',
    };
    if (local.isEmpty) {
      map['created_at'] = _nowIso();
      await _db.insert('wallets', map);
    } else {
      await _db.update('wallets', map, where: 'id = ?', whereArgs: [id]);
    }
  }

  // --- بودجه‌ها -------------------------------------------------------------

  @override
  Future<List<Budget>> budgets() async {
    final rows = await _db.query('budgets',
        where: 'is_deleted = 0', orderBy: 'category_name');
    return rows.map(Budget.fromMap).toList();
  }

  @override
  Future<void> addBudget(Budget budget) async {
    final now = _nowIso();
    final map = budget.toMap();
    map['id'] = _uuid.v4();
    map['created_at'] = now;
    map['updated_at'] = now;
    map['client_updated_at'] = now;
    map['is_deleted'] = 0;
    map['sync_status'] = 'pending';
    await _db.insert('budgets', map);
  }

  @override
  Future<void> updateBudget(Budget budget) async {
    final now = _nowIso();
    final map = budget.toMap()..remove('id');
    map['updated_at'] = now;
    map['client_updated_at'] = now;
    map['sync_status'] = 'pending';
    await _db.update('budgets', map, where: 'id = ?', whereArgs: [budget.id]);
  }

  @override
  Future<void> deleteBudget(String id) async {
    final now = _nowIso();
    await _db.update(
      'budgets',
      {
        'is_deleted': 1,
        'updated_at': now,
        'client_updated_at': now,
        'sync_status': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<BudgetUsage>> budgetUsage({DateTime? from, DateTime? to}) async {
    final all = await budgets();
    if (all.isEmpty) return const [];
    final totals = await categoryTotals(from: from, to: to);
    final spentByName = <String, int>{};
    for (final t in totals) {
      spentByName[t.name] = (spentByName[t.name] ?? 0) + t.amountRial;
    }
    final list = [
      for (final b in all)
        BudgetUsage(budget: b, spentRial: spentByName[b.categoryName] ?? 0),
    ];
    // پرمصرف‌ترها (نزدیک به سقف) اول.
    list.sort((a, b) => b.ratio.compareTo(a.ratio));
    return list;
  }

  @override
  Future<List<Map<String, Object?>>> pendingBudgets() async {
    return _db.query('budgets', where: "sync_status = 'pending'");
  }

  @override
  Future<void> markBudgetSynced(String id) async {
    await _db.update('budgets', {'sync_status': 'synced'},
        where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> applyRemoteBudget(Map<String, dynamic> j) async {
    final id = j['id'].toString();
    final local = await _db.query('budgets',
        columns: ['sync_status'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (local.isNotEmpty && local.first['sync_status'] == 'pending') return;
    String? s(Object? v) =>
        (v == null || (v is String && v.isEmpty)) ? null : v.toString();
    final map = <String, Object?>{
      'id': id,
      'category_name': (j['category_name'] ?? '').toString(),
      'period': (j['period'] ?? 'monthly').toString(),
      'limit_rial': (j['limit_rial'] as num?)?.toInt() ?? 0,
      'is_deleted': j['is_deleted'] == true ? 1 : 0,
      'updated_at': s(j['updated_at']),
      'client_updated_at': s(j['client_updated_at']),
      'sync_status': 'synced',
    };
    if (local.isEmpty) {
      map['created_at'] = _nowIso();
      await _db.insert('budgets', map);
    } else {
      await _db.update('budgets', map, where: 'id = ?', whereArgs: [id]);
    }
  }

  @override
  Future<List<AllowedSender>> allowedSenders() async {
    final rows = await _db.query('allowed_senders', orderBy: 'created_at');
    return rows.map(AllowedSender.fromMap).toList();
  }

  @override
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
    await _db.insert('allowed_senders', {...sender.toMap(), 'created_at': _nowIso()});
    // بانکِ پیامک‌های قبلیِ همین فرستنده را پر کن، و صاحب را (اگر تعیین شده) اعمال کن.
    if (bankId != null) await _backfillBank(sender);
    await reattributeLocal();
    return sender;
  }

  /// پیامک‌هایی که قبلاً از همین فرستنده ثبت شده و بانکشان معلوم نبود، بانکِ فرستنده
  /// را می‌گیرند تا بشود صاحب کارتشان را تعیین کرد.
  Future<void> _backfillBank(AllowedSender sender) async {
    final rows = await _db.query(
      'transactions',
      columns: ['id', 'sms_sender'],
      where: "origin = 'local' AND bank_id IS NULL AND sms_sender IS NOT NULL",
    );
    final now = _nowIso();
    var changed = false;
    for (final r in rows) {
      if (!sender.matches(r['sms_sender'] as String)) continue;
      await _db.update(
        'transactions',
        {'bank_id': sender.bankId, 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [r['id']],
      );
      final record = await getById(r['id'] as String);
      if (record != null) await _enqueueOutbox(record);
      changed = true;
    }
    if (changed) await reattributeLocal();
  }

  @override
  Future<void> deleteAllowedSender(String id) async {
    await _db.delete('allowed_senders', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> purgeRemoteNotOwnedBy(String meUserId) async {
    final rows = await _db.query(
      'transactions',
      columns: ['id'],
      where: "origin = 'remote' AND (owner_user_id IS NULL OR owner_user_id != ?)",
      whereArgs: [meUserId],
    );
    for (final r in rows) {
      final id = r['id'] as String;
      await _db.delete('transaction_categories',
          where: 'transaction_id = ?', whereArgs: [id]);
      await _db.delete('transactions', where: 'id = ?', whereArgs: [id]);
    }
  }

  @override
  Future<void> switchAccount({
    required String previousUserId,
    required String userId,
    required String userName,
    Set<String>? memberIds,
  }) async {
    final now = _nowIso();
    await _db.transaction((txn) async {
      // ۱) داده‌ی خانواده‌ی قبلی که از گوشی‌های دیگر (سرور) آمده بود.
      const remote = "SELECT id FROM transactions WHERE origin = 'remote'";
      await txn.delete('transaction_categories', where: 'transaction_id IN ($remote)');
      await txn.delete('outbox', where: 'transaction_id IN ($remote)');
      await txn.delete('transactions', where: "origin = 'remote'");

      // ۲) کیف‌های «من» مال کاربر جدید؛ کیفِ عضوی که در خانواده‌ی جدید نیست بی‌حساب.
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

      // ۳) پیامک‌های همین گوشی: شناسه‌ی تازه (سرور شناسه‌ی قبلی را در خانواده‌ی
      // قبلی دارد و «تعارض شناسه» می‌داد) + صف ارسال برای خانواده‌ی جدید.
      final rows = await txn.query('transactions',
          columns: ['id', 'kind'], where: "origin = 'local' AND deleted_at IS NULL");
      for (final r in rows) {
        final oldId = r['id'] as String;
        final newId = _uuid.v4();
        await txn.update(
            'transactions', {'id': newId, 'sync_status': 'pending', 'updated_at': now},
            where: 'id = ?', whereArgs: [oldId]);
        await txn.update('transaction_categories', {'transaction_id': newId},
            where: 'transaction_id = ?', whereArgs: [oldId]);
        await txn.delete('outbox', where: 'transaction_id = ?', whereArgs: [oldId]);
        if (r['kind'] != 'unknown') {
          await txn.insert(
            'outbox',
            {'transaction_id': newId, 'payload': '{}', 'status': 'pending', 'retry_count': 0},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      // ۴) cursor دریافت و وضعیت همگام‌سازیِ خانواده‌ی قبلی.
      await txn.delete('settings',
          where: 'key IN (?, ?)', whereArgs: [SettingKeys.pullCursor, SettingKeys.lastSync]);
    });
  }

  @override
  Future<void> assignWalletToTransaction(String txId, Wallet wallet) async {
    final data = <String, Object?>{
      'pinned_wallet_id': wallet.id,
      'owner_user_id': wallet.ownerUserId,
      'owner_name': wallet.ownerName,
      'wallet_label': wallet.label,
      if (wallet.bankId != null && wallet.bankId!.isNotEmpty) 'bank_id': wallet.bankId,
      if (wallet.cardLast4 != null && wallet.cardLast4!.isNotEmpty)
        'card_last4': wallet.cardLast4,
      if (wallet.accountRef != null && wallet.accountRef!.isNotEmpty)
        'account_ref': wallet.accountRef,
      'updated_at': _nowIso(),
      'sync_status': 'pending',
    };
    await _db.update('transactions', data, where: 'id = ?', whereArgs: [txId]);
    final record = await getById(txId);
    if (record != null && record.kind != 'unknown') await _enqueueOutbox(record);
  }

  @override
  Future<void> clearWalletPin(String txId) async {
    await _db.update('transactions', {'pinned_wallet_id': null},
        where: 'id = ?', whereArgs: [txId]);
    await reattributeLocal();
  }

  @override
  Future<void> reattributeLocal() async {
    final me = await getSetting(SettingKeys.meUserId);
    final ws = await wallets();
    final allowed = await allowedSenders();
    final rows = await _db.query(
      'transactions',
      columns: [
        'id', 'kind', 'sms_sender', 'card_last4', 'account_ref', 'bank_id',
        'owner_user_id', 'owner_name', 'wallet_label', 'pinned_wallet_id',
      ],
      where: "origin = 'local' AND deleted_at IS NULL",
    );
    final now = _nowIso();
    for (final r in rows) {
      // انتسابِ دستی (pinned): از همان کیف استفاده کن، نه حدسِ خودکار.
      final pinnedId = r['pinned_wallet_id'] as String?;
      final _Attribution a;
      if (pinnedId != null && pinnedId.isNotEmpty) {
        Wallet? pw;
        for (final w in ws) {
          if (w.id == pinnedId) {
            pw = w;
            break;
          }
        }
        if (pw == null) {
          // کیفِ انتساب حذف شده؛ pin را بردار و به حالت خودکار برگرد.
          await _db.update('transactions', {'pinned_wallet_id': null},
              where: 'id = ?', whereArgs: [r['id']]);
          a = _attributionFrom(ws, allowed, me,
              sender: r['sms_sender'] as String?,
              cardLast4: r['card_last4'] as String?,
              accountRef: r['account_ref'] as String?,
              bankId: r['bank_id'] as String?);
        } else {
          a = _Attribution(pw.ownerUserId ?? me, pw.ownerName, pw.label);
        }
      } else {
        a = _attributionFrom(
          ws,
          allowed,
          me,
          sender: r['sms_sender'] as String?,
          cardLast4: r['card_last4'] as String?,
          accountRef: r['account_ref'] as String?,
          bankId: r['bank_id'] as String?,
        );
      }
      if (a.ownerUserId == r['owner_user_id'] &&
          a.ownerName == r['owner_name'] &&
          a.walletLabel == r['wallet_label']) {
        continue;
      }
      await _db.update(
        'transactions',
        {
          'owner_user_id': a.ownerUserId,
          'owner_name': a.ownerName,
          'wallet_label': a.walletLabel,
          'updated_at': now,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [r['id']],
      );
      if (r['kind'] != 'unknown') {
        await _db.insert(
          'outbox',
          {
            'transaction_id': r['id'],
            'payload': '{}',
            'status': 'pending',
            'retry_count': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  @override
  Future<List<Category>> categories() async {
    final rows = await _db.query('categories', orderBy: 'is_system DESC, name');
    return rows.map(Category.fromMap).toList();
  }

  Future<String> _categoryIdByName(String name) async {
    final rows = await _db.query('categories',
        columns: ['id'], where: 'name = ?', whereArgs: [name], limit: 1);
    if (rows.isNotEmpty) return rows.first['id'] as String;
    final id = _uuid.v4();
    await _db.insert('categories', {
      'id': id,
      'name': name,
      'is_system': 0,
      'created_at': _nowIso(),
    });
    return id;
  }

  @override
  Future<void> categorize(
    String transactionId,
    List<String> categoryIds, {
    String? description,
  }) async {
    final txRows = await _db.query('transactions',
        columns: ['amount_rial'],
        where: 'id = ?',
        whereArgs: [transactionId],
        limit: 1);
    final amount =
        txRows.isEmpty ? 0 : ((txRows.first['amount_rial'] as int?) ?? 0);

    await _db.delete('transaction_categories',
        where: 'transaction_id = ?', whereArgs: [transactionId]);

    final n = categoryIds.length;
    if (n > 0) {
      // تقسیم مساوی؛ باقی‌مانده‌ی ریالی به دسته‌های اول داده می‌شود تا جمع دقیق بماند.
      final base = amount ~/ n;
      final remainder = amount - base * n;
      final batch = _db.batch();
      for (var i = 0; i < n; i++) {
        batch.insert('transaction_categories', {
          'id': _uuid.v4(),
          'transaction_id': transactionId,
          'category_id': categoryIds[i],
          'amount_rial': base + (i < remainder ? 1 : 0),
        });
      }
      await batch.commit(noResult: true);
    }

    final data = <String, Object?>{
      'needs_review': 0,
      'review_reason': null,
      'updated_at': _nowIso(),
      'sync_status': 'pending',
    };
    if (description != null) data['description'] = description;
    await _db.update('transactions', data,
        where: 'id = ?', whereArgs: [transactionId]);

    final record = await getById(transactionId);
    if (record != null) await _enqueueOutbox(record);
  }

  @override
  Future<List<CategoryTotal>> categoryTotals({DateTime? from, DateTime? to}) async {
    final where = StringBuffer("t.kind = 'expense' AND t.deleted_at IS NULL");
    final args = <Object?>[];
    if (from != null) {
      where.write(' AND $_dateExpr >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.write(' AND $_dateExpr < ?');
      args.add(to.toUtc().toIso8601String());
    }
    final rows = await _db.rawQuery('''
      SELECT c.id AS cid, c.name AS cname, COALESCE(SUM(tc.amount_rial), 0) AS total
      FROM transaction_categories tc
      JOIN transactions t ON t.id = tc.transaction_id
      JOIN categories c ON c.id = tc.category_id
      WHERE $where
      GROUP BY c.id, c.name
      ORDER BY total DESC
    ''', args);
    return rows
        .map((r) => CategoryTotal(
              categoryId: r['cid'] as String,
              name: r['cname'] as String,
              amountRial: (r['total'] as int?) ?? 0,
            ))
        .toList();
  }

  @override
  Future<DateTime> categorizeFrom() async {
    final stored = await getSetting(SettingKeys.categorizeFrom);
    if (stored != null) return DateTime.parse(stored);
    // پیش‌فرض: از اول ماه شمسی بعد (تراکنش‌های قدیمی وارد صف دسته‌بندی نمی‌شوند).
    final start = startOfNextJalaliMonth(_clock());
    await setSetting(SettingKeys.categorizeFrom, start.toIso8601String());
    return start;
  }

  @override
  Future<List<TransactionRecord>> uncategorized({int? limit}) async {
    final me = await getSetting(SettingKeys.meUserId);
    final from = await categorizeFrom();
    return _select(
      [
        't.deleted_at IS NULL',
        't.amount_rial IS NOT NULL',
        "t.kind IN ('income','expense')",
        't.needs_review = 0',
        if (me != null) '(t.owner_user_id IS NULL OR t.owner_user_id = ?)',
        '$_dateExpr >= ?',
        'NOT EXISTS (SELECT 1 FROM transaction_categories tc WHERE tc.transaction_id = t.id)',
      ],
      [if (me != null) me, from.toUtc().toIso8601String()],
      limit: limit,
    );
  }

  /// جمع درآمد/هزینه‌ی بازه (همان قاعده‌ی [countsInTotals]).
  @override
  Future<FinanceSummary> summary({DateTime? from, DateTime? to}) async {
    final where = StringBuffer(
      "t.amount_rial IS NOT NULL AND t.kind IN ('income','expense') "
      'AND t.deleted_at IS NULL AND t.needs_review = 0',
    );
    final args = <Object?>[];
    if (from != null) {
      where.write(' AND $_dateExpr >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.write(' AND $_dateExpr < ?');
      args.add(to.toUtc().toIso8601String());
    }

    final rows = await _db.rawQuery(
      'SELECT t.kind AS kind, COALESCE(SUM(t.amount_rial), 0) AS total '
      'FROM transactions t WHERE $where GROUP BY t.kind',
      args,
    );

    var income = 0;
    var expense = 0;
    for (final row in rows) {
      final kind = row['kind'] as String;
      final total = (row['total'] as int?) ?? 0;
      if (kind == 'income') {
        income = total;
      } else if (kind == 'expense') {
        expense = total;
      }
    }
    return FinanceSummary(incomeRial: income, expenseRial: expense);
  }

  @override
  Future<int> pendingSyncCount() async {
    return Sqflite.firstIntValue(
          await _db.rawQuery("SELECT COUNT(*) FROM outbox WHERE status = 'pending'"),
        ) ??
        0;
  }

  @override
  Future<String?> getSetting(String key) async {
    final rows = await _db.query('settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
      return;
    }
    await _db.insert('settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------------------------
  // کمک‌تابع‌های همگام‌سازی (SyncService)
  // ---------------------------------------------------------------------------

  /// اعمال یک تراکنش دریافتی از سرور (گوشی عضو دیگر یا نسخه‌ی سرورِ همین).
  /// اگر تغییر محلیِ ارسال‌نشده‌ای دارد، نسخه‌ی محلی مقدم است.
  Future<void> applyRemote(Map<String, dynamic> j) async {
    final id = j['id'].toString();
    final pending = await _db.query('outbox',
        columns: ['transaction_id'],
        where: 'transaction_id = ?',
        whereArgs: [id],
        limit: 1);
    if (pending.isNotEmpty) return;

    String? str(Object? v) =>
        (v == null || (v is String && v.isEmpty)) ? null : v.toString();
    DateTime? dt(Object? v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toUtc();
    final nowIso = _nowIso();
    final editedAt = dt(j['client_updated_at']) ?? dt(j['updated_at']) ?? _clock().toUtc();
    final deleted = j['is_deleted'] == true;

    final fields = <String, Object?>{
      'kind': j['kind'],
      'amount_rial': (j['amount_rial'] as num?)?.toInt(),
      'balance_after_rial': (j['balance_after_rial'] as num?)?.toInt(),
      'raw_amount': str(j['raw_amount']),
      'raw_unit': str(j['raw_unit']) ?? 'rial',
      'counterparty': str(j['counterparty']),
      'description': str(j['description']),
      'bank_id': str(j['bank_id']),
      'card_last4': str(j['card_last4']),
      'transaction_date': dt(j['transaction_date'])?.toIso8601String(),
      'needs_review': j['needs_review'] == true ? 1 : 0,
      'owner_user_id': str(j['owner']),
      'owner_name': str(j['owner_name']),
      'wallet_label': str(j['wallet_label']),
      'sync_status': 'synced',
      'updated_at': editedAt.toIso8601String(),
    };

    final existing = await _db.query('transactions',
        columns: ['id', 'deleted_at', 'origin'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1);
    if (existing.isNotEmpty) {
      final row = existing.first;
      fields['deleted_at'] = deleted ? (row['deleted_at'] ?? nowIso) : null;
      if (row['origin'] == 'local') {
        // صاحبِ تراکنش‌های همین گوشی را کیف‌های همین گوشی تعیین می‌کنند.
        fields
          ..remove('owner_user_id')
          ..remove('owner_name')
          ..remove('wallet_label')
          ..remove('bank_id')
          ..remove('card_last4');
      }
      await _db.update('transactions', fields, where: 'id = ?', whereArgs: [id]);
    } else {
      final hash = str(j['source_message_hash']);
      if (hash != null) {
        final same = await _db.query('transactions',
            columns: ['id'],
            where: 'source_message_hash = ?',
            whereArgs: [hash],
            limit: 1);
        if (same.isNotEmpty) {
          // همان پیامک روی این گوشی هم ثبت شده؛ ردیف محلی شناسه‌ی سرور را می‌گیرد.
          await rekey(same.first['id'] as String, id);
          return applyRemote(j);
        }
      }
      final created =
          dt(j['client_created_at']) ?? dt(j['created_at']) ?? _clock().toUtc();
      await _db.insert('transactions', {
        ...fields,
        'id': id,
        'source': str(j['source']) ?? 'sms',
        'source_message_hash': hash,
        'client_created_at': created.toIso8601String(),
        'created_at': created.toIso8601String(),
        'deleted_at': deleted ? nowIso : null,
        'origin': 'remote',
      });
    }
    await _replaceAllocationsByName(id, j['allocations']);
  }

  Future<void> _replaceAllocationsByName(String id, Object? raw) async {
    final list = raw is List ? raw : const [];
    await _db.delete('transaction_categories',
        where: 'transaction_id = ?', whereArgs: [id]);
    for (final item in list) {
      if (item is! Map) continue;
      final name = item['name']?.toString() ?? '';
      final amount = (item['amount_rial'] as num?)?.toInt();
      if (name.isEmpty || amount == null) continue;
      await _db.insert(
        'transaction_categories',
        {
          'id': _uuid.v4(),
          'transaction_id': id,
          'category_id': await _categoryIdByName(name),
          'amount_rial': amount,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// سرور همین تراکنش را با شناسه‌ی دیگری دارد (همان پیامک از گوشی دیگر، یا نصب
  /// دوباره‌ی اپ) → ردیف محلی به شناسه‌ی سرور منتقل می‌شود.
  Future<void> rekey(String oldId, String newId) async {
    if (oldId == newId) return;
    final clash = await _db.query('transactions',
        columns: ['id'], where: 'id = ?', whereArgs: [newId], limit: 1);
    await _db.transaction((txn) async {
      if (clash.isNotEmpty) {
        final old = await txn.query('transactions',
            columns: ['sms_sender', 'sms_body', 'sms_received_at', 'sms_content_hash'],
            where: 'id = ?',
            whereArgs: [oldId],
            limit: 1);
        if (old.isNotEmpty) {
          await txn.update('transactions', old.first,
              where: 'id = ? AND sms_body IS NULL', whereArgs: [newId]);
        }
        await txn.delete('transaction_categories',
            where: 'transaction_id = ?', whereArgs: [oldId]);
        await txn.delete('outbox', where: 'transaction_id = ?', whereArgs: [oldId]);
        await txn.delete('transactions', where: 'id = ?', whereArgs: [oldId]);
      } else {
        await txn.update('transactions', {'id': newId},
            where: 'id = ?', whereArgs: [oldId]);
        await txn.update('transaction_categories', {'transaction_id': newId},
            where: 'transaction_id = ?', whereArgs: [oldId]);
        await txn.update('outbox', {'transaction_id': newId},
            where: 'transaction_id = ?', whereArgs: [oldId]);
      }
    });
  }
}
