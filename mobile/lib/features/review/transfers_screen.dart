/// انتقال‌های احتمالی: از یک کارت برداشت و «تقریباً هم‌زمان» همان مبلغ به کارتِ
/// دیگری واریز شده. کاربر تأیید می‌کند تا هر دو «انتقال» شوند و از خالص بیرون بروند.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/transfer/transfer_finder.dart';
import '../dashboard/dashboard_controller.dart';
import '../transactions/data/transaction_record.dart';
import '../transactions/data/tx_query.dart';

const kTransfersEmptyKey = Key('transfers-empty');

class TransfersScreen extends StatelessWidget {
  final DashboardController controller;

  const TransfersScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('انتقال بین کارت‌ها')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final pairs = controller.transferPairs;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _Explain(),
              const SizedBox(height: 12),
              if (pairs.isEmpty)
                const Padding(
                  key: kTransfersEmptyKey,
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Column(children: [
                    Icon(Icons.swap_horiz_rounded, size: 48),
                    SizedBox(height: 8),
                    Text('انتقالِ مشکوکی پیدا نشد.'),
                  ]),
                )
              else
                for (final p in pairs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PairCard(
                      key: ValueKey('transfer-${p.key}'),
                      controller: controller,
                      pair: p,
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
    return Card(
      color: theme.colorScheme.secondaryContainer.withOpacity(0.6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'این‌ها یک برداشت و یک واریزِ هم‌مبلغ‌اند که نزدیک به هم و بینِ دو کارتِ '
          'خانواده رخ داده‌اند؛ احتمالاً جابه‌جاییِ پول بوده، نه درآمد/خرجِ واقعی. '
          'اگر تأیید کنی، هر دو «انتقال» می‌شوند و در خالص حساب نمی‌شوند.',
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _PairCard extends StatelessWidget {
  final DashboardController controller;
  final TransferPair pair;

  const _PairCard(
      {super.key, required this.controller, required this.pair});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('مبلغ ${formatToman(pair.amountRial)}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _Line(record: pair.out, isOut: true),
            const Divider(),
            _Line(record: pair.inn, isOut: false),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: ValueKey('transfer-confirm-${pair.key}'),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('انتقال است'),
                    onPressed: () => controller.confirmTransfer(pair),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: ValueKey('transfer-dismiss-${pair.key}'),
                  onPressed: () => controller.dismissTransfer(pair),
                  child: const Text('نیست'),
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
  final TransactionRecord record;
  final bool isOut;

  const _Line({required this.record, required this.isOut});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(isOut ? Icons.north_east_rounded : Icons.south_west_rounded,
            size: 18, color: isOut ? scheme.error : scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${isOut ? 'برداشت از' : 'واریز به'} ${cardTitleOf(record)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              Text('${personOf(record)} • ${formatJalaliDateTime(record.effectiveTime)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
