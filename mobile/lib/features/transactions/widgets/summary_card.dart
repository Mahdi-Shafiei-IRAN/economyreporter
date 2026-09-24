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
const kOpeningValueKey = Key('summary-opening');
const kRangeLabelKey = Key('summary-range');
const kSummaryTitleKey = Key('summary-title');
const kSummaryExplainKey = Key('summary-explain');
const kSummaryDiscrepancyKey = Key('summary-discrepancy');

class SummaryCard extends StatelessWidget {
  final FinanceSummary summary;
  final Period period;
  final int count;
  final bool filtered;

  /// شخصِ انتخاب‌شده (جمع فقط مال اوست)؛ null یعنی همه.
  final String? scope;

  /// موجودیِ «اولِ دوره» (از «مانده»ی پیامک‌ها)؛ null یعنی مانده‌ای نداریم.
  /// وقتی معلوم باشد: موجودیِ نهایی = اولِ دوره + درآمد − هزینه (منطقی و هم‌خوان).
  final int? openingBalance;

  /// «این عدد از کجا آمده؟» (صفحه‌ی عیب‌یابی)؛ null یعنی دکمه نشان داده نشود.
  final VoidCallback? onExplain;

  /// موجودیِ آخرِ دوره طبق مانده‌ی بانک (جمعِ آخرین مانده‌ی هر حساب). اگر باشد، همین
  /// عددِ اصلی است (چون با بانک یکی است، حتی وقتی پیامکی جا افتاده).
  final int? bankBalance;

  /// بانک − (اولِ دوره + درآمد − هزینه). غیرِ صفر → برچسبِ «مغایرت» که عیب‌یابی را باز می‌کند.
  final int? discrepancy;

  const SummaryCard({
    super.key,
    required this.summary,
    required this.period,
    required this.count,
    this.filtered = false,
    this.scope,
    this.openingBalance,
    this.onExplain,
    this.bankBalance,
    this.discrepancy,
  });

  bool get _hasBalance => openingBalance != null;

  String get _title {
    if (bankBalance != null) {
      return scope != null ? 'موجودی $scope (طبق بانک)' : 'موجودی (طبق مانده‌ی بانک)';
    }
    if (_hasBalance) return scope != null ? 'موجودی نهایی $scope' : 'موجودی نهایی';
    if (scope != null) return 'خالص $scope • ${period.title}';
    return period.isAll ? 'خالص (درآمد − هزینه)' : 'خالص ${period.title}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fin = FinanceColors.of(context);
    const onHero = Colors.white;
    final muted = Colors.white.withOpacity(0.78);
    final net = summary.balanceRial;
    // طبق بانک اگر داریم؛ وگرنه اولِ دوره + (درآمد − هزینه)؛ وگرنه فقط خالص.
    final headline = bankBalance ?? (_hasBalance ? openingBalance! + net : net);
    final d = discrepancy;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  _title,
                  key: kSummaryTitleKey,
                  style: theme.textTheme.labelLarge?.copyWith(color: muted),
                ),
              ),
              if (onExplain != null)
                InkWell(
                  key: kSummaryExplainKey,
                  onTap: onExplain,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.help_outline_rounded, size: 16, color: muted),
                        const SizedBox(width: 4),
                        Text('چرا این عدد؟',
                            style: theme.textTheme.labelSmall?.copyWith(color: muted)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  formatToman(headline),
                  key: kBalanceValueKey,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: onHero,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (_hasBalance) ...[
            const SizedBox(height: 4),
            Text(
              'موجودیِ اولِ ${period.title}: ${formatToman(openingBalance!)}',
              key: kOpeningValueKey,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          if (d != null && d != 0) ...[
            const SizedBox(height: 8),
            InkWell(
              key: kSummaryDiscrepancyKey,
              onTap: onExplain,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFFFD48A)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'مغایرت با تراکنش‌ها: ${formatToman(d)}'
                        '${onExplain == null ? '' : ' — ببین کجاست'}',
                        style: theme.textTheme.bodySmall?.copyWith(color: onHero),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
