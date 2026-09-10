/// فهرست موارد مشکوک به پیامک جاافتاده (از تطبیق مانده).
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../../core/reconcile/reconciliation.dart';

class ReconciliationScreen extends StatelessWidget {
  final List<BalanceGap> gaps;

  const ReconciliationScreen({super.key, required this.gaps});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تطبیق مانده')),
      body: gaps.isEmpty
          ? const Center(child: Text('ناهماهنگی‌ای پیدا نشد ✅'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'بر اساس مانده‌ی داخل پیامک‌ها، این موارد نشان می‌دهند احتمالاً '
                    'تراکنشی ثبت نشده است:',
                  ),
                ),
                for (final gap in gaps) _GapCard(gap: gap),
              ],
            ),
    );
  }
}

class _GapCard extends StatelessWidget {
  final BalanceGap gap;
  const _GapCard({required this.gap});

  @override
  Widget build(BuildContext context) {
    final missing = gap.missingAmountRial;
    final direction = missing < 0 ? 'برداشتِ ثبت‌نشده' : 'واریزِ ثبت‌نشده';
    final amount = formatToman(missing.abs());
    final source = gap.cardLast4 != null
        ? 'کارت ${gap.cardLast4}'
        : (gap.accountRef != null ? 'حساب ${gap.accountRef}' : 'نامشخص');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: Text('$direction: $amount'),
        subtitle: Text(
          '$source — '
          'مانده‌ی موردانتظار ${formatToman(gap.expectedBalanceRial)}، '
          'واقعی ${formatToman(gap.actualBalanceRial)}',
        ),
      ),
    );
  }
}
