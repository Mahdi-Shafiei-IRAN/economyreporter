/// سلامتِ برنامه روی نسخه‌ی ۲ (طرح ۱۲.۸): از دفترِ همین گوشی ساخته می‌شود و هر ۶ ساعت به سرور می‌رود
/// تا مدیرِ خانواده ببیند برنامه روی گوشیِ بقیه درست کار می‌کند. **بدونِ متنِ پیامک، شماره‌ی حساب/کارت
/// یا سرشماره** — فقط نامِ بانک، شمارش، مبلغ و زمان.
library;

import 'package:flutter/material.dart';

import '../../core/diagnostics/device_health.dart';
import '../../core/family/health_api.dart';
import '../../core/format/money_format.dart';
import '../../core/ledger/ledger_math.dart';
import '../../core/ledger/models.dart';
import '../../core/sms/bank_registry.dart';
import '../../core/sms/sms_parser.dart';
import '../senders/data/allowed_sender.dart';
import 'health_card.dart';
import 'ledger_controller.dart';

const kLedgerHealthReportedAt = 'ledger_health_reported_at';
const kReportEvery = Duration(hours: 6);
const kDevicesHealthKey = Key('devices-health');

String _fa(int n) => toPersianDigits('$n');

DeviceHealthReport ledgerHealthReport(LedgerController c, {String? appVersion}) {
  final now = c.now;
  final issues = <HealthIssue>[];
  if (c.banks.isEmpty) {
    issues.add(const HealthIssue(HealthLevel.bad, 'no_senders',
        'هیچ بانکی انتخاب نشده؛ هیچ پیامکی خوانده نمی‌شود.',
        hint: 'تنظیمات / بانک‌ها'));
  }
  final oldPending = c.pendingActive.where((i) => now.difference(i.receivedAt) > const Duration(days: 3)).length;
  if (oldPending > 0) {
    issues.add(HealthIssue(HealthLevel.warn, 'pending_old',
        '${_fa(oldPending)} پیامک بیش از ۳ روز منتظرِ تأیید مانده.',
        hint: 'خانه / کارتِ «قدمِ بعدی»'));
  }
  if (c.accountCandidates.isNotEmpty) {
    issues.add(HealthIssue(HealthLevel.warn, 'accounts_found',
        '${_fa(c.accountCandidates.length)} حساب در پیامک‌ها پیدا شده که هنوز تأیید نشده.',
        hint: 'خانه / کارتِ «قدمِ بعدی»'));
  }
  final noAnchor = c.activeAccounts.where((a) => a.needsAnchor).length;
  if (noAnchor > 0) {
    issues.add(HealthIssue(HealthLevel.warn, 'no_anchor',
        '${_fa(noAnchor)} حساب هنوز «موجودیِ الان» ندارد؛ موجودی‌اش نامعلوم است.',
        hint: 'خانه / کارتِ حساب'));
  }
  final withWindows = c.activeAccounts.where((a) => a.discrepancyCount > 0).toList();
  if (withWindows.isNotEmpty) {
    final n = withWindows.fold<int>(0, (s, a) => s + a.discrepancyCount);
    issues.add(HealthIssue(HealthLevel.warn, 'chain',
        '${_fa(n)} جا در ${_fa(withWindows.length)} حساب با مانده‌ی بانک نمی‌خواند.',
        hint: 'خانه / لمسِ همان حساب'));
  }
  if (c.lastSyncError != null) {
    issues.add(HealthIssue(HealthLevel.warn, 'sync_failed', 'آخرین همگام‌سازی نشد: ${c.lastSyncError}.',
        hint: 'تنظیمات / پشتیبان روی سرور'));
  } else if (c.lastSyncAt == null || now.difference(c.lastSyncAt!) > const Duration(days: 2)) {
    issues.add(const HealthIssue(HealthLevel.warn, 'sync_stale',
        'بیش از ۲ روز است با سرور همگام نشده (اینترنت یا باز نشدنِ برنامه).',
        hint: 'تنظیمات / پشتیبان روی سرور'));
  }

  // بانک‌ها: پیامک‌های رسیده از تاریخِ شروع، ثبت‌شده و منتظر.
  final perBank = <String, ({int sms, int counted, int missing})>{};
  for (final i in c.allSmsItems) {
    final bank = findAllowedSender(c.banks, i.sender)?.bankId;
    final name = bank == null ? 'بدونِ بانک' : bankNameById(bank);
    final prev = perBank[name] ?? (sms: 0, counted: 0, missing: 0);
    perBank[name] = (
      sms: prev.sms + 1,
      counted: prev.counted + (i.status == SmsStatus.accepted ? 1 : 0),
      missing: prev.missing + (i.status == SmsStatus.pending ? 1 : 0),
    );
  }

  return DeviceHealthReport(
    at: now,
    appVersion: appVersion,
    parserVersion: kParserVersion,
    lastSyncAt: c.lastSyncAt,
    issues: issues,
    banks: [
      for (final e in perBank.entries)
        BankHealth(name: e.key, sms: e.value.sms, counted: e.value.counted, missing: e.value.missing),
    ],
    accounts: [
      for (final v in c.activeAccounts)
        AccountHealth(
          title: [
            if (v.account.bankId != null) bankNameById(v.account.bankId!) else 'نقد',
            v.account.label,
          ].join(' • '),
          transactions: c.ledgerOf(v.account.id).whereType<EntryItem>().length,
          problems: v.discrepancyCount,
          balanceRial: v.balance?.balanceRial,
          lastAt: v.balance?.anchor.at,
        ),
    ],
  );
}

