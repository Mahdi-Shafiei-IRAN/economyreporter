/// صف بازبینی: پیامک‌هایی که برنامه مطمئن نیست درست فهمیده (مبلغ/نوع نامشخص
/// یا احتمال تراکنش ناموفق). تا تأیید نشوند در جمع‌ها حساب نمی‌شوند.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/sms/digit_utils.dart';
import '../../core/theme/app_theme.dart';
import '../dashboard/dashboard_controller.dart';
import '../transactions/data/transaction_record.dart';
import '../transactions/data/tx_query.dart';
import '../transactions/transaction_details_sheet.dart';
import '../transactions/widgets/tx_widgets.dart';

const kReviewEmptyKey = Key('review-empty');
const kReviewExplainKey = Key('review-explain');

class ReviewScreen extends StatelessWidget {
  final DashboardController controller;

  const ReviewScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بازبینی پیامک‌های مبهم')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final items = controller.reviewItems;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _Explain(key: kReviewExplainKey),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Padding(
                  key: kReviewEmptyKey,
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(Icons.task_alt_rounded, size: 48),
                      SizedBox(height: 8),
                      Text('چیزی برای بازبینی نمانده'),
                    ],
                  ),
                )
              else
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ReviewCard(
                      key: ValueKey(item.id),
                      controller: controller,
                      record: item,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _Explain extends StatelessWidget {
  const _Explain({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.secondaryContainer.withOpacity(0.6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline_rounded, color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Text('این صفحه برای چیست؟',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'این‌ها پیامک‌هایی هستند که برنامه مطمئن نیست درست فهمیده؛ مثلاً مبلغ یا '
              'نوعِ تراکنش (برداشت/واریز) را پیدا نکرده، یا متن پیامک می‌گوید تراکنش '
              'ناموفق بوده. تا تصمیم نگیری، در جمع درآمد و هزینه حساب نمی‌شوند.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Text('• «درسته، ثبت کن»: تراکنش واقعی است (اگر لازم است نوع/مبلغ را اصلاح کن).',
                style: theme.textTheme.bodySmall),
            Text('• «نامعتبر است»: انجام نشده یا پیامک رمز بوده؛ حذف می‌شود و دیگر برنمی‌گردد.',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatefulWidget {
  final DashboardController controller;
  final TransactionRecord record;

  const _ReviewCard({super.key, required this.controller, required this.record});

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  late String _kind = _validKindOr(widget.record.kind);
  final _amount = TextEditingController();
  String? _amountError;
  bool _busy = false;

  static String _validKindOr(String kind) =>
      const {'income', 'expense', 'transfer'}.contains(kind) ? kind : 'expense';

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    int? amountRial;
    if (widget.record.amountRial == null) {
      final toman = int.tryParse(
          normalizeDigits(_amount.text.trim()).replaceAll(RegExp(r'[,٬\s]'), ''));
      if (toman == null || toman <= 0) {
        setState(() => _amountError = 'مبلغ را به تومان وارد کن');
        return;
      }
      amountRial = toman * 10;
    }
    setState(() => _busy = true);
    await widget.controller.confirmReview(widget.record.id, kind: _kind, amountRial: amountRial);
  }

  Future<void> _invalid() async {
    if (!await confirmInvalidate(context)) return;
    setState(() => _busy = true);
    await widget.controller.deleteTransaction(widget.record.id);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fin = FinanceColors.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.amountRial == null ? 'مبلغ نامشخص' : formatToman(r.amountRial!),
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(formatShortDateTime(r.effectiveTime),
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 2),
            Text('${personOf(r)} • ${cardTitleOf(r)}',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final reason in r.reviewReasons)
                  Pill(
                    text: reviewReasonLabel(reason),
                    icon: Icons.error_outline_rounded,
                    foreground: fin.warning,
                    background: fin.warningContainer,
                  ),
              ],
            ),
            if (r.smsBody != null && r.smsBody!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('متن پیامک', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text(r.smsBody!.trim(), style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
            if (r.amountRial == null) ...[
              const SizedBox(height: 12),
              TextField(
                key: Key('review-amount-${r.id}'),
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'مبلغ (تومان)',
                  errorText: _amountError,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SegmentedButton<String>(
              key: Key('review-kind-${r.id}'),
              segments: const [
                ButtonSegment(value: 'expense', label: Text('برداشت')),
                ButtonSegment(value: 'income', label: Text('واریز')),
                ButtonSegment(value: 'transfer', label: Text('انتقال')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: Key('review-confirm-${r.id}'),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('درسته، ثبت کن'),
                    onPressed: _busy ? null : _confirm,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: Key('review-delete-${r.id}'),
                  style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('نامعتبر است'),
                  onPressed: _busy ? null : _invalid,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
