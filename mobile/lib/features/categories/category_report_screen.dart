/// گزارش هزینه به‌تفکیک دسته، با بازه‌ی روز/هفته/ماه/کل + نوار نسبت.
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../dashboard/dashboard_controller.dart';
import 'data/category.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش دسته‌ها')),
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
                    const SizedBox(height: 8),
                    for (final t in totals)
                      _CategoryBar(
                        name: t.name,
                        amountRial: t.amountRial,
                        fraction: max == 0 ? 0 : t.amountRial / max,
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

  const _CategoryBar({
    required this.name,
    required this.amountRial,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name),
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
              backgroundColor: color.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }
}