/// فرستادنِ سلامت اگر ۶ ساعت گذشته (یا [force]). بی‌صدا اگر آفلاین.
Future<bool> reportLedgerHealthIfDue(LedgerController c,
    {required HealthApi api, required String deviceId, String? appVersion, bool force = false}) async {
  final last = DateTime.tryParse(await c.repo.value(kLedgerHealthReportedAt) ?? '');
  if (!force && last != null && c.now.difference(last) < kReportEvery) return false;
  try {
    await api.report(deviceId: deviceId, report: ledgerHealthReport(c, appVersion: appVersion));
    await c.repo.setValue(kLedgerHealthReportedAt, c.now.toIso8601String());
    return true;
  } catch (_) {
    return false;
  }
}

/// «سلامتِ برنامه روی گوشی‌ها»: این گوشی (همین الان) + گزارشِ گوشی‌های دیگر (مدیر: همه‌ی اعضا).
class LedgerDevicesHealthScreen extends StatefulWidget {
  final LedgerController controller;
  final HealthApi api;
  final String deviceId;
  final String? appVersion;

  const LedgerDevicesHealthScreen({
    super.key,
    required this.controller,
    required this.api,
    required this.deviceId,
    this.appVersion,
  });

  @override
  State<LedgerDevicesHealthScreen> createState() => _LedgerDevicesHealthScreenState();
}

class _LedgerDevicesHealthScreenState extends State<LedgerDevicesHealthScreen> {
  late Future<List<RemoteDeviceHealth>> _remote = _load();

  Future<List<RemoteDeviceHealth>> _load() async {
    await reportLedgerHealthIfDue(widget.controller,
        api: widget.api, deviceId: widget.deviceId, appVersion: widget.appVersion, force: true);
    return widget.api.family();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('سلامتِ برنامه روی گوشی‌ها'),
        actions: [
          IconButton(
            tooltip: 'دوباره',
            onPressed: () => setState(() => _remote = _load()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        key: kDevicesHealthKey,
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'هر گوشی وضعیتِ خودش را هر چند ساعت یک بار برای سرور می‌فرستد: پیامک‌های منتظر، حساب‌های '
            'بی‌موجودی، جاهایی که با مانده‌ی بانک نمی‌خواند و همگام‌سازی. متنِ پیامک و شماره‌ی حساب فرستاده نمی‌شود.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          HealthReportCard(
            key: kHealthCardKey,
            report: ledgerHealthReport(c, appVersion: widget.appVersion),
            title: 'این گوشی',
            subtitle: 'همین الان',
          ),
          const SizedBox(height: 8),
          Text('گوشی‌های دیگر', style: theme.textTheme.titleSmall),
          FutureBuilder<List<RemoteDeviceHealth>>(
            future: _remote,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                    padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('به سرور وصل نشد؛ اینترنت را بررسی کن و دوباره بزن.'),
                );
              }
              final others = [for (final d in snap.data!) if (d.deviceId != widget.deviceId) d];
              if (others.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('هنوز گزارشی از گوشیِ دیگری نیامده. روی آن گوشی نسخه‌ی تازه را نصب و یک '
                      'بار با اینترنت باز کن.'),
                );
              }
              return Column(children: [
                for (var i = 0; i < others.length; i++)
                  HealthReportCard(
                    key: Key('device-health-$i'),
                    report: others[i].report,
                    title: others[i].userName,
                    subtitle: 'گزارش ${healthAgo(others[i].receivedAt ?? others[i].report.at, c.now)}'
                        '${others[i].appVersion.isEmpty ? '' : ' • نسخه‌ی ${toPersianDigits(others[i].appVersion)}'}',
                    stale: c.now.difference(others[i].receivedAt ?? others[i].report.at) > const Duration(days: 2),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}
