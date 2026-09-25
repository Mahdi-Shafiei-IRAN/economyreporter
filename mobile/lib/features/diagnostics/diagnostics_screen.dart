/// صفحه‌ی «عیب‌یابی»: چرا موجودی این عدد است و هر پیامک چرا شمرده شد/نشد.
///
/// سه زبانه:
///   ۱) موجودی: عددِ کارتِ خلاصه کارت به کارت، کنارِ موجودیِ آخرِ دوره طبق بانک.
///   ۲) زنجیره‌ی مانده: هر پیامک با «مانده‌ی قبلی ± مبلغ» سنجیده و علتِ ناجوری گفته می‌شود.
///   ۳) پیامک‌ها: سرنوشتِ هر پیامکِ فرستنده‌ی مجاز + پیش‌نمایشِ قانونِ پیشنهادی.
/// کنارِ هر مشکل دکمه‌ی «درستش کن» هست (نوع، برگرداندن، حذف، یکی کردنِ حساب، ثبت)؛
/// با لمسِ یک تراکنش هم برگه‌ی جزئیات (ویرایش/حذف) باز می‌شود.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/diagnostics/balance_breakdown.dart';
import '../../core/diagnostics/balance_chain.dart';
import '../../core/diagnostics/device_health.dart';
import '../../core/diagnostics/diagnostic_report.dart';
import '../../core/diagnostics/sms_diagnosis.dart';
import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/sms/models.dart';
import '../../core/sms/sms_importer.dart';
import '../../core/theme/app_theme.dart';
import '../dashboard/dashboard_controller.dart';
import 'health_view.dart';
import '../senders/senders_screen.dart';
import '../transactions/data/period.dart';
import '../transactions/data/transaction_record.dart';
import '../transactions/transaction_details_sheet.dart';

const kDiagCopyKey = Key('diag-copy');
const kDiagBalanceDiffKey = Key('diag-balance-diff');
const kDiagSmsListKey = Key('diag-sms-list');
const kDiagRepairKey = Key('diag-repair');
const kDiagImportAllKey = Key('diag-import-all');
const kDiagRestoreAllKey = Key('diag-restore-all');

/// اجرای یک «درستش کن» با پیامِ نتیجه.
typedef _Run = Future<void> Function(Future<void> Function() action, String done);

String _fa(int n) => toPersianDigits('$n');

/// عنوانِ حساب با ارقام فارسی (برای نمایش).
String _title(TransactionRecord t) => toPersianDigits(diagAccountTitle(t));

String _kindLabel(String kind) => switch (kind) {
      'income' => 'واریز',
      'expense' => 'برداشت',
      'transfer' => 'انتقال',
      _ => 'نامشخص',
    };

class DiagnosticsScreen extends StatefulWidget {
  final DashboardController controller;
  final int initialTab;

  const DiagnosticsScreen({super.key, required this.controller, this.initialTab = 0});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late Future<SmsDiagnosisReport> _sms = widget.controller.diagnoseSmsMessages();
  late Future<DeviceHealthReport> _health = _healthOf(_sms);

  DashboardController get _c => widget.controller;

  /// حکمِ کلی از همان عیب‌یابیِ پیامک (دوباره خوانده نمی‌شود) و فرستادنش برای مدیرِ خانواده.
  Future<DeviceHealthReport> _healthOf(Future<SmsDiagnosisReport> sms) async {
    final h = await _c.deviceHealth(sms: await sms);
    _c.reportHealthIfDue(health: h).ignore();
    return h;
  }

