/// تراکنش‌های احتمالاً تکراری: یک رخداد (مثل حقوق) که دوبار ثبت شده. کاربر یکی را
/// نگه می‌دارد و بقیه را حذف می‌کند، یا می‌گوید «تکراری نیست».
library;

import 'package:flutter/material.dart';

import '../../core/dedup/duplicate_finder.dart';
import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../transactions/data/transaction_record.dart';
import '../dashboard/dashboard_controller.dart';
import '../transactions/data/tx_query.dart';
import '../transactions/widgets/tx_widgets.dart';

const kDuplicatesEmptyKey = Key('duplicates-empty');

String _fa(int n) => toPersianDigits('$n');

class DuplicatesScreen extends StatelessWidget {
  final DashboardController controller;

  const DuplicatesScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تراکنش‌های تکراری')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final groups = controller.duplicateGroups;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _Explain(),
              const SizedBox(height: 12),
              if (groups.isEmpty)
                const Padding(
                  key: kDuplicatesEmptyKey,
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(Icons.done_all_rounded, size: 48),
                      SizedBox(height: 8),
                      Text('تکراریِ مشکوکی پیدا نشد.'),
                    ],
                  ),
                )
              else
                for (final g in groups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _GroupCard(
                      key: ValueKey('dup-${g.key}'),
                      controller: controller,
                      group: g,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _Explain extends StatelessWidget {
  const _Explain();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.secondaryContainer.withOpacity(0.6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'این‌ها تراکنش‌هایی با مبلغ، نوع و کارتِ یکسان‌اند که نزدیک به هم ثبت شده‌اند؛ '
          'ممکن است یک خرید/واریز باشند که دوبار حساب شده (مثلاً بانک دو پیامک داده). '
          'یکی را نگه دار و بقیه را حذف کن، یا اگر واقعاً جدا هستند «تکراری نیست» بزن.',
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final DashboardController controller;
  final DuplicateGroup group;

  const _GroupCard({super.key, required this.controller, required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final style = KindStyle.of(context, group.kind);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(style.icon, color: style.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${style.label} ${formatToman(group.amountRial)}',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Text('${_fa(group.items.length)} مورد',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < group.items.length; i++) ...[
              if (i > 0) const Divider(),
              _Line(index: i, record: group.items[i]),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: ValueKey('dup-resolve-${group.key}'),
                    icon: const Icon(Icons.delete_sweep_rounded),
                    label: Text('حذف تکراری‌ها (${_fa(group.items.length - 1)} مورد)'),
                    onPressed: () => controller.resolveDuplicate(group),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: ValueKey('dup-dismiss-${group.key}'),
                  onPressed: () => controller.dismissDuplicate(group),
                  child: const Text('تکراری نیست'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final int index;
  final TransactionRecord record;

  const _Line({required this.index, required this.record});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = record;
    final keep = index == 0;
    final sms = smsPreviewOf(t);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            keep ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
            size: 18,
            color: keep ? scheme.primary : scheme.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${keep ? 'می‌ماند' : 'حذف'} • ${formatJalaliDateTime(t.effectiveTime)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: keep ? FontWeight.w700 : FontWeight.w400),
              ),
              Text('${personOf(t)} • ${cardTitleOf(t)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              if (sms != null)
                Text(sms,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}
