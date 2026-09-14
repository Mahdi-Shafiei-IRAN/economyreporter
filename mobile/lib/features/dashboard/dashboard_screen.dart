/// صفحه‌ی اصلی: سه زبانه — تراکنش‌ها (پله‌ای یا همه)، گزارش، تنظیمات.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/theme/app_theme.dart';
import '../categories/categorize_list_screen.dart';
import '../categories/categorize_screen.dart';
import '../reports/report_screen.dart';
import '../review/reconciliation_screen.dart';
import '../review/duplicates_screen.dart';
import '../review/review_screen.dart';
import '../senders/senders_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/data/transaction_record.dart';
import '../transactions/data/tx_query.dart';
import '../transactions/transaction_details_sheet.dart';
import '../transactions/widgets/period_bar.dart';
import '../transactions/widgets/summary_card.dart';
import '../transactions/widgets/tx_widgets.dart';
import '../wallets/wallets_screen.dart';
import 'dashboard_controller.dart';

// کلیدهای تست.
const kAddSmsFabKey = Key('add-sms-fab');
const kSmsSenderFieldKey = Key('sms-sender-field');
const kSmsBodyFieldKey = Key('sms-body-field');
const kSmsSaveButtonKey = Key('sms-save-button');
const kEmptyStateKey = Key('empty-state');
const kViewToggleKey = Key('view-toggle');
const kSortButtonKey = Key('sort-button');
const kFilterButtonKey = Key('filter-button');
const kSearchButtonKey = Key('search-button');
const kSearchFieldKey = Key('search-field');
const kReviewChipKey = Key('review-chip');
const kCategorizeChipKey = Key('categorize-chip');
const kReconcileChipKey = Key('reconcile-chip');
const kDuplicatesChipKey = Key('duplicates-chip');
const kSyncChipKey = Key('sync-chip');
const kSelectionBarKey = Key('selection-bar');
const kSelectionCountKey = Key('selection-count');
const kSelectionAllKey = Key('selection-all');
const kSelectionCategorizeKey = Key('selection-categorize');
const kSelectionDeleteKey = Key('selection-delete');
const kNavTransactionsKey = Key('nav-transactions');
const kNavReportKey = Key('nav-report');
const kNavSettingsKey = Key('nav-settings');

String _fa(int n) => toPersianDigits('$n');

class DashboardScreen extends StatefulWidget {
  final DashboardController controller;
  final VoidCallback? onLogout;

  /// همگام‌سازی دستی؛ پیام نتیجه را برمی‌گرداند تا نشان داده شود.
  final Future<String> Function()? onSync;

  /// باز کردن خلاصه‌ی خانواده از سرور (نیازمند شبکه).
  final VoidCallback? onOpenFamilyDashboard;

