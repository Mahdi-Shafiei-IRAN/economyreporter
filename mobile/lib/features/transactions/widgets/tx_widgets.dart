/// اجزای مشترک نمایش تراکنش: سبک هر نوع، ردیف تراکنش، برچسب‌ها و سرتیترها.
library;

import 'package:flutter/material.dart';

import '../../../core/format/date_format.dart';
import '../../../core/format/money_format.dart';
import '../../../core/sms/models.dart';
import '../../../core/theme/app_theme.dart';
import '../data/transaction_record.dart';
import '../data/tx_query.dart';

/// سبک نمایش هر نوع تراکنش (آیکون + رنگ + برچسب؛ فقط به رنگ تکیه نمی‌کند).
class KindStyle {
  final String label;
  final IconData icon;
  final Color color;
  final Color container;

  const KindStyle(this.label, this.icon, this.color, this.container);

  static KindStyle of(BuildContext context, String kind) {
    final c = FinanceColors.of(context);
    switch (kind) {
      case 'income':
        return KindStyle('واریز', Icons.south_west_rounded, c.income, c.incomeContainer);
      case 'expense':
        return KindStyle('برداشت', Icons.north_east_rounded, c.expense, c.expenseContainer);
      case 'transfer':
        return KindStyle('انتقال', Icons.swap_horiz_rounded, c.transfer, c.transferContainer);
      default:
        return KindStyle('نامشخص', Icons.help_outline_rounded, c.warning, c.warningContainer);
    }
  }
}

/// توضیح قابل‌فهمِ دلیل بازبینی.
String reviewReasonLabel(String code) => switch (code) {
      ReviewReason.amount => 'مبلغ از متن پیامک پیدا نشد',
      ReviewReason.kind => 'معلوم نیست برداشت است یا واریز',
      ReviewReason.failed => 'متن پیامک می‌گوید تراکنش احتمالاً ناموفق یا لغو شده',
      _ => 'نیاز به بررسی',
    };

/// عنوان ردیف: طرف حساب/توضیح، وگرنه نوع.
String transactionTitle(BuildContext context, TransactionRecord t) {
  final title = (t.counterparty?.trim().isNotEmpty ?? false)
      ? t.counterparty!.trim()
      : (t.description?.trim().isNotEmpty ?? false)
          ? t.description!.trim()
          : null;
  return title == null ? KindStyle.of(context, t.kind).label : toPersianDigits(title);
}

/// مبلغ به تومان بدون واحد («۱۲۰٬۰۰۰») یا «نامشخص».
String amountText(TransactionRecord t) =>
    t.amountRial == null ? 'نامشخص' : formatToman(t.amountRial!, withUnit: false);

/// برچسب کوچک گرد.
class Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color foreground;
  final Color background;

  const Pill({
    super.key,
    required this.text,
    required this.foreground,
    required this.background,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: foreground, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// ردیف یک تراکنش.
class TransactionTile extends StatelessWidget {
  final TransactionRecord record;

  /// نشان دادن شخص و کارت در زیرعنوان (در نمای «همه»؛ در نمای پله‌ای سرتیتر دارند).
  final bool showOwner;
  final bool canEdit;
  final bool selected;
  final bool selectionMode;

  /// «بدون دسته» فقط برای تراکنش‌های بعد از شروع دسته‌بندی نشان داده می‌شود.
  final DateTime? categorizeFrom;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TransactionTile({
    super.key,
    required this.record,
    this.showOwner = true,
    this.canEdit = true,
    this.selected = false,
    this.selectionMode = false,
    this.categorizeFrom,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = record;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fin = FinanceColors.of(context);
    final style = KindStyle.of(context, t.kind);

    final subtitle = [
      formatShortDateTime(t.effectiveTime),
      if (showOwner) personOf(t),
      if (showOwner) cardTitleOf(t),
    ].join(' • ');

    final pills = <Widget>[
      if (t.needsReview)
        Pill(
          text: 'منتظر بازبینی',
          icon: Icons.error_outline_rounded,
          foreground: fin.warning,
          background: fin.warningContainer,
        )
      else if (t.isCategorized) ...[
        for (final a in t.allocations.take(2))
          Pill(
            text: a.categoryName,
            foreground: scheme.onSecondaryContainer,
            background: scheme.secondaryContainer,
          ),
        if (t.allocations.length > 2)
          Pill(
            text: '+${toPersianDigits('${t.allocations.length - 2}')}',
            foreground: scheme.onSecondaryContainer,
            background: scheme.secondaryContainer,
          ),
      ] else if (canEdit &&
          (t.kind == 'income' || t.kind == 'expense') &&
          categorizeFrom != null &&
          !t.effectiveTime.isBefore(categorizeFrom!))
        Pill(
          text: 'بدون دسته',
          icon: Icons.label_outline_rounded,
          foreground: scheme.onSurfaceVariant,
          background: scheme.surfaceContainerHigh,
        ),
    ];

    final leading = selectionMode
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? scheme.primary : Colors.transparent,
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : (canEdit ? scheme.outline : scheme.outlineVariant),
                width: 2,
              ),
            ),
            child: selected
                ? Icon(Icons.check_rounded, color: scheme.onPrimary, size: 22)
                : (canEdit
                    ? null
                    : Icon(Icons.lock_outline_rounded,
                        size: 18, color: scheme.outline)),
          )
        : CircleAvatar(
            radius: 20,
            backgroundColor: style.container,
            child: Icon(style.icon, color: style.color, size: 20),
          );

    return Material(
      color: selected ? scheme.primaryContainer.withOpacity(0.45) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transactionTitle(context, t),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (pills.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 4, runSpacing: 4, children: pills),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amountText(t),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: style.color,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!canEdit && !selectionMode) ...[
                        Icon(Icons.lock_outline_rounded,
                            size: 12, color: scheme.outline),
                        const SizedBox(width: 2),
                      ],
                      Text(
                        '${style.label} • تومان',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
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

/// سرتیتر یک بخش (مثلاً روز) با جمع کوچک در انتها.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 6),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// جمعِ کوتاه یک گروه: «هزینه ۱۲۰٬۰۰۰ • درآمد ۵۰٬۰۰۰».
String shortTotals(int incomeRial, int expenseRial) {
  final parts = [
    if (expenseRial > 0) 'هزینه ${formatToman(expenseRial, withUnit: false)}',
    if (incomeRial > 0) 'درآمد ${formatToman(incomeRial, withUnit: false)}',
  ];
  return parts.isEmpty ? '' : parts.join(' • ');
}
