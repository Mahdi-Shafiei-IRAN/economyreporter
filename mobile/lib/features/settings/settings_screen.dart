/// تنظیمات و ابزارها: کارت‌ها، موارد نیازمند توجه (با توضیح)، شروع دسته‌بندی،
/// وضعیت همگام‌سازی با سرور، تم و خروج.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/theme/theme_controller.dart';
import '../categories/categorize_list_screen.dart';
import '../dashboard/dashboard_controller.dart';
import '../family/add_member_screen.dart';
import '../review/reconciliation_screen.dart';
import '../review/review_screen.dart';
import '../senders/senders_screen.dart';
import '../transactions/data/period.dart';
import '../wallets/wallets_screen.dart';

const kAddMemberTileKey = Key('settings-add-member');
const kSettingsWalletsKey = Key('settings-wallets');
const kSettingsSendersKey = Key('settings-senders');
const kShowSmsToggleKey = Key('settings-show-sms');
const kSettingsReviewKey = Key('settings-review');
const kSettingsReconcileKey = Key('settings-reconcile');
const kSettingsCategorizeKey = Key('settings-categorize');
const kCategorizeFromTileKey = Key('settings-categorize-from');
const kSyncNowKey = Key('settings-sync-now');
const kSyncStatusKey = Key('settings-sync-status');
const kThemeToggleKey = Key('theme-toggle');
const kLogoutKey = Key('settings-logout');

String _fa(int n) => toPersianDigits('$n');

class SettingsScreen extends StatefulWidget {
  final DashboardController controller;
  final Future<String> Function()? onSync;
  final VoidCallback? onLogout;
  final VoidCallback? onOpenFamilyDashboard;

