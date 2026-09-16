/// گزارش و نمودار: خلاصه‌ی بازه، روند روزانه/ماهانه، تفکیک افراد، کارت‌ها و
/// دسته‌ها، و خروجی PDF.
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/theme/app_theme.dart';
import '../dashboard/dashboard_controller.dart';
import 'cards_report_screen.dart';
import '../transactions/data/period.dart';
import '../transactions/data/transaction_record.dart';
import '../transactions/data/transaction_repository.dart';
import '../transactions/data/tx_query.dart';
import '../transactions/widgets/period_bar.dart';
import '../transactions/widgets/summary_card.dart';
import 'pdf_report.dart';
import 'report_data.dart';

const kReportPdfKey = Key('report-pdf');
const kReportBarsKey = Key('report-bars');
const kReportSeriesKey = Key('report-series');
const kReportPeopleKey = Key('report-people');
const kReportCardsKey = Key('report-cards');
const kReportCategoriesKey = Key('report-categories');
const kReportEmptyKey = Key('report-empty');

/// پالت رنگ نمودارها (قابل تشخیص در روشن و تیره).
const List<Color> kChartPalette = [
  Color(0xFF2563EB), Color(0xFFF59E0B), Color(0xFF10B981), Color(0xFFEF4444),
  Color(0xFF8B5CF6), Color(0xFF06B6D4), Color(0xFFEC4899), Color(0xFF84CC16),
  Color(0xFFF97316), Color(0xFF6366F1), Color(0xFF14B8A6), Color(0xFFA855F7),
];

class ReportScreen extends StatefulWidget {
  final DashboardController controller;

  const ReportScreen({super.key, required this.controller});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late Period _period = widget.controller.period;
  bool _exporting = false;

