/// «سلامتِ» برنامه روی یک گوشی: آیا پیامک‌های بانکِ این گوشی درست شمرده می‌شوند؟
///
/// از همان عیب‌یابی ساخته می‌شود (پیامک‌ها و زنجیره‌ی مانده)، با حکمِ کلی
/// سالم / نیاز به بررسی / مشکل و فهرستِ دلیل‌ها. همین خلاصه به سرور می‌رود تا مدیرِ
/// خانواده بدونِ دست زدن به گوشیِ بقیه ببیند برنامه آنجا درست کار می‌کند یا نه؛ پس
/// **هیچ متنِ پیامک، شماره‌ی حساب/کارت یا سرشماره‌ای در آن نیست** — فقط نامِ بانک، شمارش،
/// مبلغ و زمان.
library;

import '../../features/senders/data/allowed_sender.dart';
import '../../features/transactions/data/transaction_record.dart';
import '../sms/bank_registry.dart';
import '../sync/sync_service.dart';
import 'balance_chain.dart';
import 'sms_diagnosis.dart';

enum HealthLevel {
  ok('سالم'),
  warn('نیاز به بررسی'),
  bad('مشکل');

  final String label;
  const HealthLevel(this.label);

  static HealthLevel parse(String? s) =>
      HealthLevel.values.firstWhere((l) => l.name == s, orElse: () => HealthLevel.warn);
}

class HealthIssue {
  final HealthLevel level;

  /// شناسه‌ی ثابت (برای تست و آمار): no_permission، no_senders، not_imported، bank_silent،
  /// deleted_valid، no_id، chain، sync_failed، sync_stale.
  final String code;

  /// متنِ فارسی برای نمایش.
  final String text;

  /// کجا درستش کنم.
  final String? hint;

  const HealthIssue(this.level, this.code, this.text, {this.hint});

  Map<String, Object?> toJson() =>
      {'level': level.name, 'code': code, 'text': text, if (hint != null) 'hint': hint};

  factory HealthIssue.fromJson(Map<String, dynamic> j) => HealthIssue(
      HealthLevel.parse(j['level'] as String?), '${j['code']}', '${j['text']}',
      hint: j['hint'] as String?);
}

/// پیامک‌های یک بانک روی این گوشی.
class BankHealth {
  final String name;

  /// پیامکِ مبلغ‌دارِ این بانک در صندوق (و ثبت‌شده‌هایی که پیامکشان پاک شده).
  final int sms;
  final int counted;

  /// پیامکِ تراکنشی که ثبت نشده (باید صفر باشد).
  final int missing;

  const BankHealth({required this.name, required this.sms, required this.counted, this.missing = 0});

  Map<String, Object?> toJson() => {'name': name, 'sms': sms, 'counted': counted, 'missing': missing};

  factory BankHealth.fromJson(Map<String, dynamic> j) => BankHealth(
        name: '${j['name']}',
        sms: (j['sms'] as num?)?.toInt() ?? 0,
        counted: (j['counted'] as num?)?.toInt() ?? 0,
        missing: (j['missing'] as num?)?.toInt() ?? 0,
      );
}

/// یک حساب/کارت (بدونِ شماره؛ فقط بانک و نوع).
class AccountHealth {
  final String title;
  final int transactions;

  /// جاهای ناجورِ زنجیره‌ی مانده.
  final int problems;
  final int? balanceRial;
  final DateTime? lastAt;

  const AccountHealth({
    required this.title,
    required this.transactions,
    required this.problems,
    this.balanceRial,
    this.lastAt,
  });

  Map<String, Object?> toJson() => {
        'title': title,
        'tx': transactions,
        'problems': problems,
        if (balanceRial != null) 'balance': balanceRial,
        if (lastAt != null) 'last_at': lastAt!.toUtc().toIso8601String(),
      };

  factory AccountHealth.fromJson(Map<String, dynamic> j) => AccountHealth(
        title: '${j['title']}',
        transactions: (j['tx'] as num?)?.toInt() ?? 0,
        problems: (j['problems'] as num?)?.toInt() ?? 0,
        balanceRial: (j['balance'] as num?)?.toInt(),
        lastAt: DateTime.tryParse('${j['last_at']}'),
      );
}

class DeviceHealthReport {
  final DateTime at;
  final String? appVersion;
  final int? parserVersion;
  final bool inboxRead;
  final DateTime? lastSyncAt;
  final List<HealthIssue> issues;
  final List<BankHealth> banks;
  final List<AccountHealth> accounts;

