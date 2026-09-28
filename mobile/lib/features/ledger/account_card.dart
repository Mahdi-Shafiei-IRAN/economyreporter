/// کارتِ یک حساب: موجودی (از آخرین نقطه)، «موجودیِ الان؟» اگر ندارد، و منوی تطبیق/کنار گذاشتن.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/ledger/models.dart';
import 'account_form.dart';
import 'ledger_controller.dart';
import 'ledger_text.dart';

Key ledgerAccountCardKey(String id) => Key('ledger-account-$id');
Key ledgerSetBalanceKey(String id) => Key('ledger-set-balance-$id');
Key ledgerAccountMenuKey(String id) => Key('ledger-account-menu-$id');
const kDeleteAccountConfirmKey = Key('delete-account-confirm');

/// «حذفِ کارت» با پرسش: کارت، تراکنش‌ها و موجودی‌هایش با هم می‌روند (طرح ۱۲.۱۰). true = حذف شد.
Future<bool> confirmDeleteAccount(BuildContext context, LedgerController controller, LedgerAccount a) async {
  final n = controller.entryCountOf(a.id);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('حذفِ «${accountShortLabel(a)}»؟'),
      content: Text([
        n == 0
            ? 'کارت و موجودی‌هایش حذف می‌شود.'
            : 'کارت با ${toPersianDigits('$n')} تراکنش و موجودی‌هایش حذف می‌شود؛ از جمع‌ها و گزارش‌ها هم بیرون می‌رود.',
        'پیامک‌هایی که به این تراکنش‌ها ثبت شده بودند «رد» می‌شوند.',
        'اگر فقط نمی‌خواهی دیده شود و تراکنش‌ها بمانند، «پیگیری نشود» را بزن.',
      ].join('\n\n')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
        FilledButton(
          key: kDeleteAccountConfirmKey,
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('حذف'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await controller.deleteAccount(a.id);
  return true;
}

class LedgerAccountCard extends StatelessWidget {
  final LedgerController controller;
  final AccountView view;

  /// لمسِ کارت (در خانه: جزئیاتِ حساب).
  final VoidCallback? onTap;

  /// حسابِ عضوِ دیگرِ خانواده: بی‌منو و بی‌«موجودیِ الان».
  final bool readOnly;

  const LedgerAccountCard(
      {super.key, required this.controller, required this.view, this.onTap, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = view.account;
    final balance = view.balance;
    return Card(
      key: ledgerAccountCardKey(a.id),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
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
                        Text(accountTitle(a),
                            style: theme.textTheme.titleMedium),
                        Text(accountSubtitle(a),
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  if (!readOnly) PopupMenuButton<String>(
                    key: ledgerAccountMenuKey(a.id),
                    tooltip: 'بیشتر',
                    onSelected: (v) => switch (v) {
                      'reconcile' => showBalanceDialog(
                          context, controller, view,
                          reconcile: true),
                      'archive' => controller.setArchived(a.id, !a.archived),
                      'delete' => confirmDeleteAccount(context, controller, a),
                      _ => null,
                    },
                    itemBuilder: (_) => [
                      if (!a.archived)
                        const PopupMenuItem(
                            value: 'reconcile',
                            child: Text('موجودیِ واقعی را وارد کن')),
                      PopupMenuItem(
                          value: 'archive',
                          child: Text(a.archived
                              ? 'دوباره پیگیری شود'
                              : 'پیگیری نشود (کنار بگذار)')),
                      PopupMenuItem(
                          value: 'delete',
                          child: Text('حذفِ کارت و تراکنش‌هایش',
                              style: TextStyle(color: Theme.of(context).colorScheme.error))),
                    ],
                  ),
                ],
              ),
              if (balance != null) ...[
                const SizedBox(height: 6),
                Text(formatToman(balance.balanceRial),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text('از ${formatShortDateTime(balance.anchor.at)}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
              if (view.unconfirmedBalance != null)
                Text(
                    'طبقِ پیامکی که هنوز تأیید نکرده‌ای: ${formatToman(view.unconfirmedBalance!)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.tertiary)),
              if (view.discrepancyCount > 0 && !readOnly)
                Text('با مانده‌ی بانک نمی‌خواند — برای دیدن و درست کردن لمس کن',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              if (readOnly && balance == null)
                Text('هنوز داده‌ای از گوشیِ ${a.ownerName} نیامده',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (view.needsAnchor && !a.archived && !readOnly)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.tonalIcon(
                      key: ledgerSetBalanceKey(a.id),
                      onPressed: () =>
                          showBalanceDialog(context, controller, view),
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
      ),
    );
  }
}
