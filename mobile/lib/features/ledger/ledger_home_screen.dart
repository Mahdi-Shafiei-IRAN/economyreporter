/// صفحه‌ی اصلی (طرح ۱۲.۹): مثلِ داشبوردِ قبلی — ماه، اعضا، کارت‌ها، خالصِ ماه و موجودی، تراشه‌ی کارها، و
/// «اعضا و کارت‌ها» یا «روز به روز». مدیر همه‌ی اعضا را می‌بیند؛ مالِ بقیه فقط دیدنی است.
/// اولین بار راهنمای سه‌قدمی باز می‌شود.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/ledger/dashboard.dart';
import '../../core/ledger/models.dart';
import '../../core/sms/jalali.dart';
import '../../core/theme/app_theme.dart';
import 'account_details_screen.dart';
import 'accounts_view.dart';
import 'banks_view.dart';
import 'entry_sheet.dart';
import 'ledger_controller.dart';
import 'ledger_text.dart';
import 'month_report_screen.dart';
import 'pending_screen.dart';
import 'setup_screen.dart';

const kLedgerMonthCardKey = Key('ledger-month-card');
const kLedgerAddFabKey = Key('ledger-add-fab');
const kLedgerSettingsKey = Key('ledger-settings');
const kHomeMonthPrevKey = Key('home-month-prev');
const kHomeMonthNextKey = Key('home-month-next');
const kHomeMonthTitleKey = Key('home-month-title');
const kHomeNetKey = Key('home-net');
const kHomePersonAllKey = Key('home-person-all');
const kHomeCardAllKey = Key('home-card-all');
const kHomeViewKey = Key('home-view');
const kHomeBanksChipKey = Key('home-chip-banks');
const kHomeCandidatesChipKey = Key('home-chip-candidates');
const kHomeAnchorChipKey = Key('home-chip-anchor');
const kHomePendingChipKey = Key('home-chip-pending');
const kHomeWindowsChipKey = Key('home-chip-windows');
Key homePersonChipKey(String key) => Key('home-person-$key');
Key homeCardChipKey(String id) => Key('home-card-$id');
Key homePersonSectionKey(String key) => Key('home-section-$key');
Key homeCardRowKey(String id) => Key('home-card-row-$id');
Key homeCardDetailsKey(String id) => Key('home-card-details-$id');
Key homeEntryKey(String id) => Key('home-entry-$id');
Key homeDayKey(DateTime day) => Key('home-day-${day.toIso8601String()}');

String _fa(int n) => toPersianDigits('$n');

String _signed(int rial) => '${rial >= 0 ? '+' : '−'}${formatToman(rial.abs())}';

String _monthTitle(DateTime at) {
  final j = JalaliDate.fromDateTime(at);
  return '${jalaliMonthName(j.month)} ${toPersianDigits('${j.year}')}';
}

String _short(int rial) => formatToman(rial, withUnit: false);

/// «هزینه ۱۲۰ • درآمد ۵۰۰» (هزار تومان نه؛ همان تومان بی‌واحد).
String _totals(int income, int expense) => [
      if (expense > 0) 'هزینه ${_short(expense)}',
      if (income > 0) 'درآمد ${_short(income)}',
    ].join(' • ');