  const DeviceHealthReport({
    required this.at,
    required this.issues,
    this.appVersion,
    this.parserVersion,
    this.inboxRead = true,
    this.lastSyncAt,
    this.banks = const [],
    this.accounts = const [],
  });

  HealthLevel get level => issues.any((i) => i.level == HealthLevel.bad)
      ? HealthLevel.bad
      : issues.any((i) => i.level == HealthLevel.warn)
          ? HealthLevel.warn
          : HealthLevel.ok;

  Map<String, Object?> toJson() => {
        'at': at.toUtc().toIso8601String(),
        if (appVersion != null) 'app_version': appVersion,
        if (parserVersion != null) 'parser': parserVersion,
        'inbox_read': inboxRead,
        if (lastSyncAt != null) 'last_sync': lastSyncAt!.toUtc().toIso8601String(),
        'level': level.name,
        'issues': [for (final i in issues) i.toJson()],
        'banks': [for (final b in banks) b.toJson()],
        'accounts': [for (final a in accounts) a.toJson()],
      };

  factory DeviceHealthReport.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) => [
          for (final e in (j[k] as List? ?? const []))
            if (e is Map) Map<String, dynamic>.from(e),
        ];
    return DeviceHealthReport(
      at: DateTime.tryParse('${j['at']}') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      appVersion: j['app_version'] as String?,
      parserVersion: (j['parser'] as num?)?.toInt(),
      inboxRead: j['inbox_read'] != false,
      lastSyncAt: DateTime.tryParse('${j['last_sync']}'),
      issues: [for (final e in list('issues')) HealthIssue.fromJson(e)],
      banks: [for (final e in list('banks')) BankHealth.fromJson(e)],
      accounts: [for (final e in list('accounts')) AccountHealth.fromJson(e)],
    );
  }
}

String _fa(int n) {
  const digits = '۰۱۲۳۴۵۶۷۸۹';
  return n.toString().split('').map((c) {
    final d = int.tryParse(c);
    return d == null ? c : digits[d];
  }).join();
}

/// نامِ بانک (بدونِ شماره) یا «پیامک‌های بدونِ بانک».
String _bankName(String? bankId) => bankId == null ? 'بدونِ بانک' : bankNameById(bankId);