  Future<void> _copyReport() async {
    SmsDiagnosisReport? sms;
    try {
      sms = await _sms;
    } catch (_) {
      // بدون بخشِ پیامک
    }
    final text = _c.diagnosticReportText(sms: sms);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('گزارش کپی شد (شماره‌ی کارت/حساب پوشانده شده). '
          'قبل از فرستادن یک بار بخوانش.'),
    ));
  }

  /// پیامک‌ها را دوباره بررسی کن (setState نباید Future برگرداند).
  void _refreshSms() => setState(() {
        _sms = _c.diagnoseSmsMessages();
        _health = _healthOf(_sms);
      });

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      _refreshSms();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('نشد: $e')));
    }
  }

  Future<void> _openTx(TransactionRecord t) async {
    await showTransactionDetails(context, _c, t);
    if (mounted) _refreshSms();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('عیب‌یابی موجودی و پیامک‌ها'),
          actions: [
            IconButton(
              key: kDiagCopyKey,
              tooltip: 'کپیِ گزارش برای فرستادن',
              icon: const Icon(Icons.copy_all_rounded),
              onPressed: _copyReport,
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(text: 'موجودی'),
            Tab(text: 'زنجیره‌ی مانده'),
            Tab(text: 'پیامک‌ها'),
          ]),
        ),
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final chains = _c.balanceChains();
            return TabBarView(children: [
              _BalanceTab(
                  controller: _c,
                  breakdown: _c.balanceBreakdown(),
                  chains: chains,
                  health: _health,
                  run: _run),
              _ChainTab(controller: _c, report: chains, onOpen: _openTx, run: _run),
              _SmsTab(controller: _c, future: _sms, onOpen: _openTx, run: _run),
            ]);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// کمکی‌های مشترک
// ---------------------------------------------------------------------------

class _Intro extends StatelessWidget {
  final String title;
  final List<String> lines;
  const _Intro({required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer.withOpacity(0.6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            for (final l in lines) ...[
              const SizedBox(height: 6),
              Text(l, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  final String text;
  final Widget? action;
  const _Warning(this.text, {this.action});

  @override
  Widget build(BuildContext context) {
    final fin = FinanceColors.of(context);
    return Card(
      color: fin.warningContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded, color: fin.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text, style: TextStyle(color: fin.warning)),
                  if (action != null) action!,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bold;
  final Key? valueKey;
  const _Row(this.label, this.value, {this.color, this.bold = false, this.valueKey});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: color,
          fontWeight: bold ? FontWeight.w700 : null,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, key: valueKey, style: style),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  const _Tag(this.text, {required this.color, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    );
  }
}

/// یک دکمه‌ی کوچکِ «درستش کن».
Widget _fixButton(String label, VoidCallback onPressed, {Key? key, IconData? icon}) =>
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon ?? Icons.build_circle_outlined, size: 18),
        label: Text(label),
      ),
    );

List<Widget> _splitWarnings(
        BalanceChainReport chains, DashboardController c, _Run run) =>
    [
      for (final (i, h) in chains.splitHints.indexed)
        _Warning(
          '«${_title(h.a.sample)}» و «${_title(h.b.sample)}» '
          'احتمالاً یک حساب‌اند (مانده‌هایشان در ${_fa(h.consistent)} از '
          '${_fa(h.switches)} جابه‌جایی دقیقاً پشتِ هم جور است). برنامه آن‌ها را '
          'دو کارتِ جدا می‌شمارد، پس موجودیِ این حساب دو بار جمع می‌شود.',
          action: _fixButton(
            'یکی کن: همه به «${_title(h.keep.sample)}»',
            () => run(() => c.mergeAccounts(h), 'دو گروه یک حساب شدند'),
            key: Key('diag-merge-$i'),
            icon: Icons.merge_rounded,
          ),
        ),
    ];

// ---------------------------------------------------------------------------
// ۱) موجودی
// ---------------------------------------------------------------------------

class _BalanceTab extends StatelessWidget {
  final DashboardController controller;
  final BalanceBreakdown breakdown;
  final BalanceChainReport chains;
  final Future<DeviceHealthReport> health;
  final _Run run;

  const _BalanceTab({
    required this.controller,
    required this.breakdown,
    required this.chains,
    required this.health,
    required this.run,
  });

  @override
  Widget build(BuildContext context) {
    final fin = FinanceColors.of(context);
    final b = breakdown;
    final diff = b.diffRial;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FutureBuilder<DeviceHealthReport>(
          future: health,
          builder: (context, snap) => snap.hasData
              ? HealthReportCard(
                  key: kHealthCardKey, report: snap.data!, title: 'وضعیتِ کلیِ این گوشی')
              : const SizedBox.shrink(),
        ),
        const _Intro(
          title: 'این عدد از کجا آمده؟',
          lines: [
            'کارتِ خلاصه می‌گوید: موجودیِ اولِ دوره + درآمد − هزینه. «موجودیِ اول دوره» از '
                '«مانده»ی آخرین پیامکِ بانک قبل از شروعِ دوره خوانده می‌شود.',
            'اینجا کنارش «موجودیِ آخرِ دوره طبق مانده‌ی خودِ بانک» هم هست. اگر اختلاف صفر '
                'نباشد، یعنی تراکنش‌های این دوره با بانک نمی‌خوانند؛ کارتِ دارای اختلاف را '
                'پیدا کن و علتش را در «زنجیره‌ی مانده» ببین.',
          ],
        ),
        if (controller.hasActiveFilters)
          const _Warning('فیلترِ نوع/جستجو روشن است؛ کارتِ خلاصه با فیلتر حساب می‌شود ولی '
              'این جدول بدون فیلتر است.'),
        _RepairCard(controller: controller, run: run),
        if (b.period.isAll)
          const _Warning('برای «همه‌ی زمان‌ها» موجودیِ اول دوره صفر فرض می‌شود، پس «اختلاف» '
              'یعنی پولی که از قبل در حساب بوده؛ برای عددِ معنادار یک ماه را انتخاب کن.'),
        ..._splitWarnings(chains, controller, run),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Text('${b.period.title}${controller.person == null ? '' : ' • ${controller.person}'}',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                _Row('موجودیِ اولِ دوره', formatToman(b.openingRial)),
                _Row('+ درآمد', formatToman(b.incomeRial), color: fin.income),
                _Row('− هزینه', formatToman(b.expenseRial), color: fin.expense),
                const Divider(),
                _Row('کارتِ خلاصه نشان می‌دهد', formatToman(b.expectedClosingRial), bold: true),
                _Row('آخرِ دوره طبق مانده‌ی بانک', formatToman(b.bankClosingRial), bold: true),
                _Row(
                  diff == 0 ? 'اختلاف: ندارد ✓' : 'اختلاف (بانک − کارتِ خلاصه)',
                  formatToman(diff),
                  color: diff == 0 ? fin.income : fin.expense,
                  bold: true,
                  valueKey: kDiagBalanceDiffKey,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final c in b.cards) _CardBalanceTile(card: c, period: b.period),
        if (b.cards.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('تراکنشی نیست.')),
          ),
      ],
    );
  }
}

