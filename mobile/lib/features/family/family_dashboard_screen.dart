/// داشبورد خانواده از سرور: جمع کل + تفکیک عضو/دسته/کارت، برای بازه‌ی انتخاب‌شده.
///
/// این صفحه جمعِ کلِ خانواده را از سرور می‌گیرد (نه فقط دادهٔ همین گوشی)، پس برای
/// عضوی که جزئیاتِ بقیه را ندارد هم «جمعِ خانواده» را نشان می‌دهد.
library;

import 'package:flutter/material.dart';

import '../../core/dashboard/dashboard_summary.dart';
import '../../core/dashboard/remote_dashboard_api.dart';
import '../../core/format/money_format.dart';
import '../transactions/data/period.dart';
import '../transactions/widgets/period_bar.dart';

const kFamilyLoadingKey = Key('family-loading');
const kFamilyErrorKey = Key('family-error');
const kFamilyIncomeKey = Key('family-income');
const kFamilyExpenseKey = Key('family-expense');
const kFamilyBalanceKey = Key('family-balance');

class FamilyDashboardScreen extends StatefulWidget {
  final RemoteDashboardApi api;
  final Period initialPeriod;
  final DateTime now;

  const FamilyDashboardScreen({
    super.key,
    required this.api,
    required this.initialPeriod,
    required this.now,
  });

  @override
  State<FamilyDashboardScreen> createState() => _FamilyDashboardScreenState();
}

class _FamilyDashboardScreenState extends State<FamilyDashboardScreen> {
  late Period _period = widget.initialPeriod;
  late Future<DashboardSummary> _future = _fetch();

  Future<DashboardSummary> _fetch() => widget.api.fetchSummary(
        from: _period.from,
        // بازه‌ی انحصاری است؛ یک ثانیه عقب می‌کشیم تا اول ماهِ بعد جزو این ماه نشود.
        to: _period.to?.subtract(const Duration(seconds: 1)),
      );

  void _reload([Period? p]) => setState(() {
        if (p != null) _period = p;
        _future = _fetch();
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('داشبورد خانواده'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: PeriodBar(period: _period, now: widget.now, onChanged: _reload),
          ),
          Expanded(
            child: FutureBuilder<DashboardSummary>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    key: kFamilyLoadingKey,
                    child: CircularProgressIndicator(),
                  );
                }
                if (snapshot.hasError) {
                  return const Center(
                    key: kFamilyErrorKey,
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'خطا در دریافت داشبورد از سرور. اینترنت و اتصال به سرور را چک کن.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                final s = snapshot.data!;
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(
                      _period.isAll ? 'همه‌ی زمان‌ها' : _period.rangeLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    _Totals(summary: s),
                    const SizedBox(height: 16),
                    _Section(
                      title: 'هزینه به‌تفکیک عضو',
                      rows: [
                        for (final m in s.members)
                          _Row(label: m.name, amountRial: m.expensesRial),
                      ],
                    ),
                    _Section(
                      title: 'هزینه به‌تفکیک دسته',
                      rows: [
                        for (final c in s.categories)
                          _Row(label: c.name ?? 'بدون دسته', amountRial: c.amountRial),
                      ],
                    ),
                    _Section(
                      title: 'هزینه به‌تفکیک کارت',
                      rows: [
                        for (final c in s.cards)
                          _Row(
                            label: c.cardLast4 == null ? 'نامشخص' : 'کارت ${c.cardLast4}',
                            amountRial: c.amountRial,
                          ),
                      ],
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

class _Totals extends StatelessWidget {
  final DashboardSummary summary;
  const _Totals({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Total(label: 'درآمد', valueKey: kFamilyIncomeKey, amountRial: summary.incomeRial, color: Colors.green.shade700),
            _Total(label: 'هزینه', valueKey: kFamilyExpenseKey, amountRial: summary.expenseRial, color: Colors.red.shade700),
            _Total(label: 'مانده', valueKey: kFamilyBalanceKey, amountRial: summary.balanceRial, color: Colors.blue.shade700),
          ],
        ),
      ),
    );
  }
}

class _Total extends StatelessWidget {
  final String label;
  final Key valueKey;
  final int amountRial;
  final Color color;
  const _Total({required this.label, required this.valueKey, required this.amountRial, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(formatToman(amountRial),
            key: valueKey,
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Row> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        Card(child: Column(children: rows)),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final int amountRial;
  const _Row({required this.label, required this.amountRial});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(formatToman(amountRial)),
    );
  }
}