/// عنوانِ کارتِ کوچک (تراشه): «ملت ۵۵۹۶».
String _cardChipLabel(LedgerAccount a) {
  final number = a.cardLast4 ??
      (a.accountRef == null || a.accountRef!.length < 4
          ? a.accountRef
          : a.accountRef!.substring(a.accountRef!.length - 4));
  return [accountTitle(a), if (number != null) toPersianDigits(number)].join(' ');
}

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

  late DateTime _month = _c.now;
  String? _person;
  String? _card;
  bool _byDay = false;
  final Set<String> _collapsedPeople = {};
  final Set<String> _openCards = {};

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

  DateTime get _monthStart => jalaliMonthRange(_month).$1;
  bool get _canGoBack => _monthStart.isAfter(_c.firstMonth);
  bool get _canGoForward => _monthStart.isBefore(jalaliMonthRange(_c.now).$1);

  void _shiftMonth(int by) {
    final (from, to) = jalaliMonthRange(_month);
    setState(() => _month = by < 0 ? from.subtract(const Duration(days: 1)) : to.add(const Duration(days: 1)));
  }

  @override
  Widget build(BuildContext context) {
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
          final d = _c.dashboard(_month, personKey: _person, accountId: _card);
          // عضو یا کارتی که دیگر نیست (مثلاً کنار گذاشته شد) = همه.
          final person = d.people.any((p) => p.key == _person) ? _person : null;
          final card = d.cardChoices.any((a) => a.id == _card) ? _card : null;
          return RefreshIndicator(
            onRefresh: _c.syncInbox,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
              children: [
                _MonthBar(
                  title: _monthTitle(_month),
                  onPrev: _canGoBack ? () => _shiftMonth(-1) : null,
                  onNext: _canGoForward ? () => _shiftMonth(1) : null,
                ),
                if (d.people.length > 1)
                  _ChipRow(children: [
                    ChoiceChip(
                      key: kHomePersonAllKey,
                      label: const Text('همه'),
                      selected: person == null,
                      onSelected: (_) => setState(() {
                        _person = null;
                        _card = null;
                      }),
                    ),
                    for (final p in d.people)
                      ChoiceChip(
                        key: homePersonChipKey(p.key),
                        label: Text(p.name),
                        selected: person == p.key,
                        onSelected: (_) => setState(() {
                          _person = p.key;
                          _card = null;
                        }),
                      ),
                  ]),
                if (d.cardChoices.length > 1)
                  _ChipRow(children: [
                    ChoiceChip(
                      key: kHomeCardAllKey,
                      label: const Text('همه‌ی کارت‌ها'),
                      selected: card == null,
                      onSelected: (_) => setState(() => _card = null),
                    ),
                    for (final a in d.cardChoices)
                      ChoiceChip(
                        key: homeCardChipKey(a.id),
                        avatar: Icon(a.bankId == null ? Icons.payments_outlined : Icons.credit_card_rounded,
                            size: 18),
                        label: Text(_cardChipLabel(a)),
                        selected: card == a.id,
                        onSelected: (_) => setState(() => _card = a.id),
                      ),
                  ]),
                _SummaryCard(
                  dashboard: d,
                  month: _monthTitle(_month),
                  scope: [
                    if (person == null)
                      'همه'
                    else
                      d.people.firstWhere((p) => p.key == person).name,
                    if (card != null) _cardChipLabel(d.cardChoices.firstWhere((a) => a.id == card)),
                  ].join(' • '),
                  onTap: () => _push(MonthReportScreen(controller: _c, initialMonth: _month)),
                ),
                _TaskChips(controller: _c, onOpen: _push),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: SegmentedButton<bool>(
                    key: kHomeViewKey,
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: false, icon: Icon(Icons.groups_outlined), label: Text('اعضا و کارت‌ها')),
                      ButtonSegment(value: true, icon: Icon(Icons.event_note_outlined), label: Text('روز به روز')),
                    ],
                    selected: {_byDay},
                    onSelectionChanged: (s) => setState(() => _byDay = s.first),
                  ),
                ),
                if (d.shown.isEmpty)
                  const _Empty('هنوز حسابی نیست؛ تراشه‌های بالا راهنمایی می‌کنند.')
                else if (_byDay)
                  ..._dayView(d)
                else
                  for (final p in d.shown) _personSection(p, showPersonName: d.people.length > 1),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _dayView(Dashboard d) {
    if (d.days.isEmpty) return [_Empty('در ${_monthTitle(_month)} تراکنشی نیست.')];
    final theme = Theme.of(context);
    final showOwner = d.people.length > 1;
    return [
      for (final day in d.days) ...[
        Padding(
          key: homeDayKey(day.day),
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
          child: Row(children: [
            Expanded(child: Text(formatDayHeader(day.day), style: theme.textTheme.labelLarge)),
            Text(_totals(day.incomeRial, day.expenseRial),
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < day.entries.length; i++) ...[
              if (i > 0) const Divider(height: 1, indent: 56),
              _EntryTile(
                controller: _c,
                entry: day.entries[i].entry,
                account: day.entries[i].account,
                showAccount: true,
                showOwner: showOwner,
              ),
            ],
          ]),
        ),
      ],
    ];
  }

  Widget _personSection(PersonGroup p, {required bool showPersonName}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fin = FinanceColors.of(context);
    final collapsed = _collapsedPeople.contains(p.key);
    return Card(
      key: homePersonSectionKey(p.key),
      margin: const EdgeInsets.only(top: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => collapsed ? _collapsedPeople.remove(p.key) : _collapsedPeople.add(p.key)),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 10, 12),
            child: Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: p.isMe ? scheme.primaryContainer : scheme.secondaryContainer,
                child: Text(p.name.isEmpty ? '؟' : p.name.substring(0, 1),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.isMe && showPersonName ? '${p.name} (من)' : p.name,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('${_fa(p.count)} تراکنش • ${_fa(p.cards.length)} کارت/حساب',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('هزینه ${_short(p.expenseRial)}',
                    style: theme.textTheme.labelLarge?.copyWith(color: fin.expense, fontWeight: FontWeight.w700)),
                if (p.incomeRial > 0)
                  Text('درآمد ${_short(p.incomeRial)}',
                      style: theme.textTheme.labelMedium?.copyWith(color: fin.income)),
              ]),
              Icon(collapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded,
                  color: scheme.onSurfaceVariant),
            ]),
          ),
        ),
        if (!collapsed) for (final c in p.cards) ..._cardSection(c),
      ]),
    );
  }

  List<Widget> _cardSection(CardGroup c) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = c.account;
    final open = _openCards.contains(a.id);
    final mine = _c.canEdit(a.id);
    final view = _c.view(a.id);
    final totals = _totals(c.incomeRial, c.expenseRial);
    return [
      const Divider(height: 1),
      Material(
        color: scheme.surfaceContainer.withOpacity(0.55),
        child: InkWell(
          key: homeCardRowKey(a.id),
          onTap: () => setState(() => open ? _openCards.remove(a.id) : _openCards.add(a.id)),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 4, 8),
            child: Row(children: [
              Icon(a.bankId == null ? Icons.payments_outlined : Icons.credit_card_rounded,
                  size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_cardChipLabel(a), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    [
                      c.balanceRial == null ? 'موجودی نامعلوم' : 'موجودی ${formatToman(c.balanceRial!)}',
                      if (totals.isNotEmpty) totals,
                    ].join(' • '),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (mine && (view?.discrepancyCount ?? 0) > 0)
                    Text('با مانده‌ی بانک نمی‌خواند',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(_fa(c.entries.length), style: theme.textTheme.labelMedium),
              ),
              IconButton(
                key: homeCardDetailsKey(a.id),
                tooltip: 'جزئیاتِ حساب',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => _push(AccountDetailsScreen(controller: _c, accountId: a.id)),
              ),
            ]),
          ),
        ),
      ),
      if (open)
        if (c.entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('این ماه تراکنشی نیست.', style: theme.textTheme.bodySmall),
          )
        else
          for (var i = 0; i < c.entries.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 56),
            _EntryTile(controller: _c, entry: c.entries[i], account: a, showDate: true),
          ],
    ];
  }
}