/// نتیجه‌ی تعمیرِ خودکار + «اعمال دوباره‌ی قانون‌ها».
class _RepairCard extends StatelessWidget {
  final DashboardController controller;
  final _Run run;
  const _RepairCard({required this.controller, required this.run});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = controller.lastRepair;
    final lines = r == null
        ? ['هنوز اجرا نشده.']
        : [
            'آخرین اجرا: ${formatJalaliNumeric(r.at)} ${formatClock(r.at)}',
            if (r.adopted > 0)
              '${_fa(r.adopted)} تراکنشِ برگشته از سرور (نصبِ قبلی) به پیامک و شماره‌ی حسابشان وصل شدند',
            if (r.backfilled > 0)
              '${_fa(r.backfilled)} تراکنش شماره‌ی حساب/مانده/تاریخشان از متنِ پیامک تکمیل شد',
            if (r.removed > 0)
              '${_fa(r.removed)} تراکنشِ بی‌شماره (اعتبار کیف پول، اطلاعیه، …) یا رمز پویا کنار رفتند؛ '
                  'در «پیامک‌ها» / «در جمع نیست» قابل برگرداندن‌اند',
            if (r.imported > 0) '${_fa(r.imported)} پیامکِ تراکنشی که ثبت نشده بود وارد شد',
            if (r.revived > 0)
              '${_fa(r.revived)} تراکنشی که قبلاً خودکار کنار رفته بود، حالا با قانون می‌خواند و برگشت',
            if (r.proven > 0)
              '${_fa(r.proven)} تراکنش (کارمزد، وام، قسط، …) که شماره‌ی حساب نداشت یا حذف شده بود، '
                  'با مانده‌ی بانک ثابت شد و در همان حساب شمرده شد',
            if (!r.changedAnything) 'چیزی برای درست کردن نبود ✓',
          ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('درست کردنِ خودکار',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'قانون: پیامک فقط وقتی تراکنش است که از سرشماره‌ی مجاز باشد و شماره‌ی '
              'حساب/کارت + مبلغ + نوع داشته باشد.',
              style: theme.textTheme.bodySmall,
            ),
            for (final l in lines) Text('• $l', style: theme.textTheme.bodySmall),
            _fixButton(
              r == null ? 'اجرا' : 'اعمال دوباره‌ی قانون‌ها',
              () => run(controller.runRepair, 'قانون‌ها اعمال شد'),
              key: kDiagRepairKey,
              icon: Icons.auto_fix_high_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _CardBalanceTile extends StatelessWidget {
  final CardPeriodBalance card;
  final Period period;
  const _CardBalanceTile({required this.card, required this.period});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fin = FinanceColors.of(context);
    final c = card;
    Widget warn(String t) =>
        _Tag(t, color: fin.warning, background: fin.warningContainer);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title(c.sample),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (c.opening == null && !period.isAll)
                warn('قبل از این دوره پیامکی نیست (اول دوره = ۰)')
              else if (c.opening != null && c.opening!.isEstimate)
                warn('اول دوره تخمینی (پیامکِ مانده‌دار نبود)'),
              if (c.closingIsEstimate) warn('مانده‌ای از بانک ندارد'),
              if (!c.hasId) warn('بدون شماره کارت/حساب'),
              if (!c.hasId && c.sample.isRemote) warn('از سرور (نصبِ قبلی)'),
              if (c.uncounted.isNotEmpty)
                warn('${_fa(c.uncounted.length)} تراکنش در جمع نیست (انتقال/بازبینی)'),
            ]),
            const SizedBox(height: 6),
            _Row('اولِ دوره', formatToman(c.openingRial)),
            _Row('+ درآمد / − هزینه',
                '${formatToman(c.incomeRial, withUnit: false)} / ${formatToman(c.expenseRial)}'),
            _Row('کارتِ خلاصه', formatToman(c.expectedClosingRial)),
            _Row('طبق بانک', formatToman(c.closingRial)),
            _Row(
              c.diffRial == 0 ? 'اختلاف: ندارد ✓' : 'اختلاف',
              formatToman(c.diffRial),
              color: c.diffRial == 0 ? fin.income : fin.expense,
              bold: c.diffRial != 0,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ۲) زنجیره‌ی مانده
// ---------------------------------------------------------------------------

class _ChainTab extends StatelessWidget {
  final DashboardController controller;
  final BalanceChainReport report;
  final Future<void> Function(TransactionRecord) onOpen;
  final _Run run;

  const _ChainTab({
    required this.controller,
    required this.report,
    required this.onOpen,
    required this.run,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Intro(
          title: 'مانده‌ی بانک مرجع است',
          lines: [
            'هر پیامکِ بانک «مانده»ی حساب را می‌گوید، پس باید: مانده‌ی این پیامک = مانده‌ی '
                'پیامکِ قبلی ± مبلغ. هر جا جور نیست، مقدارِ اختلاف علت را نشان می‌دهد:',
            '• اختلاف دو برابرِ مبلغ: نوع برعکس ثبت شده (واریز به‌جای برداشت یا برعکس)\n'
                '• مانده عوض نشده: تکراری است یا اصلاً تراکنش نبوده\n'
                '• بقیه: پیامکِ جاافتاده، کارمزد/سود، یا مبلغِ اشتباه',
            'زیرِ هر مورد دکمه‌ی «درستش کن» هست؛ با لمسِ خودِ مورد هم جزئیاتِ تراکنش باز می‌شود.',
          ],
        ),
        ..._splitWarnings(report, controller, run),
        for (final a in report.accounts)
          _AccountChainCard(chain: a, controller: controller, onOpen: onOpen, run: run),
        if (report.accounts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('تراکنشی نیست.')),
          ),
      ],
    );
  }
}

