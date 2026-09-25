/// نمایشِ «سلامتِ برنامه» روی یک گوشی، و صفحه‌ی «سلامتِ گوشی‌های خانواده» که مدیر با آن
/// می‌فهمد برنامه روی گوشیِ بقیه درست کار می‌کند یا نه، بی‌آنکه گوشی دستش باشد.
library;

import 'package:flutter/material.dart';

import '../../core/diagnostics/device_health.dart';
import '../../core/family/health_api.dart';
import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/theme/app_theme.dart';
import '../dashboard/dashboard_controller.dart';
import '../transactions/data/transaction_repository.dart';
import 'diagnostics_screen.dart';

const kHealthCardKey = Key('health-card');
const kDevicesHealthKey = Key('devices-health');

String _fa(int n) => toPersianDigits('$n');

/// «۳ ساعت پیش»
String healthAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 2) return 'همین الان';
  if (d.inHours < 1) return '${_fa(d.inMinutes)} دقیقه پیش';
  if (d.inDays < 1) return '${_fa(d.inHours)} ساعت پیش';
  return '${_fa(d.inDays)} روز پیش';
}

({Color fg, Color bg, IconData icon}) _style(BuildContext context, HealthLevel level) {
  final fin = FinanceColors.of(context);
  return switch (level) {
    HealthLevel.ok => (fg: fin.income, bg: fin.incomeContainer, icon: Icons.check_circle_rounded),
    HealthLevel.warn => (fg: fin.warning, bg: fin.warningContainer, icon: Icons.error_outline_rounded),
    HealthLevel.bad => (fg: fin.expense, bg: fin.expenseContainer, icon: Icons.cancel_rounded),
  };
}

/// کارتِ سلامتِ یک گوشی: حکم، دلیل‌ها (با «کجا درستش کنم»)، بانک‌ها و حساب‌ها.
class HealthReportCard extends StatelessWidget {
  final DeviceHealthReport report;
  final String title;
  final String? subtitle;

  /// «آخرین گزارش» خیلی قدیمی است؟ (گوشی مدتی باز نشده یا اینترنت نداشته.)
  final bool stale;

  const HealthReportCard({
    super.key,
    required this.report,
    required this.title,
    this.subtitle,
    this.stale = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final st = _style(context, report.level);
    final small = theme.textTheme.bodySmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(st.icon, color: st.fg),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: small?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(20)),
                child: Text(report.level.label,
                    style: small?.copyWith(color: st.fg, fontWeight: FontWeight.w700)),
              ),
            ]),
            if (stale) ...[
              const SizedBox(height: 8),
              Text('این گزارش قدیمی است: برنامه روی این گوشی مدتی باز نشده یا اینترنت نداشته.',
                  style: small?.copyWith(color: FinanceColors.of(context).warning)),
            ],
            const SizedBox(height: 8),
            if (report.issues.isEmpty)
              Text('همه‌ی پیامک‌های بانک شمرده شده‌اند و مانده‌ها با بانک جورند.', style: small)
            else
              for (final i in report.issues) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(_style(context, i.level).icon,
                        size: 16, color: _style(context, i.level).fg),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.text, style: theme.textTheme.bodyMedium),
                      if (i.hint != null)
                        Text('کجا: ${i.hint}',
                            style: small?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 6),
              ],
            if (report.banks.isNotEmpty) ...[
              const Divider(),
              for (final b in report.banks)
                Text(
                  '${b.name}: ${_fa(b.sms)} پیامکِ مبلغ‌دار، ${_fa(b.counted)} شمرده شد'
                  '${b.missing > 0 ? '، ${_fa(b.missing)} ثبت‌نشده' : ''}',
                  style: small,
                ),
            ],
            if (report.accounts.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final a in report.accounts)
                Text(
                  '${a.title}: ${_fa(a.transactions)} تراکنش'
                  '${a.balanceRial == null ? '' : '، مانده‌ی بانک ${formatToman(a.balanceRial!)}'}'
                  '${a.lastAt == null ? '' : ' (${formatJalaliNumeric(a.lastAt!)})'}'
                  '${a.problems > 0 ? '، ${_fa(a.problems)} ناجور' : ''}',
                  style: small,
                ),
            ],
            if (report.appVersion != null || report.lastSyncAt != null) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (report.appVersion != null) 'نسخه‌ی ${toPersianDigits(report.appVersion!)}',
                  if (report.lastSyncAt != null)
                    'آخرین همگام‌سازی ${healthAgo(report.lastSyncAt!, report.at)}',
                ].join(' • '),
                style: small?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// «سلامتِ گوشی‌های خانواده»: این گوشی (همین الان) + گزارشی که هر گوشیِ دیگر فرستاده.
