/// تنظیمات (طرح ۱۲.۹): فقط ۴ ردیف + خروج — «بانک‌ها و کارت‌ها»، «خانواده»، «ظاهر» و «بیشتر» (راهنما، پشتیبان روی
/// سرور، نسخه‌ی جدید). جزئیاتِ هر کدام در صفحه‌ی خودش.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/theme/theme_controller.dart';
import 'account_card.dart';
import 'account_details_screen.dart';
import 'account_form.dart';
import 'accounts_view.dart';
import 'banks_view.dart';
import 'guide_screen.dart';
import 'ledger_controller.dart';

const kLedgerSettingsBanksKey = Key('ledger-settings-banks');
const kLedgerSettingsFamilyKey = Key('ledger-settings-family');
const kLedgerSettingsMoreKey = Key('ledger-settings-more');
const kLedgerSettingsLogoutKey = Key('ledger-settings-logout');
const kLedgerSettingsGuideKey = Key('ledger-settings-guide');
const kLedgerSettingsUpdateKey = Key('ledger-settings-update');
const kLedgerSettingsSyncKey = Key('ledger-settings-sync');
const kLedgerSettingsHealthKey = Key('ledger-settings-health');
const kLedgerSettingsAddMemberKey = Key('ledger-settings-add-member');
const kCardsSettingsSendersKey = Key('cards-settings-senders');
const kCardsSettingsCandidatesKey = Key('cards-settings-candidates');
const kLedgerNewAccountKey = Key('ledger-new-account');

String _fa(int n) => toPersianDigits('$n');

class LedgerSettingsScreen extends StatelessWidget {
  final LedgerController controller;
  final Future<String> Function()? onCheckUpdate;
  final VoidCallback? onLogout;

  /// «افزودن عضو خانواده» (فقط مدیر).
  final VoidCallback? onAddMember;

  /// «همگام‌سازی الان»؛ پیامِ نتیجه را برمی‌گرداند.
  final Future<String> Function()? onSync;

  /// «سلامتِ برنامه روی گوشی‌ها».
  final VoidCallback? onOpenDevicesHealth;

