/// گزارش هزینه به‌تفکیک دسته، با بازه‌ی روز/هفته/ماه/کل + نوار نسبت.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../dashboard/dashboard_controller.dart';
import '../reports/pdf_report.dart';
import 'data/category.dart';

/// پالت رنگ برای دسته‌ها در نمودار.
const List<Color> _palette = [
  Color(0xFF0D9488), Color(0xFFF59E0B), Color(0xFFEF4444), Color(0xFF3B82F6),
  Color(0xFF8B5CF6), Color(0xFF10B981), Color(0xFFEC4899), Color(0xFF14B8A6),
  Color(0xFFF97316), Color(0xFF6366F1), Color(0xFF84CC16), Color(0xFF06B6D4),
];

const kReportPeriodDay = Key('report-day');
const kReportTotalKey = Key('report-total');

enum _Period { day, week, month, all }

class CategoryReportScreen extends StatefulWidget {
  final DashboardController controller;

  const CategoryReportScreen({super.key, required this.controller});

  @override
  State<CategoryReportScreen> createState() => _CategoryReportScreenState();
}

class _CategoryReportScreenState extends State<CategoryReportScreen> {
  _Period _period = _Period.month;
  late Future<List<CategoryTotal>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  DateTime? _fromFor(_Period p) {
    final now = DateTime.now();
    switch (p) {
      case _Period.day:
        return DateTime(now.year, now.month, now.day);
      case _Period.week:
        return now.subtract(const Duration(days: 7));
      case _Period.month:
        return now.subtract(const Duration(days: 30));
      case _Period.all:
        return null;
    }
  }

  void _reload() {
    _future = widget.controller.categoryTotals(from: _fromFor(_period));
  }

  String get _periodLabel => switch (_period) {
        _Period.day => 'امروز',
        _Period.week => 'هفته‌ی اخیر',
        _Period.month => 'ماه اخیر',
        _Period.all => 'کل',
      };

  Future<void> _exportPdf() async {
    final totals = await widget.controller.categoryTotals(from: _fromFor(_period));
    if (totals.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('در این بازه هزینه‌ای برای خروجی نیست.')),
        );
      }
      return;
    }
    final sum = totals.fold<int>(0, (a, t) => a + t.amountRial);
    await PdfReport.shareCategoryReport(
      periodLabel: _periodLabel,
      totals: totals,
      totalRial: sum,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارش دسته‌ها'),
        actions: [
          IconButton(
            key: const Key('report-pdf'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'خروجی PDF',
            onPressed: _exportPdf,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<_Period>(
              key: kReportPeriodDay,
              segments: const [
                ButtonSegment(value: _Period.day, label: Text('امروز')),
                ButtonSegment(value: _Period.week, label: Text('هفته')),
                ButtonSegment(value: _Period.month, label: Text('ماه')),
                ButtonSegment(value: _Period.all, label: Text('کل')),
              ],
              selected: {_period},
              onSelectionChanged: (s) => setState(() {
                _period = s.first;
                _reload();
              }),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CategoryTotal>>(
              future: _future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final totals = snapshot.data!;
                if (totals.isEmpty) {
                  return const Center(child: Text('در این بازه هزینه‌ای ثبت نشده.'));
                }
                final sum =
                    totals.fold<int>(0, (a, t) => a + t.amountRial);
                final max = totals.first.amountRial;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    Card(
                      child: ListTile(
                        title: const Text('جمع کل هزینه'),
                        trailing: Text(
                          formatToman(sum),
                          key: kReportTotalKey,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    if (sum > 0) ...[
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            height: 200,
                            child: PieChart(
                              PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 48,
                                sections: [
                                  for (var i = 0; i < totals.length; i++)
                                    PieChartSectionData(
                                      value: totals[i].amountRial.toDouble(),
                                      color: _palette[i % _palette.length],
                                      title:
                                          '${(totals[i].amountRial * 100 / sum).round()}%',
                                      radius: 60,
                                      titleStyle: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    for (var i = 0; i < totals.length; i++)
                      _CategoryBar(
                        name: totals[i].name,
                        amountRial: totals[i].amountRial,
                        fraction: max == 0 ? 0 : totals[i].amountRial / max,
                        color: _palette[i % _palette.length],
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final String name;
  final int amountRial;
  final double fraction;
  final Color color;

  const _CategoryBar({
    required this.name,
    required this.amountRial,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(name),
                ],
              ),
              Text(formatToman(amountRial),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 10,
              color: color,
              backgroundColor: color.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }
}