  const DashboardScreen({
    super.key,
    required this.controller,
    this.onLogout,
    this.onSync,
    this.onOpenFamilyDashboard,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tab = 0;
  DashboardController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final attention = _c.needsReviewCount + _c.balanceGaps.length;
        return Scaffold(
          body: IndexedStack(
            index: _tab,
            children: [
              _TransactionsTab(
                controller: _c,
                onOpenSettings: () => setState(() => _tab = 2),
                onOpenFamilyDashboard: widget.onOpenFamilyDashboard,
              ),
              ReportScreen(controller: _c),
              SettingsScreen(
                controller: _c,
                onSync: widget.onSync,
                onLogout: widget.onLogout,
                onOpenFamilyDashboard: widget.onOpenFamilyDashboard,
              ),
            ],
          ),
          bottomNavigationBar: _c.selectionMode
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  destinations: [
                    const NavigationDestination(
                      key: kNavTransactionsKey,
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long_rounded),
                      label: 'تراکنش‌ها',
                    ),
                    const NavigationDestination(
                      key: kNavReportKey,
                      icon: Icon(Icons.insights_outlined),
                      selectedIcon: Icon(Icons.insights_rounded),
                      label: 'گزارش و نمودار',
                    ),
                    NavigationDestination(
                      key: kNavSettingsKey,
                      icon: Badge(
                        isLabelVisible: attention > 0,
                        label: Text(_fa(attention)),
                        child: const Icon(Icons.tune_outlined),
                      ),
                      selectedIcon: const Icon(Icons.tune_rounded),
                      label: 'تنظیمات',
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _TransactionsTab extends StatefulWidget {
  final DashboardController controller;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenFamilyDashboard;

  const _TransactionsTab(
      {required this.controller,
      required this.onOpenSettings,
      this.onOpenFamilyDashboard});

  @override
  State<_TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<_TransactionsTab> {
  DashboardController get _c => widget.controller;
  bool _searching = false;
  final _searchCtrl = TextEditingController();

  /// پیام‌ها در Scaffold همین زبانه نشان داده شوند تا دکمه‌ی «+» بالای آن‌ها برود
  /// (در Scaffold بیرونی، پیام روی دکمه می‌افتاد و ضربه را می‌گرفت).
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// گروه‌هایی که کاربر باز/بسته کرده (پیش‌فرض: ماه باز، «همه‌ی زمان‌ها» بسته).
  final Set<String> _toggled = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isCollapsed(String key) => _c.period.isAll ^ _toggled.contains(key);

  void _toggle(String key) => setState(() {
        if (!_toggled.remove(key)) _toggled.add(key);
      });

  void _snack(String message) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _readOnly(TransactionRecord t) => _snack(
      'فقط ${_c.editorName(t)} (صاحب این کارت) می‌تواند این تراکنش را ویرایش یا دسته‌بندی کند.');

  void _onTap(TransactionRecord t) {
    if (_c.selectionMode) {
      if (!_c.toggleSelect(t)) _readOnly(t);
      return;
    }
    showTransactionDetails(context, _c, t);
  }

  void _onLongPress(TransactionRecord t) {
    if (!_c.toggleSelect(t)) _readOnly(t);
  }

  void _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _deleteSelected() async {
    final n = _c.selected.length;
    if (!await confirmInvalidate(context, count: n)) return;
    await _c.deleteSelected();
    if (mounted) _snack('${_fa(n)} تراکنش نامعتبر شد و از جمع‌ها بیرون رفت.');
  }

  Future<void> _categorizeSelected() async {
    final records = _c.selectedRecords
        .where((t) => t.kind == 'income' || t.kind == 'expense')
        .toList();
    if (records.isEmpty) {
      _snack('فقط تراکنش‌های واریز/برداشت دسته‌بندی می‌شوند.');
      return;
    }
    _push(CategorizeScreen(controller: _c, records: records));
  }

  Future<void> _pickSort() async {
    final picked = await showModalBottomSheet<TxSort>(
      context: context,
      useSafeArea: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ترتیب نمایش', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final s in TxSort.values)
            RadioListTile<TxSort>(
              value: s,
              groupValue: _c.sort,
              title: Text(s.label),
              onChanged: (v) => Navigator.of(context).pop(v),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
    if (picked != null) _c.setSort(picked);
  }

  Future<void> _openFilters() => showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (_) => _FilterSheet(controller: _c),
      );

  Future<void> _openAddSmsSheet() async {
    final input = await showModalBottomSheet<_SmsInput>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddSmsSheet(),
    );
    if (input == null) return;
    final outcome = await _c.addFromSms(sender: input.sender, body: input.body);
    if (!mounted) return;
    _snack(outcome.isDuplicate
        ? 'این پیامک قبلاً ثبت شده بود.'
        : 'تراکنش ثبت شد.');
  }

  PreferredSizeWidget _appBar() {
    if (_c.selectionMode) {
      return AppBar(
        key: kSelectionBarKey,
        leading: IconButton(
          tooltip: 'لغو انتخاب',
          icon: const Icon(Icons.close_rounded),
          onPressed: _c.clearSelection,
        ),
        title: Text('${_fa(_c.selected.length)} مورد انتخاب شد',
            key: kSelectionCountKey),
        actions: [
          IconButton(
            key: kSelectionAllKey,
            tooltip: 'انتخاب همه‌ی موارد قابل‌ویرایش',
            icon: const Icon(Icons.select_all_rounded),
            onPressed: _c.selectAllVisible,
          ),
          IconButton(
            key: kSelectionCategorizeKey,
            tooltip: 'دسته‌بندی گروهی',
            icon: const Icon(Icons.label_outline_rounded),
            onPressed: _categorizeSelected,
          ),
          IconButton(
            key: kSelectionDeleteKey,
            tooltip: 'نامعتبر (حذف)',
            icon: const Icon(Icons.block_rounded),
            onPressed: _deleteSelected,
          ),
        ],
      );
    }
    return AppBar(
      title: const Text('مالی خانواده'),
      actions: [
        IconButton(
          key: kSearchButtonKey,
          tooltip: _searching ? 'بستن جستجو' : 'جستجو',
          icon: Icon(
              _searching ? Icons.search_off_rounded : Icons.search_rounded),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) {
              _searchCtrl.clear();
              _c.setSearch('');
            }
          }),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return PopScope(
      canPop: !c.selectionMode,
      onPopInvoked: (didPop) {
        if (!didPop) c.clearSelection();
      },
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          appBar: _appBar(),
          floatingActionButton: c.selectionMode
              ? null
              : FloatingActionButton(
                  key: kAddSmsFabKey,
                  tooltip: 'افزودن دستی پیامک بانکی',
                  onPressed: _openAddSmsSheet,
                  child: const Icon(Icons.add_rounded),
                ),
          body: c.loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: c.load,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: PeriodBar(
                            period: c.period,
                            now: c.now,
                            onChanged: c.setPeriod,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(child: _PersonChips(controller: c)),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: SummaryCard(
                            summary: c.summary,
                            period: c.period,
                            count: c.visible.length,
                            filtered: c.hasActiveFilters,
                            scope: c.person == null ? null : _personLabel(c.person!),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _AttentionStrip(
                          controller: c,
                          push: _push,
                          onOpenSettings: widget.onOpenSettings,
                          onOpenFamilyDashboard: widget.onOpenFamilyDashboard,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _Toolbar(
                          controller: c,
                          onSort: _pickSort,
                          onFilter: _openFilters,
                        ),
                      ),
                      if (_searching)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                            child: TextField(
                              key: kSearchFieldKey,
                              controller: _searchCtrl,
                              autofocus: true,
                              onChanged: c.setSearch,
                              decoration: InputDecoration(
                                hintText: 'طرف حساب، توضیح، شخص، کارت یا مبلغ',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _searchCtrl.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'پاک کردن',
                                        icon: const Icon(Icons.clear_rounded),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          c.setSearch('');
                                        },
                                      ),
                              ),
                            ),
                          ),
                        ),
                      if (c.hasActiveFilters)
                        SliverToBoxAdapter(
                            child: _ActiveFilters(controller: c)),
                      ..._content(),
                      const SliverToBoxAdapter(child: SizedBox(height: 96)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  List<Widget> _content() {
    final c = _c;
    if (c.periodItems.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyState(
            key: kEmptyStateKey,
            icon: Icons.inbox_outlined,
            title: 'در ${c.period.title} تراکنشی نیست',
            message: c.needsSenderSetup
                ? 'هنوز فرستنده‌ی پیامک بانکی مشخص نشده؛ با تراشه‌ی «فرستنده‌های بانک» '
                    'بالای صفحه مشخص کن تا پیامک‌های بانک ثبت شوند.'
                : 'پیامک‌های بانکی به‌محض رسیدن خودکار این‌جا ثبت می‌شوند. '
                    'برای دیدن ماه‌های قبل از فلش بالای صفحه استفاده کن.',
          ),
        ),
      ];
    }
    if (c.visible.isEmpty) {
      final onlyPerson = c.person != null && !c.hasActiveFilters;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyState(
            key: kEmptyStateKey,
            icon: onlyPerson
                ? Icons.person_search_outlined
                : Icons.filter_alt_off_outlined,
            title: onlyPerson
                ? 'برای ${_personLabel(c.person!)} در ${c.period.title} تراکنشی نیست'
                : 'با این فیلترها چیزی پیدا نشد',
            action: TextButton(
              onPressed: () {
                _searchCtrl.clear();
                c.clearFilters();
              },
              child: Text(onlyPerson ? 'نمایش همه' : 'پاک کردن فیلترها'),
            ),
          ),
        ),
      ];
    }
    return c.view == HomeView.people ? _peopleSlivers() : _allSlivers();
  }

  List<Widget> _tiles(List<TransactionRecord> items,
          {required bool showOwner}) =>
      [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const Divider(indent: 68),
          TransactionTile(
            key: ValueKey('tx-${items[i].id}'),
            record: items[i],
            showOwner: showOwner,
            showSms: _c.showSmsText,
            canEdit: _c.canEdit(items[i]),
            selected: _c.isSelected(items[i].id),
            selectionMode: _c.selectionMode,
            categorizeFrom: _c.categorizeFrom,
            onTap: () => _onTap(items[i]),
            onLongPress: () => _onLongPress(items[i]),
          ),
        ],
      ];

  List<Widget> _peopleSlivers() {
    final groups = _c.personGroups;
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        sliver: SliverList.separated(
          itemCount: groups.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _PersonSection(
            group: groups[i],
            isCollapsed: _isCollapsed,
            onToggle: _toggle,
            buildTiles: (items) => _tiles(items, showOwner: false),
            onRegisterCard: (card) => showWalletForm(
              context,
              _c,
              bankId: card.bankId,
              cardLast4: card.cardLast4,
              accountRef: card.cardLast4 == null ? card.accountRef : null,
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _allSlivers() {
    final c = _c;
    if (c.sort.byDate) {
      final days = c.dayGroups;
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: days.length,
            itemBuilder: (context, i) {
              final d = days[i];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(
                    title: formatDayHeader(d.anchor),
                    trailing: shortTotals(
                        d.summary.incomeRial, d.summary.expenseRial),
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                  ),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: _tiles(d.items, showOwner: true)),
                  ),
                ],
              );
            },
          ),
        ),
      ];
    }
    final items = c.visible;
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        sliver: SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, i) => _GroupedRow(
            first: i == 0,
            last: i == items.length - 1,
            child: _tiles([items[i]], showOwner: true).single,
          ),
        ),
      ),
    ];
  }
}