/// مدیر گوشیِ همه‌ی اعضا را می‌بیند؛ عضوِ عادی فقط گوشی‌های خودش را.
class DevicesHealthScreen extends StatefulWidget {
  final DashboardController controller;

  const DevicesHealthScreen({super.key, required this.controller});

  @override
  State<DevicesHealthScreen> createState() => _DevicesHealthScreenState();
}

class _DevicesHealthScreenState extends State<DevicesHealthScreen> {
  late Future<DeviceHealthReport> _local = _loadLocal();
  late Future<List<RemoteDeviceHealth>> _remote = _loadRemote();
  String? _deviceId;

  Future<DeviceHealthReport> _loadLocal() async {
    final c = widget.controller;
    _deviceId = await c.repository.getSetting(SettingKeys.deviceId);
    final h = await c.deviceHealth();
    // تازه‌ترین وضعیتِ همین گوشی برای بقیه هم.
    await c.reportHealthIfDue(health: h);
    return h;
  }

  Future<List<RemoteDeviceHealth>> _loadRemote() async {
    final api = widget.controller.healthApi;
    if (api == null) return const [];
    await _local.catchError((_) => DeviceHealthReport(at: DateTime.now(), issues: const []));
    return api.family();
  }

  void _reload() => setState(() {
        _local = _loadLocal();
        _remote = _loadRemote();
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = widget.controller.now;
    return Scaffold(
      appBar: AppBar(
        title: const Text('سلامتِ برنامه روی گوشی‌ها'),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: ListView(
        key: kDevicesHealthKey,
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'هر گوشی وضعیتِ خودش را هر چند ساعت یک بار (و هر بار که این صفحه یا عیب‌یابی باز '
            'شود) برای سرور می‌فرستد: کدام بانک‌ها پیامکشان شمرده می‌شود، کدام پیامک ثبت نشده '
            'و مانده‌ها با بانک جورند یا نه. متنِ پیامک و شماره‌ی حساب فرستاده نمی‌شود.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          FutureBuilder<DeviceHealthReport>(
            future: _local,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) return Text('وضعیتِ این گوشی خوانده نشد: ${snap.error}');
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                HealthReportCard(
                  key: kHealthCardKey,
                  report: snap.data!,
                  title: 'این گوشی',
                  subtitle: 'همین الان',
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => DiagnosticsScreen(controller: widget.controller))),
                    icon: const Icon(Icons.troubleshoot),
                    label: const Text('عیب‌یابیِ این گوشی'),
                  ),
                ),
              ]);
            },
          ),
          const SizedBox(height: 8),
          Text('گوشی‌های دیگر', style: theme.textTheme.titleSmall),
          FutureBuilder<List<RemoteDeviceHealth>>(
            future: _remote,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('به سرور وصل نشد؛ اینترنت را بررسی کن و دوباره بزن.'),
                );
              }
              final others = [
                for (final d in snap.data!)
                  if (d.deviceId != _deviceId) d,
              ];
              if (others.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                      'هنوز گزارشی از گوشیِ دیگری نیامده. روی آن گوشی نسخه‌ی تازه را نصب کن و '
                      'یک بار برنامه را باز کن (با اینترنت).'),
                );
              }
              return Column(children: [
                for (var i = 0; i < others.length; i++)
                  HealthReportCard(
                    key: Key('device-health-$i'),
                    report: others[i].report,
                    title: others[i].userName,
                    subtitle: 'گزارش ${healthAgo(others[i].receivedAt ?? others[i].report.at, now)}'
                        '${others[i].appVersion.isEmpty ? '' : ' • نسخه‌ی ${toPersianDigits(others[i].appVersion)}'}',
                    stale: now.difference(others[i].receivedAt ?? others[i].report.at) >
                        const Duration(days: 2),
                  ),
              ]);
            },
          ),
        ],
      ),
    );
  }
}
