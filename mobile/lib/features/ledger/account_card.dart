/// کارتِ یک حساب: موجودی (از آخرین نقطه)، «موجودیِ الان؟» اگر ندارد، و منوی تطبیق/کنار گذاشتن.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import 'account_form.dart';
import 'ledger_controller.dart';
import 'ledger_text.dart';

Key ledgerAccountCardKey(String id) => Key('ledger-account-$id');
Key ledgerSetBalanceKey(String id) => Key('ledger-set-balance-$id');

class LedgerAccountCard extends StatelessWidget {
  final LedgerController controller;
  final AccountView view;

  const LedgerAccountCard({super.key, required this.controller, required this.view});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = view.account;
    final balance = view.balance;
    return Card(
      key: ledgerAccountCardKey(a.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(accountTitle(a), style: theme.textTheme.titleMedium),
                      Text(accountSubtitle(a), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'بیشتر',
                  onSelected: (v) => switch (v) {
                    'reconcile' => showBalanceDialog(context, controller, view, reconcile: true),
                    'archive' => controller.setArchived(a.id, !a.archived),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    if (!a.archived)
                      const PopupMenuItem(value: 'reconcile', child: Text('موجودیِ واقعی را وارد کن')),
                    PopupMenuItem(
                        value: 'archive',
                        child: Text(a.archived ? 'دوباره پیگیری شود' : 'پیگیری نشود (کنار بگذار)')),
                  ],
                ),
              ],
            ),
            if (balance != null) ...[
              const SizedBox(height: 6),
              Text(formatToman(balance.balanceRial),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text('از ${formatShortDateTime(balance.anchor.at)}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (view.unconfirmedBalance != null)
              Text('طبقِ پیامکی که هنوز تأیید نکرده‌ای: ${formatToman(view.unconfirmedBalance!)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary)),
            if (view.discrepancyCount > 0)
              Text('با مانده‌ی بانک نمی‌خواند؛ شاید پیامکی هنوز تأیید نشده',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            if (view.needsAnchor && !a.archived)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    key: ledgerSetBalanceKey(a.id),
                    onPressed: () => showBalanceDialog(context, controller, view),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: Text(view.lastBankBalance == null
                        ? 'موجودیِ الانش را وارد کن'
                        : 'موجودیِ الان ${formatToman(view.lastBankBalance!)} است؟'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
