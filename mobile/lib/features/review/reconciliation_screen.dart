/// ناهماهنگی مانده («پیامک جاافتاده»): توضیح + ثبت دستی یا نادیده گرفتن.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/reconcile/reconciliation.dart';
import '../../core/theme/app_theme.dart';
import '../dashboard/dashboard_controller.dart';
import '../transactions/data/tx_query.dart';

const kReconcileEmptyKey = Key('reconcile-empty');

class ReconciliationScreen extends StatelessWidget {
  final DashboardController controller;

  const ReconciliationScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ناهماهنگی مانده')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final gaps = controller.balanceGaps;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: scheme.secondaryContainer.withOpacity(0.6),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('«پیامک جاافتاده» یعنی چه؟',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(
                        'هر پیامک بانکی «مانده»ی حساب را هم می‌گوید. برنامه مانده‌ی هر '
                        'پیامک را با «مانده‌ی پیامک قبلی ± مبلغ» مقایسه می‌کند. اگر جور '
                        'نباشد، یعنی بین این دو، تراکنشی انجام شده که پیامکش به این گوشی '
                        'نرسیده یا پاک شده — یا بانک کارمزد/سود حساب کرده.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'می‌توانی همان مبلغ را دستی ثبت کنی تا جمع‌ها درست شوند، یا اگر '
                        'مهم نیست «نادیده بگیر» را بزنی.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (gaps.isEmpty)
                const Padding(
                  key: kReconcileEmptyKey,
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(Icons.verified_outlined, size: 48),
                      SizedBox(height: 8),
                      Text('ناهماهنگی‌ای پیدا نشد'),
                    ],
                  ),
                )
              else
                for (final gap in gaps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _GapCard(controller: controller, gap: gap),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _GapCard extends StatelessWidget {
  final DashboardController controller;
  final BalanceGap gap;

  const _GapCard({required this.controller, required this.gap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fin = FinanceColors.of(context);
    final missing = gap.missingAmountRial;
    final withdrawal = missing < 0;
    final prev = controller.cachedById(gap.previousTxId);
    final curr = controller.cachedById(gap.currentTxId);
    final canAdd = curr == null || controller.canEdit(curr);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(withdrawal ? Icons.north_east_rounded : Icons.south_west_rounded,
                    color: withdrawal ? fin.expense : fin.income),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${withdrawal ? 'احتمالاً برداشتی ثبت نشده' : 'احتمالاً واریزی ثبت نشده'}: '
                    '${formatToman(missing.abs())}',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (curr != null) ...[
              const SizedBox(height: 4),
              Text('${personOf(curr)} • ${cardTitleOf(curr)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Text(
              'بین ${formatShortDateTime(gap.previousAt)}'
              '${prev?.balanceAfterRial != null ? ' (مانده ${formatToman(prev!.balanceAfterRial!)})' : ''}'
              ' و ${formatShortDateTime(gap.currentAt)}'
              ' (مانده ${formatToman(gap.actualBalanceRial)}).',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              'انتظار داشتیم مانده ${formatToman(gap.expectedBalanceRial)} باشد.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            // Wrap تا روی گوشی‌های باریک دکمه‌ها زیر هم بیایند، نه بیرون از صفحه.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (canAdd)
                  FilledButton.tonalIcon(
                    key: Key('gap-add-${gap.key}'),
                    onPressed: () => controller.addMissingFromGap(gap),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('ثبت دستی همین مبلغ'),
                  ),
                TextButton(
                  key: Key('gap-dismiss-${gap.key}'),
                  onPressed: () => controller.dismissGap(gap),
                  child: const Text('نادیده بگیر'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
