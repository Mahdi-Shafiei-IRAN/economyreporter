/// انتخاب بازه: ماه قبل/بعد + فهرست ماه‌ها و «همه‌ی زمان‌ها».
library;

import 'package:flutter/material.dart';

import '../data/period.dart';

const kPeriodPrevKey = Key('period-prev');
const kPeriodNextKey = Key('period-next');
const kPeriodTitleKey = Key('period-title');

class PeriodBar extends StatelessWidget {
  final Period period;
  final DateTime now;
  final ValueChanged<Period> onChanged;

  const PeriodBar({
    super.key,
    required this.period,
    required this.now,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context) async {
    final current = Period.containing(now);
    final months = <Period>[];
    var p = current;
    for (var i = 0; i < 24; i++) {
      months.add(p);
      p = p.previous;
    }
    final picked = await showModalBottomSheet<Period>(
      context: context,
      useSafeArea: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          ListTile(
            leading: const Icon(Icons.all_inclusive_rounded),
            title: const Text('همه‌ی زمان‌ها'),
            selected: period.isAll,
            onTap: () => Navigator.of(context).pop(const Period.all()),
          ),
          const Divider(),
          for (final m in months)
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(m.title),
              subtitle: m == current ? const Text('ماه جاری') : null,
              selected: m == period,
              onTap: () => Navigator.of(context).pop(m),
            ),
        ],
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final current = Period.containing(now);
    final canGoNext = !period.isAll && period != current;
    return Row(
      children: [
        IconButton(
          key: kPeriodPrevKey,
          tooltip: 'ماه قبل',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: period.isAll ? null : () => onChanged(period.previous),
        ),
        Expanded(
          child: Center(
            child: TextButton.icon(
              key: kPeriodTitleKey,
              onPressed: () => _pick(context),
              icon: const Icon(Icons.expand_more_rounded),
              label: Text(
                period.title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
        IconButton(
          key: kPeriodNextKey,
          tooltip: 'ماه بعد',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: canGoNext ? () => onChanged(period.next) : null,
        ),
      ],
    );
  }
}