class _MonthBar extends StatelessWidget {
  final String title;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _MonthBar({required this.title, this.onPrev, this.onNext});

  @override
  Widget build(BuildContext context) {
    // راست‌به‌چپ: دکمه‌ی راست = ماهِ قبل، رو به بیرون. (Flutter فلش‌ها را در راست‌به‌چپ برعکس می‌کشد.)
    return Row(children: [
      IconButton(
          key: kHomeMonthPrevKey,
          tooltip: 'ماهِ قبل',
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left_rounded)),
      Expanded(
        child: Text(title,
            key: kHomeMonthTitleKey,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ),
      IconButton(
          key: kHomeMonthNextKey,
          tooltip: 'ماهِ بعد',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded)),
    ]);
  }
}

class _ChipRow extends StatelessWidget {
  final List<Widget> children;

  const _ChipRow({required this.children});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(children: [
          for (final c in children) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: c),
        ]),
      );
}

class _SummaryCard extends StatelessWidget {
  final Dashboard dashboard;
  final String month;
  final String scope;
  final VoidCallback onTap;

  const _SummaryCard({required this.dashboard, required this.month, required this.scope, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fin = FinanceColors.of(context);
    final d = dashboard;
    const onHero = Colors.white;
    final muted = onHero.withOpacity(0.85);
    return Card(
      key: kLedgerMonthCardKey,
      margin: const EdgeInsets.only(top: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [fin.heroStart, fin.heroEnd],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Text('خالصِ $month ($scope)',
                      style: theme.textTheme.labelLarge?.copyWith(color: muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              Text('گزارش', style: theme.textTheme.labelLarge?.copyWith(color: onHero)),
              const Icon(Icons.chevron_right_rounded, color: onHero, size: 20),
            ]),
            const SizedBox(height: 4),
            Text(_signed(d.netRial),
                key: kHomeNetKey,
                style: theme.textTheme.headlineMedium?.copyWith(color: onHero, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _HeroFigure(label: 'درآمد', value: formatToman(d.incomeRial))),
              Expanded(child: _HeroFigure(label: 'هزینه', value: formatToman(d.expenseRial))),
            ]),
            const SizedBox(height: 8),
            Text(
              d.balanceRial == null
                  ? 'موجودیِ الانِ این کارت‌ها: نامعلوم'
                  : 'موجودیِ الانِ این کارت‌ها: ${formatToman(d.balanceRial!)}'
                      '${d.unknownBalances > 0 ? ' (+ ${_fa(d.unknownBalances)} کارتِ نامعلوم)' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ]),
        ),
      ),
    );
  }
}