  Future<void> _export(List<TransactionRecord> items, {bool preview = false}) async {
    setState(() => _exporting = true);
    try {
      final data = ReportData.from(period: _period, items: items, now: widget.controller.now);
      if (preview) {
        await PdfReport.preview(data);
      } else {
        await PdfReport.share(data);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ساخت PDF ناموفق بود: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final items = c.itemsIn(_period);
        final summary = FinanceSummary.of(items);
        final cats = categoryBreakdown(items);
        return Scaffold(
          appBar: AppBar(
            title: const Text('گزارش و نمودار'),
            actions: [
              if (_exporting)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                PopupMenuButton<bool>(
                  key: kReportPdfKey,
                  tooltip: 'خروجی PDF',
                  enabled: items.isNotEmpty,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onSelected: (preview) => _export(items, preview: preview),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: false,
                      child: ListTile(
                        leading: Icon(Icons.share_outlined),
                        title: Text('اشتراک/ذخیره‌ی PDF'),
                      ),
                    ),
                    PopupMenuItem(
                      value: true,
                      child: ListTile(
                        leading: Icon(Icons.print_outlined),
                        title: Text('پیش‌نمایش و چاپ'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              PeriodBar(
                period: _period,
                now: c.now,
                onChanged: (p) => setState(() => _period = p),
              ),
              SummaryCard(summary: summary, period: _period, count: items.length),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  key: const Key('open-cards-report'),
                  leading: const Icon(Icons.credit_card_rounded),
                  title: const Text('گزارش به‌تفکیک کارت'),
                  subtitle: const Text('موجودی و تراکنش‌های هر کارت جدا جدا'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CardsReportScreen(controller: c),
                  )),
                ),
              ),
              if (items.isEmpty)
                const _Hint(
                  key: kReportEmptyKey,
                  icon: Icons.bar_chart_rounded,
                  text: 'در این بازه تراکنشی نیست. با فلش‌های بالا ماه دیگری را ببین.',
                )
              else ...[
                const SizedBox(height: 16),
                _ChartCard(
                  key: kReportBarsKey,
                  title: _period.isAll ? 'روند ماهانه' : 'روند روزانه',
                  subtitle: 'روی ستون‌ها بزن تا مبلغ دقیق را ببینی',
                  child: _TrendChart(buckets: buildBuckets(_period, items)),
                ),
                const SizedBox(height: 12),
                _ChartCard(
                  key: kReportPeopleKey,
                  title: 'هزینه به تفکیک افراد',
                  child: _BreakdownBars(entries: breakdown(items, personOf)),
                ),
                const SizedBox(height: 12),
                _ChartCard(
                  key: kReportCardsKey,
                  title: 'هزینه به تفکیک کارت‌ها',
                  child: _BreakdownBars(
                    entries: breakdown(items, (t) => '${personOf(t)} — ${cardTitleOf(t)}'),
                  ),
                ),
                const SizedBox(height: 12),
                _ChartCard(
                  key: kReportCategoriesKey,
                  title: 'هزینه به تفکیک دسته',
                  child: cats.isEmpty
                      ? _Hint(
                          icon: Icons.label_outline_rounded,
                          text: 'هنوز هزینه‌ای در این بازه دسته‌بندی نشده.'
                              '${c.categorizeFrom == null ? '' : ' دسته‌بندی از ${formatJalaliDate(c.categorizeFrom!)} شروع می‌شود.'}',
                        )
                      : _CategoryPie(entries: cats),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _ChartCard({super.key, required this.title, required this.child, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null)
              Text(subtitle!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

enum _Series { expense, income }

/// روند روزانه/ماهانه‌ی هزینه یا درآمد (جدا؛ چون یک حقوقِ بزرگ، ستون‌های
/// هزینه‌ی روزانه را در یک نمودار مشترک ناپیدا می‌کرد).
class _TrendChart extends StatefulWidget {
  final List<ChartBucket> buckets;

  const _TrendChart({required this.buckets});

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  _Series? _series;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fin = FinanceColors.of(context);
    final buckets = widget.buckets;
    final hasExpense = buckets.any((b) => b.expenseRial > 0);
    final series = _series ?? (hasExpense ? _Series.expense : _Series.income);
    final isExpense = series == _Series.expense;
    final label = isExpense ? 'هزینه' : 'درآمد';
    final color = isExpense ? fin.expense : fin.income;
    int valueOf(ChartBucket b) => isExpense ? b.expenseRial : b.incomeRial;

    final n = buckets.length;
    final maxRial = buckets.fold<int>(0, (m, b) => math.max(m, valueOf(b)));
    ChartBucket? peak;
    for (final b in buckets) {
      if (valueOf(b) > 0 && (peak == null || valueOf(b) > valueOf(peak))) peak = b;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_Series>(
          key: kReportSeriesKey,
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: _Series.expense, label: Text('هزینه')),
            ButtonSegment(value: _Series.income, label: Text('درآمد')),
          ],
          selected: {series},
          onSelectionChanged: (s) => setState(() => _series = s.first),
        ),
        const SizedBox(height: 16),
        if (maxRial == 0)
          _Hint(icon: Icons.bar_chart_rounded, text: 'در این بازه $label ثبت نشده.')
        else ...[
          _bars(context, buckets, valueOf, color, maxRial, label),
          if (peak != null) ...[
            const SizedBox(height: 8),
            Text(
              'بیشترین $label: ${peak.fullLabel} — ${formatToman(valueOf(peak))}',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
        if (n == 0) const SizedBox.shrink(),
      ],
    );
  }

  Widget _bars(
    BuildContext context,
    List<ChartBucket> buckets,
    int Function(ChartBucket) valueOf,
    Color color,
    int maxRial,
    String label,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final n = buckets.length;
    final maxY = maxRial / 10 * 1.15; // تومان
    final rodWidth = n > 20 ? 6.0 : (n > 8 ? 14.0 : 20.0);
    final labelEvery = n > 20 ? 5 : 1;
    // راست‌به‌چپ: ستونِ اول (روز ۱ / قدیمی‌ترین ماه) سمت راست نمودار.
    final ordered = buckets.reversed.toList();
    final labelStyle = TextStyle(
      fontSize: 10,
      color: scheme.onSurfaceVariant,
      fontFamily: kAppFontFamily,
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        height: 190,
        child: BarChart(
          BarChartData(
            maxY: maxY,
            alignment: BarChartAlignment.spaceBetween,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
              getDrawingHorizontalLine: (_) => FlLine(
                color: scheme.outlineVariant.withOpacity(0.6),
                strokeWidth: 0.7,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= n) return const SizedBox.shrink();
                    if ((n - 1 - i) % labelEvery != 0) return const SizedBox.shrink();
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      space: 4,
                      child: Text(ordered[i].label, style: labelStyle),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final b = ordered[group.x];
                  return BarTooltipItem(
                    '${b.fullLabel}\n$label: ${formatToman(valueOf(b))}',
                    TextStyle(
                      color: scheme.onInverseSurface,
                      fontSize: 12,
                      fontFamily: kAppFontFamily,
                    ),
                    textDirection: TextDirection.rtl,
                  );
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < n; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: valueOf(ordered[i]) / 10,
                      color: color,
                      width: rodWidth,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BreakdownBars extends StatelessWidget {
  final List<BreakdownEntry> entries;
  final List<Color>? colors;

  const _BreakdownBars({required this.entries, this.colors});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fin = FinanceColors.of(context);
    final withExpense = entries.where((e) => e.expenseRial > 0).toList();
    if (withExpense.isEmpty) {
      return const _Hint(icon: Icons.info_outline_rounded, text: 'هزینه‌ای در این بازه نیست.');
    }
    final max = withExpense.first.expenseRial;
    return Column(
      children: [
        for (var i = 0; i < withExpense.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(withExpense[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium),
                  ),
                  Text(formatToman(withExpense[i].expenseRial),
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: max == 0 ? 0 : withExpense[i].expenseRial / max,
                  minHeight: 8,
                  color: colors == null ? fin.expense : colors![i % colors!.length],
                  backgroundColor: theme.colorScheme.surfaceContainerHigh,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${toPersianDigits('${withExpense[i].count}')} تراکنش'
                '${withExpense[i].incomeRial > 0 ? ' • درآمد ${formatToman(withExpense[i].incomeRial)}' : ''}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CategoryPie extends StatelessWidget {
  final List<BreakdownEntry> entries;

  const _CategoryPie({required this.entries});

  @override
  Widget build(BuildContext context) {
    final sum = entries.fold<int>(0, (a, e) => a + e.expenseRial);
    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 42,
              sections: [
                for (var i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: entries[i].expenseRial.toDouble(),
                    color: kChartPalette[i % kChartPalette.length],
                    radius: 52,
                    title: () {
                      final pct = sum == 0 ? 0 : (entries[i].expenseRial * 100 / sum).round();
                      return pct >= 6 ? '${toPersianDigits('$pct')}٪' : '';
                    }(),
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontFamily: kAppFontFamily,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _BreakdownBars(entries: entries, colors: kChartPalette),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Hint({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Icon(icon, size: 36, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