class _AccountChainCard extends StatefulWidget {
  final AccountChain chain;
  final DashboardController controller;
  final Future<void> Function(TransactionRecord) onOpen;
  final _Run run;

  const _AccountChainCard({
    required this.chain,
    required this.controller,
    required this.onOpen,
    required this.run,
  });

  @override
  State<_AccountChainCard> createState() => _AccountChainCardState();
}

class _AccountChainCardState extends State<_AccountChainCard> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fin = FinanceColors.of(context);
    final a = widget.chain;
    final problems = a.problems;
    final shown = (_showAll ? a.links : problems).reversed.toList();
    final last = a.lastBalanceRial;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_title(a.sample),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              [
                if (!a.hasBalance)
                  'هیچ پیامکش مانده ندارد (قابل سنجش نیست)'
                else if (problems.isEmpty)
                  'همه‌ی ${_fa(a.links.length)} مورد جور است ✓'
                else
                  '${_fa(problems.length)} مورد ناجور از ${_fa(a.links.length)}',
                if (last != null) 'آخرین مانده: ${formatToman(last)}',
                if (!a.hasId) 'بدون شماره کارت/حساب',
              ].join(' • '),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: !a.hasBalance
                      ? fin.warning
                      : problems.isEmpty
                          ? fin.income
                          : fin.expense),
            ),
            for (final l in shown)
              _LinkTile(
                  link: l,
                  controller: widget.controller,
                  onOpen: widget.onOpen,
                  run: widget.run),
            if (a.links.length != problems.length)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(_showAll
                      ? 'فقط موارد ناجور'
                      : 'نمایش همه‌ی ${_fa(a.links.length)} پیامک'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final ChainLink link;
  final DashboardController controller;
  final Future<void> Function(TransactionRecord) onOpen;
  final _Run run;

  const _LinkTile({
    required this.link,
    required this.controller,
    required this.onOpen,
    required this.run,
  });

  /// دکمه‌ی درست کردنِ همین مورد (فقط برای صاحبِ تراکنش).
  Widget? _fix() {
    final l = link;
    final t = l.tx;
    if (!controller.canEdit(t)) return null;
    final key = Key('diag-fix-${t.id}');
    final restore = l.restoreCandidate;
    if (restore != null) {
      return _fixButton(
        'برگرداندنِ ${_kindLabel(restore.kind)} ${formatToman(restore.amountRial ?? 0)} '
        'که حذف شده بود',
        () => run(() => controller.restoreTransaction(restore), 'تراکنش برگشت'),
        key: key,
        icon: Icons.restore_rounded,
      );
    }
    switch (l.status) {
      case ChainStatus.signFlipped:
      case ChainStatus.kindSuggested:
        final kind = l.suggestedKind!;
        return _fixButton('ثبت به‌عنوانِ ${_kindLabel(kind)}',
            () => run(() => controller.fixKind(t, kind), 'نوع اصلاح شد'),
            key: key);
      case ChainStatus.noEffect:
        return _fixButton('حذف (تکراری/غیرتراکنش)',
            () => run(() => controller.deleteTransaction(t.id), 'حذف شد'),
            key: key, icon: Icons.delete_outline_rounded);
      case ChainStatus.mismatch:
        final diff = l.diffRial!;
        return _fixButton(
          'ثبتِ دستیِ ${diff < 0 ? 'برداشت' : 'واریزِ'} جاافتاده‌ی ${formatToman(diff.abs())}',
          () => run(() => controller.addMissingBefore(t, diff), 'ثبت شد'),
          key: key,
          icon: Icons.add_circle_outline_rounded,
        );
      default:
        return null;
    }
  }

  String _explain() {
    final l = link;
    final prev = l.previousBalanceRial == null ? '' : formatToman(l.previousBalanceRial!);
    final actual = l.actualBalanceRial == null ? '' : formatToman(l.actualBalanceRial!);
    return switch (l.status) {
      ChainStatus.start => 'اولین مانده: $actual',
      ChainStatus.ok => 'مانده از $prev به $actual',
      ChainStatus.noBalance => 'این پیامک مانده نداشت',
      ChainStatus.signFlipped =>
        'بانک می‌گوید ${_kindLabel(l.suggestedKind!)} بوده: مانده از $prev به $actual',
      ChainStatus.noEffect => 'مانده قبل و بعد هر دو $actual است',
      ChainStatus.kindSuggested =>
        'مانده نشان می‌دهد ${_kindLabel(l.suggestedKind!)} بوده: از $prev به $actual',
      ChainStatus.outOfOrder => 'زمانش با پیامکِ کناری جابه‌جاست',
      ChainStatus.mismatch => 'انتظار ${formatToman(l.expectedBalanceRial!)} ولی بانک '
          '$actual (اختلاف ${formatToman(l.diffRial!)}): پیامکِ جاافتاده، کارمزد/سود یا '
          'مبلغِ اشتباه',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fin = FinanceColors.of(context);
    final t = link.tx;
    final problem = link.status.isProblem;
    final color = problem ? fin.expense : fin.income;
    final fix = problem ? _fix() : null;
    return InkWell(
      onTap: () => onOpen(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(problem ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_kindLabel(t.kind)}${t.needsReview ? ' (بازبینی)' : ''} '
                    '${t.amountRial == null ? '؟' : formatToman(t.amountRial!)} • '
                    '${formatShortDateTime(t.effectiveTime)}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text('${link.status.label} — ${_explain()}',
                      style: theme.textTheme.bodySmall?.copyWith(color: color)),
                  if (t.smsBody != null && controller.showSmsText)
                    Text(t.smsBody!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  if (fix != null) fix,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ۳) پیامک‌ها
// ---------------------------------------------------------------------------

enum _SmsFilter { all, counted, notCounted, rejected, strictDrops }

extension on _SmsFilter {
  String get label => switch (this) {
        _SmsFilter.all => 'همه',
        _SmsFilter.counted => 'شمرده‌شده',
        _SmsFilter.notCounted => 'در جمع نیست',
        _SmsFilter.rejected => 'ردشده/ثبت‌نشده',
        _SmsFilter.strictDrops => 'خلافِ قانون',
      };

  bool matches(SmsDiagnosis d) => switch (this) {
        _SmsFilter.all => true,
        _SmsFilter.counted => d.verdict == SmsVerdict.counted,
        _SmsFilter.notCounted => d.verdict == SmsVerdict.transfer ||
            d.verdict == SmsVerdict.review ||
            d.verdict == SmsVerdict.deleted ||
            d.verdict == SmsVerdict.duplicate,
        _SmsFilter.rejected => !d.verdict.isStored &&
            d.verdict != SmsVerdict.deleted &&
            d.verdict != SmsVerdict.duplicate,
        _SmsFilter.strictDrops => d.droppedByStrict,
      };
}

class _SmsTab extends StatefulWidget {
  final DashboardController controller;
  final Future<SmsDiagnosisReport> future;
  final Future<void> Function(TransactionRecord) onOpen;
  final _Run run;

  const _SmsTab({
    required this.controller,
    required this.future,
    required this.onOpen,
    required this.run,
  });

  @override
  State<_SmsTab> createState() => _SmsTabState();
}

class _SmsTabState extends State<_SmsTab> {
  _SmsFilter _filter = _SmsFilter.all;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SmsDiagnosisReport>(
      future: widget.future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('خواندنِ پیامک‌ها نشد: ${snap.error}'));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final r = snap.data!;
        final items = [for (final d in r.items) if (_filter.matches(d)) d];
        // حذف‌شده‌هایی که شماره حساب/کارت + مبلغ + نوع دارند و تکراری نیستند (مثلاً با
        // «بردار و تراکنش‌هایش را حذف کن» در نسخه‌های قبل رفته بودند).
        final restorable = widget.controller.restorableDeleted(r);
        final header = <Widget>[
          const _Intro(
            title: 'هر پیامک چرا شمرده شد یا نشد',
            lines: [
              'فقط پیامکِ فرستنده‌های مجاز بررسی می‌شود. برای هر پیامک می‌بینی برنامه چه '
                  'خوانده (نوع، مبلغ، مانده، حساب) و آخرش چه شد.',
              'قانون: پیامک فقط وقتی تراکنش است که از سرشماره‌ی مجاز باشد و شماره حساب/کارت '
                  '+ مبلغ + نوع (واریز/برداشت) داشته باشد. اگر پیامکی اشتباهی رد یا حذف شده، '
                  'زیرش «برگرداندن» یا «ثبت کن» هست.',
            ],
          ),
          if (!r.inboxRead)
            const _Warning('صندوقِ پیامکِ گوشی خوانده نشد (مجوز؟)؛ فقط تراکنش‌هایی که قبلاً '
                'ثبت شده‌اند بررسی شدند.'),
          _SmsSummary(report: r),
          if (r.count(SmsVerdict.notImported) > 0)
            _fixButton(
              'واردکردنِ ${_fa(r.count(SmsVerdict.notImported))} پیامکِ تراکنشی که ثبت نشده',
              () => widget.run(
                  () => widget.controller.importMissing([
                        for (final d in r.items)
                          if (d.verdict == SmsVerdict.notImported) _raw(d),
                      ]),
                  'وارد شدند'),
              key: kDiagImportAllKey,
              icon: Icons.download_rounded,
            ),
          if (restorable.isNotEmpty)
            _fixButton(
              'برگرداندنِ ${_fa(restorable.length)} پیامکِ حذف‌شده که با قانون می‌خوانند',
              () => widget.run(
                  () => widget.controller.restoreMany(restorable), 'برگشتند'),
              key: kDiagRestoreAllKey,
              icon: Icons.restore_rounded,
            ),
          if (r.notAllowedWithAmount.isNotEmpty)
            _NotAllowedCard(report: r, controller: widget.controller),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final f in _SmsFilter.values)
                ChoiceChip(
                  label: Text(f.label),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ]),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('موردی نیست.')),
            ),
        ];
        return ListView.builder(
          key: kDiagSmsListKey,
          padding: const EdgeInsets.all(16),
          itemCount: header.length + items.length,
          itemBuilder: (context, i) => i < header.length
              ? header[i]
              : _SmsTile(
                  d: items[i - header.length],
                  controller: widget.controller,
                  onOpen: widget.onOpen,
                  run: widget.run),
        );
      },
    );
  }
}

