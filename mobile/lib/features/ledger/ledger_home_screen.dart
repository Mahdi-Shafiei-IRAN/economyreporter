/// خانه‌ی نسخه‌ی ۲ (طرح ۷.۱): کارتِ هر حساب با موجودی، جمعِ خانواده، درآمد/هزینه‌ی ماه و
/// بنرِ «N پیامکِ منتظرِ تأیید».
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/sms/jalali.dart';
import 'account_form.dart';
import 'entry_sheet.dart';
import 'ledger_controller.dart';
import 'ledger_text.dart';
import 'pending_screen.dart';

const kLedgerPendingBannerKey = Key('ledger-pending-banner');
const kLedgerAddFabKey = Key('ledger-add-fab');
const kLedgerNewAccountKey = Key('ledger-new-account');
const kLedgerSettingsKey = Key('ledger-settings');
Key ledgerAccountCardKey(String id) => Key('ledger-account-$id');
Key ledgerSetBalanceKey(String id) => Key('ledger-set-balance-$id');

String _fa(int n) => toPersianDigits('$n');

class LedgerHomeScreen extends StatelessWidget {
  final LedgerController controller;
  final VoidCallback? onOpenSettings;

  const LedgerHomeScreen({super.key, required this.controller, this.onOpenSettings});

  void _openPending(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => PendingScreen(controller: controller)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('مالی خانواده'),
        actions: [
          if (onOpenSettings != null)
            IconButton(
              key: kLedgerSettingsKey,
              tooltip: 'تنظیمات',
              icon: const Icon(Icons.settings_outlined),
              onPressed: onOpenSettings,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: kLedgerAddFabKey,
        onPressed: () => showEntrySheet(context, controller),
        icon: const Icon(Icons.add_rounded),
        label: const Text('افزودنِ تراکنش'),
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final c = controller;
          final month = jalaliMonthName(JalaliDate.fromDateTime(c.now).month);
          final needAnchor = [for (final a in c.activeAccounts) if (a.needsAnchor) a];
          return RefreshIndicator(
            onRefresh: c.syncInbox,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (c.pendingCount > 0)
                  Card(
                    key: kLedgerPendingBannerKey,
                    color: theme.colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.mark_email_unread_outlined),
                      title: Text('${_fa(c.pendingCount)} پیامکِ منتظرِ تأیید'),
                      subtitle: const Text('هیچ پیامکی خودش ثبت نمی‌شود؛ ثبت یا ردشان کن'),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => _openPending(context),
                    ),
                  )
                else
                  ListTile(
                    leading: const Icon(Icons.done_all_rounded),
                    title: const Text('پیامکِ منتظری نیست'),
                    onTap: () => _openPending(context),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('جمعِ موجودی‌ها', style: theme.textTheme.labelLarge),
                        Text(
                          c.totalBalance == null ? '—' : formatToman(c.totalBalance!),
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$month: درآمد ${formatToman(c.monthIncome)} • هزینه ${formatToman(c.monthExpense)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
                if (needAnchor.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                    child: Text(
                      'برای ${_fa(needAnchor.length)} حساب «موجودیِ الان» را وارد کن؛ '
                      'همه‌ی جمع و تفریق‌ها از همین عدد شروع می‌شود.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                  child: Text('حساب‌ها', style: theme.textTheme.titleMedium),
                ),
                for (final v in c.activeAccounts) _AccountCard(controller: c, view: v),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: kLedgerNewAccountKey,
                  onPressed: () => showAccountForm(context, c),
                  icon: const Icon(Icons.add_card_rounded),
                  label: const Text('حسابِ تازه'),
                ),
                if (c.archivedAccounts.isNotEmpty)
                  ExpansionTile(
                    title: Text('کنارگذاشته‌ها (${_fa(c.archivedAccounts.length)})'),
                    children: [
                      for (final v in c.archivedAccounts) _AccountCard(controller: c, view: v),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final LedgerController controller;
  final AccountView view;

  const _AccountCard({required this.controller, required this.view});

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
                  onSelected: (v) => switch (v) {
                    'reconcile' => showBalanceDialog(context, controller, view, reconcile: true),
                    'archive' => controller.setArchived(a.id, !a.archived),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'reconcile', child: Text('تطبیق با موجودیِ واقعی')),
                    PopupMenuItem(
                        value: 'archive',
                        child: Text(a.archived ? 'برگرداندن از کنارگذاشته‌ها' : 'کنار گذاشتن (پیگیری نشود)')),
                  ],
                ),
              ],
            ),
            if (balance != null) ...[
              const SizedBox(height: 6),
              Text(formatToman(balance.balanceRial),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text('از آخرین مانده‌ی ${formatShortDateTime(balance.anchor.at)}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            if (view.unconfirmedBalance != null)
              Text('طبقِ آخرین پیامکِ بانک: ${formatToman(view.unconfirmedBalance!)} (هنوز تأیید نشده)',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary)),
            if (view.discrepancyCount > 0)
              Text('${_fa(view.discrepancyCount)} جا با مانده‌ی بانک نمی‌خواند',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            if (view.needsAnchor && !a.archived)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.tonalIcon(
                  key: ledgerSetBalanceKey(a.id),
                  onPressed: () => showBalanceDialog(context, controller, view),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: Text(view.lastBankBalance == null
                      ? 'موجودیِ الان را وارد کن'
                      : 'موجودیِ الان: ${formatToman(view.lastBankBalance!)}؟'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