  const SettingsScreen({
    super.key,
    required this.controller,
    this.onSync,
    this.onLogout,
    this.onOpenFamilyDashboard,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _syncing = false;
  DashboardController get _c => widget.controller;

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      final message = await widget.onSync!();
      await _c.load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _pickCategorizeFrom() async {
    final current = Period.containing(_c.now);
    final options = <(String, DateTime)>[
      ('از اول ${current.next.title} (ماه بعد)', current.next.from!),
      ('از اول ${current.title} (همین ماه)', current.from!),
      ('از اول ${current.previous.title} (ماه قبل)', current.previous.from!),
      ('از همین حالا', _c.now),
    ];
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('دسته‌بندی از چه تاریخی شروع شود؟'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('تراکنش‌های قبل از این تاریخ در صف دسته‌بندی نمی‌آیند و '
                'برایشان اعلان هم نمی‌آید (در فهرست و جمع‌ها هستند).'),
          ),
          for (final (label, at) in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(at),
              child: Text(label),
            ),
        ],
      ),
    );
    if (picked != null) await _c.setCategorizeFrom(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات و ابزارها')),
      body: AnimatedBuilder(
        animation: Listenable.merge([_c, themeController]),
        builder: (context, _) {
          final c = _c;
          final status = c.syncStatus;
          final from = c.categorizeFrom;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Group(title: 'حساب', children: [
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text(c.meName ?? 'کاربر'),
                  subtitle: Text(c.members.isEmpty
                      ? 'فهرست اعضای خانواده هنوز از سرور گرفته نشده'
                      : 'اعضای خانواده: ${c.members.map((m) => m.name).join('، ')}'),
                ),
                if (c.canAddMember) ...[
                  const Divider(indent: 56),
                  ListTile(
                    key: kAddMemberTileKey,
                    leading: const Icon(Icons.person_add_alt_1_rounded),
                    title: const Text('افزودن عضو خانواده'),
                    subtitle: Text(
                        'تا ${_fa(DashboardController.maxFamilyMembers - c.members.length)} نفرِ دیگر '
                        '(حداکثر ${_fa(DashboardController.maxFamilyMembers)} نفر)'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: () => _push(AddMemberScreen(controller: c)),
                  ),
                ] else if (c.isManager && c.members.length >= DashboardController.maxFamilyMembers) ...[
                  const Divider(indent: 56),
                  ListTile(
                    leading: const Icon(Icons.group_rounded),
                    title: const Text('خانواده کامل است'),
                    subtitle: Text('به حداکثر ${_fa(DashboardController.maxFamilyMembers)} نفر رسیده‌ای'),
                    enabled: false,
                  ),
                ],
              ]),
              _Group(title: 'کارت‌ها', children: [
                ListTile(
                  key: kSettingsWalletsKey,
                  leading: const Icon(Icons.credit_card_rounded),
                  title: const Text('کارت‌ها و حساب‌ها'),
                  subtitle: Text('${_fa(c.wallets.length)} کارت/حساب ثبت‌شده — '
                      'مشخص می‌کند هر تراکنش مال کیست'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => _push(WalletsScreen(controller: c)),
                ),
              ]),
              _Group(title: 'پیامک‌ها', children: [
                ListTile(
                  key: kSettingsSendersKey,
                  leading: Icon(Icons.mark_email_read_outlined,
                      color: c.needsSenderSetup ? scheme.error : null),
                  title: const Text('فرستنده‌های پیامک بانک'),
                  subtitle: Text(c.needsSenderSetup
                      ? 'هیچ فرستنده‌ای مجاز نشده؛ فعلاً هیچ پیامکی خودکار ثبت نمی‌شود'
                      : '${_fa(c.allowedSenders.length)} فرستنده — فقط پیامک این‌ها ثبت می‌شود'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => _push(SendersScreen(controller: c)),
                ),
                const Divider(indent: 56),
                SwitchListTile(
                  key: kShowSmsToggleKey,
                  secondary: const Icon(Icons.sms_outlined),
                  title: const Text('نمایش متن پیامک روی تراکنش‌ها'),
                  subtitle: const Text('تا پیامکی که اشتباهی ثبت شده زود پیدا شود'),
                  value: c.showSmsText,
                  onChanged: c.setShowSmsText,
                ),
              ]),
              _Group(title: 'نیاز به توجه', children: [
                ListTile(
                  key: kSettingsReviewKey,
                  leading: const Icon(Icons.error_outline_rounded),
                  title: const Text('بازبینی پیامک‌های مبهم'),
                  subtitle: Text(c.needsReviewCount > 0
                      ? '${_fa(c.needsReviewCount)} مورد منتظر تصمیم شماست'
                      : 'موردی نیست'),
                  trailing: _Count(c.needsReviewCount),
                  onTap: () => _push(ReviewScreen(controller: c)),
                ),
                const Divider(indent: 56),
                ListTile(
                  key: kSettingsReconcileKey,
                  leading: const Icon(Icons.rule_rounded),
                  title: const Text('ناهماهنگی مانده (پیامک جاافتاده)'),
                  subtitle: const Text('وقتی مانده‌ی پیامک‌ها با هم جور نیست'),
                  trailing: _Count(c.balanceGaps.length),
                  onTap: () => _push(ReconciliationScreen(controller: c)),
                ),
                const Divider(indent: 56),
                ListTile(
                  key: kSettingsCategorizeKey,
                  leading: const Icon(Icons.label_outline_rounded),
                  title: const Text('منتظر دسته‌بندی'),
                  subtitle: const Text('تراکنش‌های خودت بدون دسته'),
                  trailing: _Count(c.uncategorizedCount),
                  onTap: () => _push(CategorizeListScreen(controller: c)),
                ),
                const Divider(indent: 56),
                ListTile(
                  key: kCategorizeFromTileKey,
                  leading: const Icon(Icons.event_available_rounded),
                  title: const Text('شروع دسته‌بندی از'),
                  subtitle: Text(from == null
                      ? '—'
                      : '${formatJalaliDate(from)} — تراکنش‌های قبل از آن دسته‌بندی نمی‌خواهند'),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: _pickCategorizeFrom,
                ),
              ]),
              _Group(title: 'همگام‌سازی با سرور خانواده', children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'برای اینکه بقیه‌ی اعضای خانواده تراکنش‌های این گوشی را ببینند (و شما '
                    'مال آن‌ها را)، تراکنش‌ها به سرور خانواده فرستاده می‌شوند. سرور فعلاً '
                    'کامپیوتر خانه است؛ اگر خاموش باشد یا گوشی به همان Wi-Fi وصل نباشد، '
                    'ارسال ناموفق می‌شود و تراکنش‌ها در صف می‌مانند تا دفعه‌ی بعد — چیزی گم '
                    'نمی‌شود. متن پیامک‌ها هرگز فرستاده نمی‌شود.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                ListTile(
                  key: kSyncStatusKey,
                  leading: Icon(status.last?.offline == true
                      ? Icons.cloud_off_rounded
                      : Icons.cloud_done_outlined),
                  title: Text(status.lastAt == null
                      ? 'هنوز همگام‌سازی نشده'
                      : 'آخرین همگام‌سازی: ${formatJalaliDateTime(status.lastAt!)}'),
                  subtitle: Text([
                    if (status.last != null) status.last!.message,
                    '${_fa(status.pendingCount)} تراکنش در صف ارسال',
                  ].join('\n')),
                ),
                if (widget.onSync != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: FilledButton.icon(
                      key: kSyncNowKey,
                      onPressed: _syncing ? null : _syncNow,
                      icon: _syncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_rounded),
                      label: Text(_syncing ? 'در حال همگام‌سازی…' : 'همگام‌سازی الان'),
                    ),
                  ),
                if (widget.onOpenFamilyDashboard != null) ...[
                  const Divider(indent: 56),
                  ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: const Text('خلاصه‌ی خانواده از سرور'),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: widget.onOpenFamilyDashboard,
                  ),
                ],
              ]),
              _Group(title: 'ظاهر', children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SegmentedButton<ThemeMode>(
                    key: kThemeToggleKey,
                    segments: const [
                      ButtonSegment(value: ThemeMode.system, label: Text('خودکار'), icon: Icon(Icons.brightness_auto_outlined)),
                      ButtonSegment(value: ThemeMode.light, label: Text('روشن'), icon: Icon(Icons.light_mode_outlined)),
                      ButtonSegment(value: ThemeMode.dark, label: Text('تیره'), icon: Icon(Icons.dark_mode_outlined)),
                    ],
                    selected: {themeController.mode},
                    onSelectionChanged: (s) => themeController.setMode(s.first),
                  ),
                ),
              ]),
              if (widget.onLogout != null)
                _Group(title: '', children: [
                  ListTile(
                    key: kLogoutKey,
                    leading: Icon(Icons.logout_rounded, color: scheme.error),
                    title: Text('خروج از حساب', style: TextStyle(color: scheme.error)),
                    onTap: widget.onLogout,
                  ),
                ]),
            ],
          );
        },
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Group({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                )),
          )
        else
          const SizedBox(height: 16),
        Card(clipBehavior: Clip.antiAlias, child: Column(children: children)),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  final int count;

  const _Count(this.count);

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const Icon(Icons.chevron_left_rounded);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(_fa(count), style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}
