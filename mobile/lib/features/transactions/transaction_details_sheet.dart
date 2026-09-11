/// برگه‌ی جزئیات یک تراکنش: همه‌ی اطلاعات + متن پیامک؛ ویرایش/دسته‌بندی/نامعتبر
/// فقط برای صاحب کارت، بقیه فقط می‌بینند.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/theme/app_theme.dart';
import '../categories/categorize_screen.dart';
import '../dashboard/dashboard_controller.dart';
import 'data/transaction_record.dart';
import 'data/tx_query.dart';
import 'edit_transaction_sheet.dart';
import 'widgets/tx_widgets.dart';

const kDetailsSheetKey = Key('details-sheet');
const kDetailsCategorizeKey = Key('details-categorize');
const kDetailsEditKey = Key('details-edit');
const kDetailsDeleteKey = Key('details-delete');
const kDetailsReadOnlyKey = Key('details-readonly');
const kConfirmInvalidKey = Key('confirm-invalid');

Future<void> showTransactionDetails(
  BuildContext context,
  DashboardController controller,
  TransactionRecord record,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => _DetailsBody(
        controller: controller,
        initial: record,
        scrollController: scroll,
      ),
    ),
  );
}

/// تأیید «نامعتبر است» (حذف نرم) با توضیح اینکه برای چیست.
Future<bool> confirmInvalidate(BuildContext context, {int count = 1}) async {
  final many = count > 1;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.block_rounded),
      title: Text(many
          ? '${toPersianDigits('$count')} تراکنش نامعتبر علامت بخورد؟'
          : 'این تراکنش نامعتبر علامت بخورد؟'),
      content: const Text(
        'برای تراکنشی که واقعاً انجام نشده (ناموفق/لغوشده) یا پیامک رمزی که '
        'اشتباهی مبلغ ثبت کرده.\n\n'
        'از فهرست و جمع‌ها حذف می‌شود، روی گوشی بقیه‌ی اعضا هم حذف می‌شود و '
        'با خواندن دوباره‌ی پیامک‌ها برنمی‌گردد.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('انصراف'),
        ),
        FilledButton(
          key: kConfirmInvalidKey,
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('بله، نامعتبر است'),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _DetailsBody extends StatelessWidget {
  final DashboardController controller;
  final TransactionRecord initial;
  final ScrollController scrollController;

  const _DetailsBody({
    required this.controller,
    required this.initial,
    required this.scrollController,
  });

  String _syncLabel(TransactionRecord t) {
    if (t.isRemote) return 'از گوشی عضو دیگر خانواده (از سرور)';
    return switch (t.syncStatus) {
      'synced' => 'روی سرور ثبت شده',
      'failed' => 'ارسال نشد؛ خودکار دوباره تلاش می‌شود',
      _ => 'در صف ارسال به سرور',
    };
  }

  Future<void> _categorize(BuildContext context, TransactionRecord t) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CategorizeScreen(controller: controller, record: t),
    ));
  }

  Future<void> _invalidate(BuildContext context, TransactionRecord t) async {
    if (!await confirmInvalidate(context)) return;
    await controller.deleteTransaction(t.id);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = controller.cachedById(initial.id) ?? initial;
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final fin = FinanceColors.of(context);
        final style = KindStyle.of(context, t.kind);
        final canEdit = controller.canEdit(t);

        return ListView(
          key: kDetailsSheetKey,
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Center(
              child: CircleAvatar(
                radius: 26,
                backgroundColor: style.container,
                child: Icon(style.icon, color: style.color, size: 26),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                t.amountRial == null ? 'مبلغ نامشخص' : formatToman(t.amountRial!),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: style.color,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '${style.label} • ${formatJalaliDateTime(t.effectiveTime)}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (t.needsReview) ...[
              const SizedBox(height: 16),
              _Notice(
                icon: Icons.error_outline_rounded,
                color: fin.warning,
                background: fin.warningContainer,
                title: 'منتظر بازبینی — هنوز در جمع‌ها حساب نمی‌شود',
                lines: [for (final r in t.reviewReasons) reviewReasonLabel(r)],
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.person_outline_rounded,
                    label: 'صاحب کارت',
                    value: personOf(t) == kUnknownPerson
                        ? 'نامشخص (این کارت هنوز در «کارت‌ها» ثبت نشده)'
                        : personOf(t),
                  ),
                  _InfoRow(
                    icon: Icons.credit_card_rounded,
                    label: 'کارت/حساب',
                    value: [
                      if (t.walletLabel != null) t.walletLabel!,
                      cardDetailsOf(t) ?? 'نامشخص',
                    ].join(' — '),
                  ),
                  if (t.balanceAfterRial != null)
                    _InfoRow(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'مانده‌ی حساب بعد از این تراکنش',
                      value: formatToman(t.balanceAfterRial!),
                    ),
                  if (t.counterparty?.isNotEmpty ?? false)
                    _InfoRow(
                      icon: Icons.storefront_outlined,
                      label: 'طرف حساب / بابت',
                      value: t.counterparty!,
                    ),
                  if (t.description?.isNotEmpty ?? false)
                    _InfoRow(
                      icon: Icons.notes_rounded,
                      label: 'توضیح',
                      value: t.description!,
                    ),
                  _InfoRow(
                    icon: Icons.label_outline_rounded,
                    label: 'دسته‌ها',
                    value: t.isCategorized
                        ? t.allocations
                            .map((a) => '${a.categoryName} (${formatToman(a.amountRial)})')
                            .join('، ')
                        : 'دسته‌بندی نشده',
                  ),
                  _InfoRow(
                    icon: Icons.cloud_outlined,
                    label: 'همگام‌سازی',
                    value: _syncLabel(t),
                    last: true,
                  ),
                ],
              ),
            ),
            if (t.smsBody != null && t.smsBody!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  leading: const Icon(Icons.sms_outlined),
                  title: const Text('متن پیامک اصلی'),
                  subtitle: Text(
                    'فقط روی همین گوشی نگه داشته می‌شود',
                    style: theme.textTheme.bodySmall,
                  ),
                  shape: const Border(),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SelectableText(t.smsBody!.trim()),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            if (canEdit)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (t.kind == 'income' || t.kind == 'expense')
                    FilledButton.icon(
                      key: kDetailsCategorizeKey,
                      onPressed: () => _categorize(context, t),
                      icon: const Icon(Icons.label_outline_rounded),
                      label: Text(t.isCategorized ? 'تغییر دسته' : 'دسته‌بندی'),
                    ),
                  OutlinedButton.icon(
                    key: kDetailsEditKey,
                    onPressed: () => showEditTransactionSheet(context, controller, t),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('ویرایش'),
                  ),
                  TextButton.icon(
                    key: kDetailsDeleteKey,
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    onPressed: () => _invalidate(context, t),
                    icon: const Icon(Icons.block_rounded),
                    label: const Text('نامعتبر است'),
                  ),
                ],
              )
            else
              _Notice(
                key: kDetailsReadOnlyKey,
                icon: Icons.lock_outline_rounded,
                color: scheme.onSurfaceVariant,
                background: scheme.surfaceContainerHigh,
                title: 'فقط مشاهده',
                lines: [
                  'فقط ${controller.editorName(t)} (صاحب این کارت) می‌تواند این '
                      'تراکنش را ویرایش یا دسته‌بندی کند.',
                ],
              ),
          ],
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool last;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(value, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!last) const Divider(indent: 48),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final List<String> lines;

  const _Notice({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    this.lines = const [],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: color, fontWeight: FontWeight.w700)),
                for (final line in lines) ...[
                  const SizedBox(height: 4),
                  Text(line, style: theme.textTheme.bodySmall?.copyWith(color: color)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