/// ردیفِ یک فهرست گروهی بزرگ (ظاهر کارت پیوسته، ولی ساخت تنبل).
class _GroupedRow extends StatelessWidget {
  final bool first;
  final bool last;
  final Widget child;

  const _GroupedRow(
      {required this.first, required this.last, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const r = Radius.circular(16);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.vertical(
          top: first ? r : Radius.zero,
          bottom: last ? r : Radius.zero,
        ),
      ),
      child: Column(
        children: [
          if (!first) const Divider(indent: 68),
          child,
        ],
      ),
    );
  }
}

class _PersonSection extends StatelessWidget {
  final PersonGroup group;
  final bool Function(String key) isCollapsed;
  final void Function(String key) onToggle;
  final List<Widget> Function(List<TransactionRecord>) buildTiles;
  final void Function(CardGroup card) onRegisterCard;

  const _PersonSection({
    required this.group,
    required this.isCollapsed,
    required this.onToggle,
    required this.buildTiles,
    required this.onRegisterCard,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fin = FinanceColors.of(context);
    final key = 'p:${group.name}';
    final collapsed = isCollapsed(key);
    final s = group.summary;

    return Card(
      key: ValueKey('person-${group.name}'),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => onToggle(key),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 12, 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 21,
                    backgroundColor: group.isUnknown
                        ? scheme.surfaceContainerHigh
                        : scheme.primaryContainer,
                    child: group.isUnknown
                        ? Icon(Icons.help_outline_rounded,
                            color: scheme.onSurfaceVariant)
                        : Text(
                            group.name.substring(0, 1),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.isUnknown ? 'کارت‌های بی‌صاحب' : group.name,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '${_fa(group.count)} تراکنش • ${_fa(group.cards.length)} کارت/حساب',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'هزینه ${formatToman(s.expenseRial, withUnit: false)}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: fin.expense,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (s.incomeRial > 0)
                        Text(
                          'درآمد ${formatToman(s.incomeRial, withUnit: false)}',
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: fin.income),
                        ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    collapsed
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (!collapsed)
            for (final card in group.cards) ..._cardSection(context, card),
        ],
      ),
    );
  }

