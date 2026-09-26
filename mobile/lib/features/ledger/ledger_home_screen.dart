/// خانه‌ی نسخه‌ی ۲ (طرح ۷.۱ و ۱۲.۵): یک کارتِ «قدمِ بعدی»، جمعِ موجودی و ماه، و حساب‌ها.
/// اولین بار راهنمای سه‌قدمی باز می‌شود.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/sms/jalali.dart';
import 'account_card.dart';
import 'account_details_screen.dart';
import 'month_report_screen.dart';
import 'account_form.dart';
import 'accounts_view.dart';
import 'banks_view.dart';
import 'entry_sheet.dart';
import 'ledger_controller.dart';
import 'pending_screen.dart';
import 'setup_screen.dart';

const kLedgerNextStepKey = Key('ledger-next-step');
const kLedgerMonthCardKey = Key('ledger-month-card');
const kLedgerAddFabKey = Key('ledger-add-fab');
const kLedgerNewAccountKey = Key('ledger-new-account');
const kLedgerSettingsKey = Key('ledger-settings');

String _fa(int n) => toPersianDigits('$n');

class LedgerHomeScreen extends StatefulWidget {
  final LedgerController controller;
  final VoidCallback? onOpenSettings;

  /// راهنمای سه‌قدمی را اولین بار خودکار باز کند (در تست‌های صفحه خاموش).
  final bool autoSetup;

  const LedgerHomeScreen({
    super.key,
    required this.controller,
    this.onOpenSettings,
    this.autoSetup = true,
  });

  @override
  State<LedgerHomeScreen> createState() => _LedgerHomeScreenState();
}

class _LedgerHomeScreenState extends State<LedgerHomeScreen> {
  LedgerController get _c => widget.controller;
  bool _setupShown = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_maybeSetup);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSetup());
  }

  @override
  void dispose() {
    _c.removeListener(_maybeSetup);
    super.dispose();
  }

  void _maybeSetup() {
    if (!widget.autoSetup || _setupShown || !mounted || !_c.enabled || _c.setupDone) return;
    _setupShown = true;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LedgerSetupScreen(controller: _c)));
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('مالی خانواده'),
        actions: [
          if (widget.onOpenSettings != null)
            IconButton(
              key: kLedgerSettingsKey,
              tooltip: 'تنظیمات',
              icon: const Icon(Icons.settings_outlined),
              onPressed: widget.onOpenSettings,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: kLedgerAddFabKey,
        onPressed: () => showEntrySheet(context, _c),
        icon: const Icon(Icons.add_rounded),
        label: const Text('تراکنشِ دستی'),
      ),
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final month = jalaliMonthName(JalaliDate.fromDateTime(_c.now).month);
          return RefreshIndicator(
            onRefresh: _c.syncInbox,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                _NextStepCard(controller: _c, onOpen: _push),
                Card(
                  key: kLedgerMonthCardKey,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _push(MonthReportScreen(controller: _c)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('جمعِ موجودی‌ها', style: theme.textTheme.labelLarge),
                          Text(
                            _c.totalBalance == null ? '—' : formatToman(_c.totalBalance!),
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                              child: Text(
                                '$month: درآمد ${formatToman(_c.monthIncome)} • هزینه ${formatToman(_c.monthExpense)}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            Text('گزارش', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                            Icon(Icons.chevron_left_rounded, color: theme.colorScheme.primary),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                  child: Text('حساب‌هایم', style: theme.textTheme.titleMedium),
                ),
                for (final v in _c.activeAccounts)
                  LedgerAccountCard(
                    controller: _c,
                    view: v,
                    onTap: () => _push(AccountDetailsScreen(controller: _c, accountId: v.account.id)),
                  ),
                if (_c.activeAccounts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('هنوز حسابی نیست؛ کارتِ بالا راهنمایی می‌کند.',
                        style: theme.textTheme.bodySmall),
                  ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: kLedgerNewAccountKey,
                    onPressed: () => showAccountForm(context, _c),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('حسابِ بی‌پیامک (مثلاً نقد)'),
                  ),
                ),
                if (_c.archivedAccounts.isNotEmpty)
                  ExpansionTile(
                    title: Text('پیگیری‌نشده‌ها (${_fa(_c.archivedAccounts.length)})'),
                    children: [
                      for (final v in _c.archivedAccounts) LedgerAccountCard(controller: _c, view: v),
                    ],
                  ),
                if (_c.othersAccountCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                    child: Text(
                      'حساب‌های بقیه‌ی خانواده (${_fa(_c.othersAccountCount)}) روی گوشیِ خودشان است؛ '
                      'دیدنِ آن‌ها در قدمِ بعد اضافه می‌شود.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// همیشه فقط یک کار: بانک‌ها ← حساب‌های پیداشده ← موجودیِ الان ← پیامک‌های منتظر ← مرتب.
class _NextStepCard extends StatelessWidget {
  final LedgerController controller;
  final void Function(Widget page) onOpen;

  const _NextStepCard({required this.controller, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = controller;
    final needAnchor = c.activeAccounts.where((a) => a.needsAnchor).length;
    final (IconData icon, String title, String subtitle, Widget? page) = switch (c.nextStep) {
      NextStep.chooseBanks => (
          Icons.account_balance_outlined,
          'قدمِ بعدی: بانک‌هایت را انتخاب کن',
          'از روی پیامک‌ها بگو کدام فرستنده بانک است',
          LedgerBanksScreen(controller: c),
        ),
      NextStep.confirmAccounts => (
          Icons.credit_card_rounded,
          'قدمِ بعدی: ${_fa(c.accountCandidates.length)} حساب در پیامک‌ها پیدا شد',
          'بگو مالِ توست یا نه',
          LedgerAccountsScreen(controller: c),
        ),
      NextStep.setBalances => (
          Icons.account_balance_wallet_outlined,
          'قدمِ بعدی: موجودیِ الانِ ${_fa(needAnchor)} حساب',
          'پیش‌فرض همان آخرین مانده‌ی بانک است',
          LedgerAccountsScreen(controller: c),
        ),
      NextStep.reviewPending => (
          Icons.mark_email_unread_outlined,
          'قدمِ بعدی: ${_fa(c.pendingCount)} پیامکِ منتظرِ تأیید',
          'ثبت کن یا بگو تراکنش نیست',
          PendingScreen(controller: c),
        ),
      NextStep.allGood => (
          Icons.check_circle_outline_rounded,
          'همه‌چیز مرتب است',
          'پیامکِ تازه که بیاید، اینجا و در نوتیفیکیشن خبر می‌دهیم',
          null,
        ),
    };
    final done = page == null;
    return Card(
      key: kLedgerNextStepKey,
      color: done ? scheme.surfaceContainerHighest : scheme.primaryContainer,
      child: ListTile(
        leading: Icon(icon, color: done ? scheme.primary : scheme.onPrimaryContainer),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: done ? null : const Icon(Icons.chevron_left_rounded),
        onTap: done ? null : () => onOpen(page),
      ),
    );
  }
}
