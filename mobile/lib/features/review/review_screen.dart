/// صف بازبینی: تراکنش‌هایی که پارسر مطمئن نبوده (بانک/نوع نامشخص).
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../../core/sms/bank_registry.dart';
import '../dashboard/dashboard_controller.dart';
import '../transactions/data/transaction_record.dart';

const kReviewEmptyKey = Key('review-empty');

class ReviewScreen extends StatelessWidget {
  final DashboardController controller;

  const ReviewScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('صف بازبینی')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final items = controller.reviewItems;
          if (items.isEmpty) {
            return const Center(
              key: kReviewEmptyKey,
              child: Text('چیزی برای بازبینی نمانده 🎉'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final item in items)
                _ReviewCard(controller: controller, record: item),
            ],
          );
        },
      ),
    );
  }
}

class _ReviewCard extends StatefulWidget {
  final DashboardController controller;
  final TransactionRecord record;

  const _ReviewCard({required this.controller, required this.record});

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  late String _kind = _validKindOr(widget.record.kind);

  static String _validKindOr(String kind) =>
      const {'income', 'expense', 'transfer'}.contains(kind) ? kind : 'expense';

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final subtitle = [
      if (r.bankId != null) bankNameById(r.bankId!),
      if (r.cardLast4 != null) 'کارت ${r.cardLast4}',
    ].join(' • ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              r.amountRial == null ? 'مبلغ نامشخص' : formatToman(r.amountRial!),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(subtitle,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              key: Key('review-kind-${r.id}'),
              segments: const [
                ButtonSegment(value: 'income', label: Text('درآمد')),
                ButtonSegment(value: 'expense', label: Text('هزینه')),
                ButtonSegment(value: 'transfer', label: Text('انتقال')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: Key('review-confirm-${r.id}'),
                    icon: const Icon(Icons.check),
                    label: const Text('تأیید'),
                    onPressed: () =>
                        widget.controller.confirmReview(r.id, kind: _kind),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: Key('review-delete-${r.id}'),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('حذف'),
                  onPressed: () => widget.controller.deleteTransaction(r.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
