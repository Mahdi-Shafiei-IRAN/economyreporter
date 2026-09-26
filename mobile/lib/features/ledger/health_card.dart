/// کارتِ «سلامتِ برنامه» روی یک گوشی: حکم، دلیل‌ها (با «کجا درستش کنم»)، بانک‌ها و حساب‌ها.
library;

import 'package:flutter/material.dart';

import '../../core/diagnostics/device_health.dart';
import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/theme/app_theme.dart';

const kHealthCardKey = Key('health-card');

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
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      Text(subtitle!, style: small?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
              Text('پیامک‌ها تأیید شده‌اند و موجودی‌ها با بانک جورند.', style: small)
            else
              for (final i in report.issues) ...[
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(_style(context, i.level).icon, size: 16, color: _style(context, i.level).fg),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.text, style: theme.textTheme.bodyMedium),
                      if (i.hint != null)
                        Text('کجا: ${i.hint}', style: small?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 6),
              ],
            if (report.banks.isNotEmpty) ...[
              const Divider(),
              for (final b in report.banks)
                Text(
                  '${b.name}: ${_fa(b.sms)} پیامک، ${_fa(b.counted)} ثبت‌شده'
                  '${b.missing > 0 ? '، ${_fa(b.missing)} منتظر' : ''}',
                  style: small,
                ),
            ],
            if (report.accounts.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final a in report.accounts)
                Text(
                  '${a.title}: ${_fa(a.transactions)} تراکنش'
                  '${a.balanceRial == null ? '' : '، موجودی ${formatToman(a.balanceRial!)}'}'
                  '${a.lastAt == null ? '' : ' (${formatJalaliNumeric(a.lastAt!)})'}'
                  '${a.problems > 0 ? '، ${_fa(a.problems)} اختلاف' : ''}',
                  style: small,
                ),
            ],
            if (report.appVersion != null || report.lastSyncAt != null) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (report.appVersion != null) 'نسخه‌ی ${toPersianDigits(report.appVersion!)}',
                  if (report.lastSyncAt != null) 'آخرین همگام‌سازی ${healthAgo(report.lastSyncAt!, report.at)}',
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