  List<Widget> _cardSection(BuildContext context, CardGroup card) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fin = FinanceColors.of(context);
    final key = 'c:${group.name}|${card.key}';
    final collapsed = isCollapsed(key);
    // بی‌بانک و بی‌شماره: هیچ کارتی نمی‌تواند با این پیامک‌ها جور شود.
    final identifiable =
        card.bankId != null || card.cardLast4 != null || card.accountRef != null;
    final canRegister =
        identifiable && !card.registered && card.items.any((t) => !t.isRemote);
    final s = card.summary;

    return [
      const Divider(),
      Material(
        color: scheme.surfaceContainer.withOpacity(0.55),
        child: InkWell(
          key: ValueKey('card-${group.name}-${card.key}'),
          onTap: () => onToggle(key),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
            child: Row(
              children: [
                Icon(Icons.credit_card_rounded,
                    size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      if (card.details != null)
                        Text(card.details!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      if (!card.registered && !identifiable)
                        Text('بدون بانک — از «فرستنده‌های پیامک» مشخص کن',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: fin.warning)),
                      if (shortTotals(s.incomeRial, s.expenseRial).isNotEmpty)
                        Text(shortTotals(s.incomeRial, s.expenseRial),
                            style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
                if (canRegister)
                  TextButton(
                    onPressed: () => onRegisterCard(card),
                    child: const Text('تعیین صاحب'),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(_fa(card.items.length),
                      style: theme.textTheme.labelMedium),
                ),
                Icon(
                  collapsed
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
      if (!collapsed) ...[const Divider(), ...buildTiles(card.items)],
    ];
  }
}

const kSendersChipKey = Key('senders-chip');
const kFamilyTotalsChipKey = Key('family-totals-chip');

class _AttentionStrip extends StatelessWidget {
  final DashboardController controller;
  final void Function(Widget page) push;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenFamilyDashboard;

  const _AttentionStrip({
    required this.controller,
    required this.push,
    required this.onOpenSettings,
    this.onOpenFamilyDashboard,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final fin = FinanceColors.of(context);
    final pending = c.syncStatus.pendingCount;
    final chips = <Widget>[
      if (!c.isManager && onOpenFamilyDashboard != null)
        ActionChip(
          key: kFamilyTotalsChipKey,
          avatar: const Icon(Icons.groups_outlined, size: 18),
          label: const Text('جمعِ خانواده'),
          onPressed: onOpenFamilyDashboard,
        ),
      if (c.needsSenderSetup)
        ActionChip(
          key: kSendersChipKey,
          avatar: Icon(Icons.mark_email_unread_outlined,
              color: fin.warning, size: 18),
          label: const Text('فرستنده‌های بانک را مشخص کن'),
          onPressed: () => push(SendersScreen(controller: c)),
        ),
      if (c.needsReviewCount > 0)
        ActionChip(
          key: kReviewChipKey,
          avatar:
              Icon(Icons.error_outline_rounded, color: fin.warning, size: 18),
          label: Text('${_fa(c.needsReviewCount)} نیازمند بازبینی'),
          onPressed: () => push(ReviewScreen(controller: c)),
        ),
      if (c.uncategorizedCount > 0)
        ActionChip(
          key: kCategorizeChipKey,
          avatar: const Icon(Icons.label_outline_rounded, size: 18),
          label: Text('${_fa(c.uncategorizedCount)} منتظر دسته‌بندی'),
          onPressed: () => push(CategorizeListScreen(controller: c)),
        ),
      if (c.balanceGaps.isNotEmpty)
        ActionChip(
          key: kReconcileChipKey,
          avatar: Icon(Icons.rule_rounded, color: fin.warning, size: 18),
          label: Text('${_fa(c.balanceGaps.length)} ناهماهنگی مانده'),
          onPressed: () => push(ReconciliationScreen(controller: c)),
        ),
      if (c.duplicateGroups.isNotEmpty)
        ActionChip(
          key: kDuplicatesChipKey,
          avatar: Icon(Icons.copy_all_rounded, color: fin.warning, size: 18),
          label: Text('${_fa(c.duplicateGroups.length)} احتمال تکراری'),
          onPressed: () => push(DuplicatesScreen(controller: c)),
        ),
      if (pending > 0 && c.syncStatus.last?.error != null)
        ActionChip(
          key: kSyncChipKey,
          avatar: const Icon(Icons.cloud_off_rounded, size: 18),
          label: Text('${_fa(pending)} در صف ارسال'),
          onPressed: onOpenSettings,
        ),
    ];
    if (chips.isEmpty) return const SizedBox(height: 8);
    // Wrap (نه فهرست افقی): همه‌ی تراشه‌ها دیده شوند، حتی وقتی چندتا هستند.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final DashboardController controller;
  final VoidCallback onSort;
  final VoidCallback onFilter;

  const _Toolbar(
      {required this.controller, required this.onSort, required this.onFilter});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<HomeView>(
            key: kViewToggleKey,
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: HomeView.people,
                icon: Icon(Icons.account_tree_outlined),
                label: Text('افراد و کارت‌ها'),
              ),
              ButtonSegment(
                value: HomeView.all,
                icon: Icon(Icons.view_list_rounded),
                label: Text('همه با هم'),
              ),
            ],
            selected: {c.view},
            onSelectionChanged: (s) => c.setView(s.first),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                key: kSortButtonKey,
                avatar: const Icon(Icons.swap_vert_rounded, size: 18),
                label: Text('ترتیب: ${c.sort.label}'),
                onPressed: onSort,
              ),
              ActionChip(
                key: kFilterButtonKey,
                avatar: Badge(
                  isLabelVisible: c.hasActiveFilters,
                  smallSize: 8,
                  child: const Icon(Icons.filter_list_rounded, size: 18),
                ),
                label: const Text('فیلتر'),
                onPressed: onFilter,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const kPersonChipsKey = Key('person-chips');

/// نام نمایشی شخص («نامشخص» = کارت‌های بی‌صاحب).
String _personLabel(String person) =>
    person == kUnknownPerson ? 'کارت‌های بی‌صاحب' : person;

/// انتخاب شخص بالای صفحه: خالص/درآمد/هزینه‌ی بالا و فهرست فقط مال همان شخص می‌شود.
class _PersonChips extends StatelessWidget {
  final DashboardController controller;

  const _PersonChips({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final people = c.people;
    if (people.length < 2 && c.person == null) return const SizedBox(height: 4);
    return SizedBox(
      height: 48,
      child: ListView(
        key: kPersonChipsKey,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: ChoiceChip(
              key: const ValueKey('person-chip-all'),
              label: const Text('همه'),
              selected: c.person == null,
              onSelected: (_) => c.setPerson(null),
            ),
          ),
          for (final p in people)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                key: ValueKey('person-chip-$p'),
                label: Text(p == kUnknownPerson ? 'بی‌صاحب' : p),
                selected: c.person == p,
                onSelected: (_) => c.setPerson(c.person == p ? null : p),
              ),
            ),
        ],
      ),
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  final DashboardController controller;

  const _ActiveFilters({required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (c.kind != KindFilter.all)
            InputChip(
                label: Text(c.kind.label),
                onDeleted: () => c.setKind(KindFilter.all)),
          if (c.search.trim().isNotEmpty)
            InputChip(
                label: Text('«${c.search.trim()}»'),
                onDeleted: () => c.setSearch('')),
        ],
      ),
    );
  }
}

class _FilterSheet extends StatelessWidget {
  final DashboardController controller;

  const _FilterSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final c = controller;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('فیلتر', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              Text('نوع تراکنش', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in KindFilter.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: c.kind == k,
                      onSelected: (_) => c.setKind(k),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'برای دیدن فقط یک نفر (و جمعِ فقط او) از تراشه‌های نام بالای صفحه '
                'استفاده کن.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  TextButton(
                      onPressed: c.clearFilters,
                      child: const Text('پاک کردن همه')),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('نمایش'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const _EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

class _AddSmsSheet extends StatefulWidget {
  const _AddSmsSheet();

  @override
  State<_AddSmsSheet> createState() => _AddSmsSheetState();
}

class _AddSmsSheetState extends State<_AddSmsSheet> {
  final _senderController = TextEditingController();
  final _bodyController = TextEditingController();

  @override
  void dispose() {
    _senderController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _save() {
    final sender = _senderController.text.trim();
    final body = _bodyController.text.trim();
    if (body.isEmpty) return;
    Navigator.of(context).pop(_SmsInput(sender: sender, body: body));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('افزودن دستی پیامک بانکی', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'معمولاً لازم نیست: پیامک‌های بانکی خودکار ثبت می‌شوند. این برای '
            'پیامکی است که جای دیگری داری.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            key: kSmsSenderFieldKey,
            controller: _senderController,
            decoration:
                const InputDecoration(labelText: 'فرستنده (نام/سرشماره بانک)'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: kSmsBodyFieldKey,
            controller: _bodyController,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'متن پیامک'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: kSmsSaveButtonKey,
            onPressed: _save,
            child: const Text('خواندن و ثبت'),
          ),
        ],
      ),
    );
  }
}

class _SmsInput {
  final String sender;
  final String body;
  const _SmsInput({required this.sender, required this.body});
}
