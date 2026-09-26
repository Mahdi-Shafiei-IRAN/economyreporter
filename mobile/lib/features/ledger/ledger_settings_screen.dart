/// تنظیماتِ حالتِ نسخه‌ی ۲ (طرح ۱۲.۵): فقط چیزهایی که در نسخه‌ی ۲ معنا دارند. ابزارهای نسخه‌ی ۱
/// اینجا نیستند؛ با خاموش کردنِ کلید برمی‌گردند.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/theme/theme_controller.dart';
import 'banks_view.dart';
import 'guide_screen.dart';
import 'ledger_controller.dart';
import 'ledger_v2_toggle.dart';

const kLedgerSettingsGuideKey = Key('ledger-settings-guide');
const kLedgerSettingsBanksKey = Key('ledger-settings-banks');
const kLedgerSettingsFamilyKey = Key('ledger-settings-family');
const kLedgerSettingsUpdateKey = Key('ledger-settings-update');
const kLedgerSettingsLogoutKey = Key('ledger-settings-logout');
const kLedgerSettingsSyncKey = Key('ledger-settings-sync');

class LedgerSettingsScreen extends StatefulWidget {
  final LedgerController controller;
  final Future<String> Function()? onCheckUpdate;
  final VoidCallback? onLogout;

  /// «افزودن عضو خانواده» (فقط مدیر).
  final VoidCallback? onAddMember;

  /// «همگام‌سازی الان»؛ پیامِ نتیجه را برمی‌گرداند.
  final Future<String> Function()? onSync;

  const LedgerSettingsScreen({
    super.key,
    required this.controller,
    this.onCheckUpdate,
    this.onLogout,
    this.onAddMember,
    this.onSync,
  });

  @override
  State<LedgerSettingsScreen> createState() => _LedgerSettingsScreenState();
}

class _LedgerSettingsScreenState extends State<LedgerSettingsScreen> {
  bool _checking = false;
  bool _syncing = false;

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final message = await widget.onSync!();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }
  LedgerController get _c => widget.controller;

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    try {
      final message = await widget.onCheckUpdate!();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: AnimatedBuilder(
        animation: Listenable.merge([_c, themeController]),
        builder: (context, _) {
          final people = _c.people?.call();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              LedgerV2Toggle(controller: _c),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  ListTile(
                    key: kLedgerSettingsGuideKey,
                    leading: const Icon(Icons.help_outline_rounded),
                    title: const Text('راهنما'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => _push(const LedgerGuideScreen()),
                  ),
                  const Divider(indent: 56),
                  ListTile(
                    key: kLedgerSettingsBanksKey,
                    leading: const Icon(Icons.account_balance_outlined),
                    title: const Text('بانک‌ها'),
                    subtitle: Text(_c.banks.isEmpty
                        ? 'هنوز بانکی انتخاب نشده'
                        : '${toPersianDigits('${_c.banks.length}')} فرستنده‌ی پیامکِ بانک'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => _push(LedgerBanksScreen(controller: _c)),
                  ),
                ]),
              ),
              if (widget.onSync != null)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    key: kLedgerSettingsSyncKey,
                    leading: Icon(_c.lastSyncError == null
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_rounded),
                    title: Text(_c.lastSyncAt == null
                        ? 'پشتیبان روی سرور: هنوز نه'
                        : 'پشتیبان روی سرور: ${formatJalaliDateTime(_c.lastSyncAt!)}'),
                    subtitle: Text([
                      if (_c.lastSyncError != null) _c.lastSyncError!,
                      _c.unsyncedCount == 0
                          ? 'همه‌چیز روی سرور هست؛ با نصبِ دوباره برمی‌گردد'
                          : '${toPersianDigits('${_c.unsyncedCount}')} تغییر منتظرِ ارسال',
                    ].join('\n')),
                    trailing: _syncing
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync_rounded),
                    onTap: _syncing ? null : _syncNow,
                  ),
                ),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  ListTile(
                    key: kLedgerSettingsFamilyKey,
                    leading: const Icon(Icons.groups_outlined),
                    title: Text(people?.meName ?? 'خانواده'),
                    subtitle: Text((people?.members ?? const []).isEmpty
                        ? 'اعضای خانواده هنوز از سرور گرفته نشده'
                        : 'اعضا: ${people!.members.map((m) => m.name).join('، ')}'),
                  ),
                  if (widget.onAddMember != null) ...[
                    const Divider(indent: 56),
                    ListTile(
                      leading: const Icon(Icons.person_add_alt_1_rounded),
                      title: const Text('افزودن عضو خانواده'),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: widget.onAddMember,
                    ),
                  ],
                ]),
              ),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  if (widget.onCheckUpdate != null) ...[
                    ListTile(
                      key: kLedgerSettingsUpdateKey,
                      leading: const Icon(Icons.system_update_rounded),
                      title: const Text('بررسیِ نسخه‌ی جدید'),
                      trailing: _checking
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.chevron_left_rounded),
                      onTap: _checking ? null : _checkUpdate,
                    ),
                    const Divider(indent: 56),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(16),
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
                ]),
              ),
              if (widget.onLogout != null)
                Card(
                  child: ListTile(
                    key: kLedgerSettingsLogoutKey,
                    leading: Icon(Icons.logout_rounded, color: scheme.error),
                    title: Text('خروج از حساب', style: TextStyle(color: scheme.error)),
                    onTap: widget.onLogout,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