/// حکمِ سلامت از روی عیب‌یابیِ همین گوشی.
///
/// [chains]: زنجیره‌ی مانده‌ی تراکنش‌های **همین گوشی** (نه نسخه‌های اعضای دیگر).
/// [restorable]: حذف‌شده‌هایی که با قانون می‌خوانند و تکراری نیستند.
DeviceHealthReport computeDeviceHealth({
  required SmsDiagnosisReport sms,
  required BalanceChainReport chains,
  required List<AllowedSender> allowed,
  required DateTime now,
  int restorable = 0,
  SyncStatusInfo? sync,
  String? appVersion,
  int? parserVersion,
}) {
  final issues = <HealthIssue>[];

  if (!sms.inboxRead) {
    issues.add(const HealthIssue(HealthLevel.bad, 'no_permission',
        'برنامه نمی‌تواند پیامک‌ها را بخواند (مجوزِ پیامک خاموش است).',
        hint: 'تنظیماتِ گوشی / برنامه‌ها / مالی خانواده / مجوزها / پیامک'));
  }
  if (allowed.isEmpty) {
    issues.add(const HealthIssue(HealthLevel.bad, 'no_senders',
        'هیچ بانکی برای خواندنِ پیامک انتخاب نشده؛ هیچ تراکنشی ثبت نمی‌شود.',
        hint: 'تنظیمات / فرستنده‌های پیامک بانک'));
  }

  // بانک به بانک: پیامکِ مبلغ‌دار، شمرده‌شده، و تراکنشی که ثبت نشده.
  final byBank = <String, ({int sms, int counted, int missing})>{};
  for (final d in sms.items) {
    final hasAmount = d.parsed.amountRial != null && !d.parsed.isOtp;
    if (!hasAmount && !d.verdict.isStored) continue;
    final name = _bankName(d.allowed.bankId ?? d.parsed.bankId ?? d.stored?.bankId);
    final cur = byBank[name] ?? (sms: 0, counted: 0, missing: 0);
    byBank[name] = (
      sms: cur.sms + 1,
      counted: cur.counted + (d.verdict == SmsVerdict.counted || d.verdict == SmsVerdict.transfer ? 1 : 0),
      missing: cur.missing + (d.verdict == SmsVerdict.notImported ? 1 : 0),
    );
  }
  final banks = [
    for (final e in byBank.entries)
      BankHealth(name: e.key, sms: e.value.sms, counted: e.value.counted, missing: e.value.missing),
  ]..sort((a, b) => b.sms.compareTo(a.sms));

  final notImported = sms.count(SmsVerdict.notImported);
  if (notImported > 0) {
    issues.add(HealthIssue(HealthLevel.bad, 'not_imported',
        '${_fa(notImported)} پیامکِ تراکنشی (با شماره‌ی حساب، مبلغ و نوع) ثبت نشده.',
        hint: 'عیب‌یابی / پیامک‌ها / «واردکردن»'));
  }
  for (final b in banks) {
    if (b.name != 'بدونِ بانک' && b.sms >= 2 && b.counted == 0) {
      issues.add(HealthIssue(HealthLevel.warn, 'bank_silent',
          'از ${b.name} ${_fa(b.sms)} پیامکِ مبلغ‌دار هست ولی هیچ‌کدام شمرده نشده.',
          hint: 'عیب‌یابی / پیامک‌ها: دلیلِ ردِ هر پیامک نوشته شده'));
    }
  }
  if (restorable > 0) {
    issues.add(HealthIssue(HealthLevel.warn, 'deleted_valid',
        '${_fa(restorable)} پیامکِ درست (شماره‌ی حساب + مبلغ + نوع) حذف شده و شمرده نمی‌شود.',
        hint: 'عیب‌یابی / پیامک‌ها / «برگرداندنِ …»'));
  }

  // حساب‌ها: بی‌شماره، و ناجوری‌های زنجیره‌ی مانده.
  final accounts = <AccountHealth>[];
  var noIdTx = 0;
  var chainProblems = 0;
  var chainAccounts = 0;
  for (final a in chains.accounts) {
    if (!a.hasId) {
      noIdTx += a.links.length;
      continue;
    }
    final problems = a.problems.length;
    if (problems > 0) {
      chainProblems += problems;
      chainAccounts++;
    }
    TransactionRecord? lastWithBalance;
    for (final l in a.links) {
      if (l.tx.balanceAfterRial != null) lastWithBalance = l.tx;
    }
    final s = a.sample;
    accounts.add(AccountHealth(
      title: '${_bankName(s.bankId)} • ${s.cardLast4 != null ? 'کارت' : 'حساب'}'
          '${(s.walletLabel ?? '').trim().isEmpty ? '' : ' «${s.walletLabel!.trim()}»'}',
      transactions: a.links.length,
      problems: problems,
      balanceRial: lastWithBalance?.balanceAfterRial,
      lastAt: lastWithBalance?.effectiveTime,
    ));
  }
  if (noIdTx > 0) {
    issues.add(HealthIssue(HealthLevel.warn, 'no_id',
        '${_fa(noIdTx)} تراکنش شماره‌ی حساب/کارت ندارد و در موجودیِ هیچ حسابی نیست.',
        hint: 'عیب‌یابی / موجودی / «درست کردنِ خودکار»'));
  }
  if (chainProblems > 0) {
    issues.add(HealthIssue(HealthLevel.warn, 'chain',
        '${_fa(chainProblems)} جای ناجور در زنجیره‌ی مانده‌ی ${_fa(chainAccounts)} حساب '
        '(پیامکِ جاافتاده، کارمزد، یا نوعِ اشتباه).',
        hint: 'عیب‌یابی / زنجیره‌ی مانده'));
  }

  // همگام‌سازی.
  final failure = sync?.last?.failure;
  if (failure != null) {
    issues.add(HealthIssue(HealthLevel.warn, 'sync_failed',
        'آخرین همگام‌سازی کامل نشد: ${sync!.last!.message}',
        hint: 'تنظیمات / همگام‌سازی'));
  } else if (sync?.lastAt != null && now.difference(sync!.lastAt!) > const Duration(days: 3)) {
    issues.add(HealthIssue(HealthLevel.warn, 'sync_stale',
        '${_fa(now.difference(sync.lastAt!).inDays)} روز است با سرور همگام نشده.',
        hint: 'اینترنت را روشن کن و «همگام‌سازی» را بزن'));
  }

  return DeviceHealthReport(
    at: now,
    appVersion: appVersion,
    parserVersion: parserVersion,
    inboxRead: sms.inboxRead,
    lastSyncAt: sync?.lastAt,
    issues: issues,
    banks: banks,
    accounts: accounts,
  );
}