class _HeroFigure extends StatelessWidget {
  final String label;
  final String value;

  const _HeroFigure({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: theme.textTheme.labelSmall?.copyWith(color: Colors.white.withOpacity(0.85))),
      Text(value, style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
    ]);
  }
}

/// کارهای مانده به‌شکلِ تراشه‌ی کوچک (جای کارتِ «قدمِ بعدی»)؛ فقط وقتی کاری هست.
class _TaskChips extends StatelessWidget {
  final LedgerController controller;
  final void Function(Widget page) onOpen;

  const _TaskChips({required this.controller, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    final needAnchor = c.activeAccounts.where((a) => a.needsAnchor).length;
    final firstWindow = c.activeAccounts.where((a) => a.discrepancyCount > 0).firstOrNull;
    final chips = <Widget>[
      if (c.banks.isEmpty)
        ActionChip(
          key: kHomeBanksChipKey,
          avatar: const Icon(Icons.account_balance_outlined, size: 18),
          label: const Text('بانک‌هایت را انتخاب کن'),
          onPressed: () => onOpen(LedgerBanksScreen(controller: c)),
        ),
      if (c.accountCandidates.isNotEmpty)
        ActionChip(
          key: kHomeCandidatesChipKey,
          avatar: const Icon(Icons.credit_card_rounded, size: 18),
          label: Text('${_fa(c.accountCandidates.length)} حسابِ تازه در پیامک‌ها'),
          onPressed: () => onOpen(LedgerAccountsScreen(controller: c)),
        ),
      if (needAnchor > 0)
        ActionChip(
          key: kHomeAnchorChipKey,
          avatar: const Icon(Icons.account_balance_wallet_outlined, size: 18),
          label: Text('${_fa(needAnchor)} حسابِ بی‌موجودی'),
          onPressed: () => onOpen(LedgerAccountsScreen(controller: c)),
        ),
      if (c.pendingCount > 0)
        ActionChip(
          key: kHomePendingChipKey,
          backgroundColor: scheme.primaryContainer,
          avatar: Icon(Icons.mark_email_unread_outlined, size: 18, color: scheme.onPrimaryContainer),
          label: Text('${_fa(c.pendingCount)} پیامکِ منتظرِ تأیید',
              style: TextStyle(color: scheme.onPrimaryContainer)),
          onPressed: () => onOpen(PendingScreen(controller: c)),
        ),
      if (firstWindow != null)
        ActionChip(
          key: kHomeWindowsChipKey,
          avatar: Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
          label: Text('${_fa(c.windowCount)} اختلاف با بانک'),
          onPressed: () => onOpen(AccountDetailsScreen(controller: c, accountId: firstWindow.account.id)),
        ),
    ];
    if (chips.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final LedgerController controller;
  final Entry entry;
  final LedgerAccount account;
  final bool showAccount;
  final bool showOwner;
  final bool showDate;

  const _EntryTile({
    required this.controller,
    required this.entry,
    required this.account,
    this.showAccount = false,
    this.showOwner = false,
    this.showDate = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fin = FinanceColors.of(context);
    final e = entry;
    final cats = controller.allocations[e.id] ?? const [];
    final title = (e.note?.trim().isNotEmpty ?? false)
        ? e.note!.trim()
        : cats.isNotEmpty
            ? cats.map((c) => c.name).join('، ')
            : switch (e.source) {
                EntrySource.sms => kindLabel(e.kind),
                EntrySource.manual => '${kindLabel(e.kind)} (دستی)',
                EntrySource.adjustment => 'اصلاح',
              };
    final income = e.kind == EntryKind.income;
    final color = e.isTransfer ? fin.transfer : (income ? fin.income : fin.expense);
    final canEdit = controller.canEdit(account.id);
    return ListTile(
      key: homeEntryKey(e.id),
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: e.isTransfer ? fin.transferContainer : (income ? fin.incomeContainer : fin.expenseContainer),
        child: Icon(
          e.isTransfer ? Icons.swap_horiz_rounded : (income ? Icons.south_west_rounded : Icons.north_east_rounded),
          size: 18,
          color: color,
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          showDate ? formatShortDateTime(e.occurredAt) : formatClock(e.occurredAt),
          if (showOwner) account.ownerName,
          if (showAccount) _cardChipLabel(account),
          if (e.isTransfer) 'انتقال',
          if (cats.isEmpty && !income && !e.isTransfer && canEdit) 'بی‌دسته',
        ].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(_signed(e.signed),
          style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
      onTap: canEdit ? () => showEntrySheet(context, controller, entry: e) : null,
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;

  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      );
}