RawSms _raw(SmsDiagnosis d) => RawSms(sender: d.sender, body: d.body, receivedAt: d.at);

class _SmsSummary extends StatelessWidget {
  final SmsDiagnosisReport report;
  const _SmsSummary({required this.report});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fin = FinanceColors.of(context);
    final r = report;
    final drops = r.droppedByStrictCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_fa(r.items.length)} پیامک از فرستنده‌های مجاز',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final v in SmsVerdict.values)
                if (r.count(v) > 0)
                  _Tag('${v.label}: ${_fa(r.count(v))}',
                      color: theme.colorScheme.onSurfaceVariant,
                      background: theme.colorScheme.surfaceContainerHighest),
            ]),
            const SizedBox(height: 8),
            Text(
              drops == 0
                  ? 'همه‌ی تراکنش‌های ثبت‌شده با قانون می‌خوانند ✓'
                  : '${_fa(drops)} تراکنشِ ثبت‌شده با قانون نمی‌خواند (پیش از قانون ثبت شده؛ '
                      'فیلترِ «خلافِ قانون» را ببین یا در «موجودی» قانون‌ها را اعمال کن).',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: drops == 0 ? fin.income : fin.warning),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotAllowedCard extends StatelessWidget {
  final SmsDiagnosisReport report;
  final DashboardController controller;
  const _NotAllowedCard({required this.report, required this.controller});

  @override
  Widget build(BuildContext context) {
    final entries = report.notAllowedWithAmount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('پیامکِ مبلغ‌دار از فرستنده‌هایی که مجاز نیستند (ثبت نمی‌شوند):'),
            const SizedBox(height: 4),
            Text(entries.map((e) => '${e.key} (${_fa(e.value)})').join('، '),
                style: Theme.of(context).textTheme.bodySmall),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SendersScreen(controller: controller))),
                child: const Text('فرستنده‌های پیامک بانک'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmsTile extends StatelessWidget {
  final SmsDiagnosis d;
  final DashboardController controller;
  final Future<void> Function(TransactionRecord) onOpen;
  final _Run run;
  const _SmsTile({
    required this.d,
    required this.controller,
    required this.onOpen,
    required this.run,
  });

  /// دکمه‌ی درست کردن برای این پیامک (اگر لازم باشد).
  Widget? _fix() {
    final stored = d.stored;
    final key = Key('diag-sms-fix-${stored?.id ?? '${d.sender}|${d.at?.millisecondsSinceEpoch}'}');
    switch (d.verdict) {
      case SmsVerdict.deleted:
        if (stored == null || !controller.canEdit(stored)) return null;
        return _fixButton('برگرداندن',
            () => run(() => controller.restoreTransaction(stored), 'تراکنش برگشت'),
            key: key, icon: Icons.restore_rounded);
      case SmsVerdict.notImported:
        return _fixButton('ثبت',
            () => run(() => controller.importMissing([_raw(d)]), 'ثبت شد'),
            key: key, icon: Icons.download_rounded);
      case SmsVerdict.noId || SmsVerdict.unknownKind || SmsVerdict.noAmount:
        if (d.parsed.amountRial == null || d.parsed.kind == TxKind.unknown) return null;
        return _fixButton('این تراکنش است؛ ثبت کن',
            () => run(() => controller.saveAnyway(d), 'ثبت شد'),
            key: key, icon: Icons.add_task_rounded);
      default:
        if (d.droppedByStrict && stored != null && controller.canEdit(stored)) {
          return _fixButton('حذف (خلافِ قانون)',
              () => run(() => controller.deleteTransaction(stored.id), 'حذف شد'),
              key: key, icon: Icons.delete_outline_rounded);
        }
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fin = FinanceColors.of(context);
    final p = d.parsed;
    final (vColor, vBg) = switch (d.verdict) {
      SmsVerdict.counted => (fin.income, fin.incomeContainer),
      SmsVerdict.transfer ||
      SmsVerdict.review ||
      SmsVerdict.duplicate ||
      SmsVerdict.deleted =>
        (fin.transfer, fin.transferContainer),
      _ => (fin.warning, fin.warningContainer),
    };
    final stored = d.stored;
    final open = stored != null && !stored.isDeleted;
    final parsedLine = [
      'خوانده شد: ${_kindLabel(p.kind.name)}',
      p.amountRial == null ? 'بی‌مبلغ' : formatToman(p.amountRial!),
      if (p.balanceAfterRial != null) 'مانده ${formatToman(p.balanceAfterRial!)}',
      if (p.accountRef != null) 'حساب ${toPersianDigits(p.accountRef!)}',
      if (p.cardLast4 != null) 'کارت ${toPersianDigits(p.cardLast4!)}',
      if (p.bankName != null) p.bankName!,
    ].join(' • ');
    final fix = _fix();
    final storedDiffers = stored != null &&
        (stored.kind != p.kind.name || stored.amountRial != p.amountRial);
    return Card(
      child: InkWell(
        onTap: open ? () => onOpen(stored) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 6, runSpacing: 4, children: [
                _Tag(d.verdict.label, color: vColor, background: vBg),
                d.strict.accepts
                    ? _Tag(d.strict.byBalance ? 'قانون: قبول (حساب از مانده‌ی بانک)' : 'قانون: قبول',
                        color: fin.income, background: fin.incomeContainer)
                    : _Tag('قانون: رد — ${d.strict.missing.join('، ')}',
                        color: fin.expense, background: fin.expenseContainer),
                if (!d.inInbox)
                  _Tag('در صندوق نیست',
                      color: theme.colorScheme.onSurfaceVariant,
                      background: theme.colorScheme.surfaceContainerHighest),
              ]),
              const SizedBox(height: 6),
              Text(
                '${d.sender}${d.at == null ? '' : ' • ${formatJalaliNumeric(d.at!)} ${formatClock(d.at!)}'}',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Text(d.body, style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(parsedLine,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (storedDiffers)
                Text(
                  'ثبت‌شده (ویرایش‌شده): ${_kindLabel(stored.kind)} '
                  '${stored.amountRial == null ? '' : formatToman(stored.amountRial!)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: fin.transfer),
                ),
              if (fix != null) fix,
            ],
          ),
        ),
      ),
    );
  }
}
