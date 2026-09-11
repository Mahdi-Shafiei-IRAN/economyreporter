/// کارت خلاصه‌ی بازه: خالص + درآمد + هزینه، با تاریخ دقیقِ «از … تا …».
library;

import 'package:flutter/material.dart';

import '../../../core/format/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../data/period.dart';
import '../data/transaction_repository.dart';

const kIncomeValueKey = Key('summary-income');
const kExpenseValueKey = Key('summary-expense');
const kBalanceValueKey = Key('summary-balance');
const kRangeLabelKey = Key('summary-range');

class SummaryCard extends StatelessWidget {
  final FinanceSummary summary;
  final Period period;
  final int count;
  final bool filtered;

  const SummaryCard({
    super.key,
    required this.summary,
    required this.period,
    required this.count,
    this.filtered = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fin = FinanceColors.of(context);
    const onHero = Colors.white;
    final muted = Colors.white.withOpacity(0.78);
    final net = summary.balanceRial;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [fin.heroStart, fin.heroEnd],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            period.isAll ? 'خالص (درآمد − هزینه)' : 'خالص ${period.title}',
            style: theme.textTheme.labelLarge?.copyWith(color: muted),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  formatToman(net),
                  key: kBalanceValueKey,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: onHero,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  icon: Icons.south_west_rounded,
                  label: 'درآمد (واریز)',
                  value: formatToman(summary.incomeRial),
                  valueKey: kIncomeValueKey,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              const SizedBox(width: 16),
              Expanded(
                child: _Figure(
                  icon: Icons.north_east_rounded,
                  label: 'هزینه (برداشت)',
                  value: formatToman(summary.expenseRial),
                  valueKey: kExpenseValueKey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.date_range_rounded, size: 16, color: muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  period.rangeLabel,
                  key: kRangeLabelKey,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              Text(
                '${toPersianDigits('$count')} تراکنش${filtered ? ' (فیلترشده)' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Key valueKey;

  const _Figure({
    required this.icon,
    required this.label,
    required this.value,
    required this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: Colors.white12,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: Colors.white.withOpacity(0.78), fontSize: 12)),
              Text(
                value,
                key: valueKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