  const LedgerSettingsScreen({
    super.key,
    required this.controller,
    this.onCheckUpdate,
    this.onLogout,
    this.onAddMember,
    this.onSync,
    this.onOpenDevicesHealth,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: AnimatedBuilder(
        animation: Listenable.merge([controller, themeController]),
        builder: (context, _) {
          final c = controller;
          final people = c.who;
          final cards = c.activeAccounts.length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  ListTile(
                    key: kLedgerSettingsBanksKey,
                    leading: const Icon(Icons.account_balance_outlined),
                    title: const Text('بانک‌ها و کارت‌ها'),
                    subtitle: Text('${_fa(c.banks.length)} بانک • ${_fa(cards)} کارت/حساب'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => push(LedgerCardsSettingsScreen(controller: c)),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    key: kLedgerSettingsFamilyKey,
                    leading: const Icon(Icons.groups_outlined),
                    title: const Text('خانواده'),
                    subtitle: Text(
                      people.members.isEmpty
                          ? (people.meName ?? 'اعضا هنوز از سرور نیامده')
                          : people.members.map((m) => m.name).join('، '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => push(LedgerFamilySettingsScreen(
                      controller: c,
                      onAddMember: onAddMember,
                      onOpenDevicesHealth: onOpenDevicesHealth,
                    )),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('ظاهر'),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, label: Text('خودکار')),
                          ButtonSegment(value: ThemeMode.light, label: Text('روشن')),
                          ButtonSegment(value: ThemeMode.dark, label: Text('تیره')),
                        ],
                        selected: {themeController.mode},
                        onSelectionChanged: (s) => themeController.setMode(s.first),
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    key: kLedgerSettingsMoreKey,
                    leading: const Icon(Icons.more_horiz_rounded),
                    title: const Text('بیشتر'),
                    subtitle: const Text('راهنما، پشتیبان روی سرور، نسخه‌ی جدید'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => push(LedgerMoreSettingsScreen(
                      controller: c,
                      onSync: onSync,
                      onCheckUpdate: onCheckUpdate,
                    )),
                  ),
                ]),
              ),
              if (onLogout != null)
                Card(
                  child: ListTile(
                    key: kLedgerSettingsLogoutKey,
                    leading: Icon(Icons.logout_rounded, color: scheme.error),
                    title: Text('خروج از حساب', style: TextStyle(color: scheme.error)),
                    onTap: onLogout,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// «بانک‌ها و کارت‌ها»: فرستنده‌های پیامکِ بانک، حساب‌های پیداشده، کارت‌هایم با موجودی و منوی تطبیق/کنار
/// گذاشتن، پیگیری‌نشده‌ها و «حسابِ بی‌پیامک».
class LedgerCardsSettingsScreen extends StatelessWidget {
  final LedgerController controller;

  const LedgerCardsSettingsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(title: const Text('بانک‌ها و کارت‌ها')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final c = controller;
          final theme = Theme.of(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  ListTile(
                    key: kCardsSettingsSendersKey,
                    leading: const Icon(Icons.sms_outlined),
                    title: const Text('فرستنده‌های پیامکِ بانک'),
                    subtitle: Text(c.banks.isEmpty
                        ? 'هنوز بانکی انتخاب نشده'
                        : '${_fa(c.banks.length)} فرستنده'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => push(LedgerBanksScreen(controller: c)),
                  ),
                  if (c.accountCandidates.isNotEmpty) ...[
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      key: kCardsSettingsCandidatesKey,
                      leading: const Icon(Icons.credit_card_rounded),
                      title: Text('${_fa(c.accountCandidates.length)} حساب در پیامک‌ها پیدا شد'),
                      subtitle: const Text('بگو مالِ توست یا نه'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => push(LedgerAccountsScreen(controller: c)),
                    ),
                  ],
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                child: Text('کارت‌ها و حساب‌هایم', style: theme.textTheme.titleMedium),
              ),
              for (final v in c.activeAccounts)
                LedgerAccountCard(
                  controller: c,
                  view: v,
                  onTap: () => push(AccountDetailsScreen(controller: c, accountId: v.account.id)),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: kLedgerNewAccountKey,
                  onPressed: () => showAccountForm(context, c),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('حسابِ بی‌پیامک (مثلاً نقد)'),
                ),
              ),
              if (c.archivedAccounts.isNotEmpty)
                ExpansionTile(
                  title: Text('پیگیری‌نشده‌ها (${_fa(c.archivedAccounts.length)})'),
                  children: [
                    for (final v in c.archivedAccounts) LedgerAccountCard(controller: c, view: v),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// «خانواده»: من و اعضا، افزودنِ عضو (مدیر) و سلامتِ برنامه روی گوشی‌ها.
class LedgerFamilySettingsScreen extends StatelessWidget {
  final LedgerController controller;
  final VoidCallback? onAddMember;
  final VoidCallback? onOpenDevicesHealth;

  const LedgerFamilySettingsScreen({
    super.key,
    required this.controller,
    this.onAddMember,
    this.onOpenDevicesHealth,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('خانواده')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final people = controller.who;
          final theme = Theme.of(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  if (people.members.isEmpty)
                    ListTile(
                      leading: const Icon(Icons.person_outline_rounded),
                      title: Text(people.meName ?? 'من'),
                      subtitle: const Text('اعضای خانواده هنوز از سرور گرفته نشده'),
                    ),
                  for (final m in people.members)
                    ListTile(
                      leading: CircleAvatar(child: Text(m.name.isEmpty ? '؟' : m.name.substring(0, 1))),
                      title: Text(m.id == people.meUserId ? '${m.name} (من)' : m.name),
                    ),
                ]),
              ),
              if (controller.isManager)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text('تو مدیرِ خانواده‌ای: حساب‌ها و تراکنش‌های همه را در صفحه‌ی اصلی می‌بینی.',
                      style: theme.textTheme.bodySmall),
                ),
              if (onAddMember != null || onOpenDevicesHealth != null)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    if (onAddMember != null)
                      ListTile(
                        key: kLedgerSettingsAddMemberKey,
                        leading: const Icon(Icons.person_add_alt_1_rounded),
                        title: const Text('افزودن عضو خانواده'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: onAddMember,
                      ),
                    if (onAddMember != null && onOpenDevicesHealth != null) const Divider(height: 1, indent: 56),
                    if (onOpenDevicesHealth != null)
                      ListTile(
                        key: kLedgerSettingsHealthKey,
                        leading: const Icon(Icons.health_and_safety_outlined),
                        title: const Text('سلامتِ برنامه روی گوشی‌ها'),
                        subtitle: const Text('برنامه روی گوشیِ بقیه درست کار می‌کند؟'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: onOpenDevicesHealth,
                      ),
                  ]),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// «بیشتر»: راهنما، پشتیبان روی سرور و نسخه‌ی جدید.
class LedgerMoreSettingsScreen extends StatefulWidget {
  final LedgerController controller;
  final Future<String> Function()? onSync;
  final Future<String> Function()? onCheckUpdate;

  const LedgerMoreSettingsScreen({super.key, required this.controller, this.onSync, this.onCheckUpdate});

  @override
  State<LedgerMoreSettingsScreen> createState() => _LedgerMoreSettingsScreenState();
}

class _LedgerMoreSettingsScreenState extends State<LedgerMoreSettingsScreen> {
  bool _syncing = false;
  bool _checking = false;

  LedgerController get _c => widget.controller;

  Future<void> _run(Future<String> Function() action, void Function(bool) busy) async {
    setState(() => busy(true));
    try {
      final message = await action();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => busy(false));
    }
  }

  static const _spinner =
      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بیشتر')),
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                ListTile(
                  key: kLedgerSettingsGuideKey,
                  leading: const Icon(Icons.help_outline_rounded),
                  title: const Text('راهنما'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const LedgerGuideScreen())),
                ),
                if (widget.onSync != null) ...[
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    key: kLedgerSettingsSyncKey,
                    leading: Icon(_c.lastSyncError == null ? Icons.cloud_done_outlined : Icons.cloud_off_rounded),
                    title: Text(_c.lastSyncAt == null
                        ? 'پشتیبان روی سرور: هنوز نه'
                        : 'پشتیبان روی سرور: ${formatJalaliDateTime(_c.lastSyncAt!)}'),
                    subtitle: Text([
                      if (_c.lastSyncError != null) _c.lastSyncError!,
                      _c.unsyncedCount == 0
                          ? 'همه‌چیز روی سرور هست؛ با نصبِ دوباره برمی‌گردد'
                          : '${_fa(_c.unsyncedCount)} تغییر منتظرِ ارسال',
                    ].join('\n')),
                    trailing: _syncing ? _spinner : const Icon(Icons.sync_rounded),
                    onTap: _syncing ? null : () => _run(widget.onSync!, (b) => _syncing = b),
                  ),
                ],
                if (widget.onCheckUpdate != null) ...[
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    key: kLedgerSettingsUpdateKey,
                    leading: const Icon(Icons.system_update_rounded),
                    title: const Text('بررسیِ نسخه‌ی جدید'),
                    trailing: _checking ? _spinner : const Icon(Icons.chevron_right_rounded),
                    onTap: _checking ? null : () => _run(widget.onCheckUpdate!, (b) => _checking = b),
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
