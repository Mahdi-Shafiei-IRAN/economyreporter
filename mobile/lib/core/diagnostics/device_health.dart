/// مدلِ «سلامتِ» برنامه روی یک گوشی: حکمِ کلی (سالم / نیاز به بررسی / مشکل)، دلیل‌ها، بانک‌ها و
/// حساب‌ها. ساختنش در `features/ledger/ledger_health.dart` است. همین خلاصه به سرور می‌رود تا مدیرِ
/// خانواده ببیند برنامه روی گوشیِ بقیه درست کار می‌کند؛ پس **هیچ متنِ پیامک، شماره‌ی حساب/کارت یا
/// سرشماره‌ای در آن نیست** — فقط نامِ بانک، شمارش، مبلغ و زمان.
library;

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

