/// صفحه‌ی اصلی: جمع درآمد/هزینه/مانده + لیست تراکنش‌ها.
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../../core/sms/bank_registry.dart';
import '../transactions/data/transaction_record.dart';
import '../transactions/data/transaction_repository.dart';
import 'dashboard_controller.dart';

/// کلیدهای تست.
const kIncomeValueKey = Key('summary-income');
const kExpenseValueKey = Key('summary-expense');
const kBalanceValueKey = Key('summary-balance');
const kAddSmsFabKey = Key('add-sms-fab');
const kSmsSenderFieldKey = Key('sms-sender-field');
const kSmsBodyFieldKey = Key('sms-body-field');
const kSmsSaveButtonKey = Key('sms-save-button');
const kEmptyStateKey = Key('empty-state');

class DashboardScreen extends StatefulWidget {
  final DashboardController controller;

  const DashboardScreen({super.key, required this.controller});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DashboardController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.load();
  }

  Future<void> _openAddSmsSheet() async {
    final input = await showModalBottomSheet<_SmsInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddSmsSheet(),
    );
    if (input == null) return;

    final outcome = await _c.addFromSms(sender: input.sender, body: input.body);
    if (!mounted) return;

    final message = outcome.isDuplicate
        ? 'این پیامک قبلاً ثبت شده بود.'
        : 'تراکنش ثبت شد.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مدیریت مالی خانواده')),
      floatingActionButton: FloatingActionButton.extended(
        key: kAddSmsFabKey,
        onPressed: _openAddSmsSheet,
        icon: const Icon(Icons.sms_outlined),
        label: const Text('افزودن پیامک'),
      ),
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          if (_c.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(
            onRefresh: _c.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                _SummaryCard(summary: _c.summary),
                const SizedBox(height: 16),
                if (_c.transactions.isEmpty)
                  const _EmptyState()
                else
                  ..._c.transactions.map((t) => _TransactionTile(record: t)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final FinanceSummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _SummaryItem(
              label: 'درآمد',
              valueKey: kIncomeValueKey,
              amountRial: summary.incomeRial,
              color: Colors.green.shade700,
            ),
            _SummaryItem(
              label: 'هزینه',
              valueKey: kExpenseValueKey,
              amountRial: summary.expenseRial,
              color: Colors.red.shade700,
            ),
            _SummaryItem(
              label: 'مانده',
              valueKey: kBalanceValueKey,
              amountRial: summary.balanceRial,
              color: Colors.blue.shade700,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final Key valueKey;
  final int amountRial;
  final Color color;

  const _SummaryItem({
    required this.label,
    required this.valueKey,
    required this.amountRial,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(
          key: valueKey,
          formatToman(amountRial),
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final TransactionRecord record;
  const _TransactionTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final meta = _kindMeta(record.kind);
    final subtitleParts = <String>[
      if (record.bankId != null) bankNameById(record.bankId!),
      if (record.cardLast4 != null) 'کارت ${record.cardLast4}',
    ];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: meta.color.withOpacity(0.15),
          child: Icon(meta.icon, color: meta.color),
        ),
        title: Text(
          record.amountRial == null
              ? 'مبلغ نامشخص'
              : formatToman(record.amountRial!),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: subtitleParts.isEmpty ? null : Text(subtitleParts.join(' • ')),
        trailing: record.needsReview
            ? const Chip(
                label: Text('بازبینی', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                backgroundColor: Color(0xFFFFF3CD),
              )
            : Text(meta.label, style: TextStyle(color: meta.color)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: kEmptyStateKey,
      padding: EdgeInsets.only(top: 64),
      child: Center(
        child: Text('هنوز تراکنشی ثبت نشده.\nبا دکمه‌ی «افزودن پیامک» شروع کن.',
            textAlign: TextAlign.center),
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('افزودن پیامک بانکی',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            key: kSmsSenderFieldKey,
            controller: _senderController,
            decoration: const InputDecoration(
              labelText: 'فرستنده (نام/سرشماره بانک)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: kSmsBodyFieldKey,
            controller: _bodyController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'متن پیامک',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: kSmsSaveButtonKey,
            onPressed: _save,
            child: const Text('پارس و ذخیره'),
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

class _KindMeta {
  final String label;
  final IconData icon;
  final Color color;
  const _KindMeta(this.label, this.icon, this.color);
}

_KindMeta _kindMeta(String kind) {
  switch (kind) {
    case 'income':
      return const _KindMeta('درآمد', Icons.south_west, Colors.green);
    case 'expense':
      return const _KindMeta('هزینه', Icons.north_east, Colors.red);
    case 'transfer':
      return const _KindMeta('انتقال', Icons.swap_horiz, Colors.blueGrey);
    default:
      return const _KindMeta('نامشخص', Icons.help_outline, Colors.grey);
  }
}
