/// گزارشِ به‌تفکیکِ کارت: موجودیِ هر کارت + درآمد/هزینه، با انتخابِ ماه (مثل شهریور)،
/// و بازکردنِ هر کارت برای دیدنِ تراکنش‌هایش.
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../../core/theme/app_theme.dart';
import '../dashboard/dashboard_controller.dart';
import '../transactions/data/period.dart';
import '../transactions/data/tx_query.dart';
import '../transactions/transaction_details_sheet.dart';
import '../transactions/widgets/period_bar.dart';
import '../transactions/widgets/tx_widgets.dart';

const kCardsReportEmptyKey = Key('cards-report-empty');

class CardsReportScreen extends StatefulWidget {
  final DashboardController controller;

  const CardsReportScreen({super.key, required this.controller});

  @override
  State<CardsReportScreen> createState() => _CardsReportScreenState();
}

class _CardsReportScreenState extends State<CardsReportScreen> {
  DashboardController get _c => widget.controller;
  late Period _period = _c.period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reports = _c.cardReports(_period);
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش به‌تفکیک کارت')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: PeriodBar(
              period: _period,
              now: _c.now,
              onChanged: (p) => setState(() => _period = p),
            ),
          ),
          Expanded(
            child: reports.isEmpty
                ? const Center(
                    key: kCardsReportEmptyKey,
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('برای این دوره کارتی نیست.'),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: reports.length,
                    itemBuilder: (context, i) =>
                        _CardTile(controller: _c, report: reports[i], theme: theme),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  final DashboardController controller;
  final CardReport report;
  final ThemeData theme;

  const _CardTile(
      {required this.controller, required this.report, required this.theme});

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final fin = FinanceColors.of(context);
    final r = report;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey('card-report-${r.key}'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(r.title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text([
              r.owner,
              if (r.details != null) r.details!,
            ].join(' • '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            if (r.balanceRial != null)
              Text('موجودی: ${formatToman(r.balanceRial!)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.primary, fontWeight: FontWeight.w700)),
            Row(
              children: [
                Text('درآمد ${formatToman(r.incomeRial)}',
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: fin.income)),
                const SizedBox(width: 12),
                Text('هزینه ${formatToman(r.expenseRial)}',
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: fin.expense)),
              ],
            ),
          ],
        ),
        children: [
          if (r.items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('در این دوره تراکنشی ندارد.'),
            )
          else
            for (final t in r.items)
              TransactionTile(
                record: t,
                showOwner: false,
                canEdit: controller.canEdit(t),
                showSms: controller.showSmsText,
                onTap: () => showTransactionDetails(context, controller, t),
              ),
        ],
      ),
    );
  }
}
