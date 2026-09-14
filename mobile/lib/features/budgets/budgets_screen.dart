/// بودجه‌ها: برای هر دسته یک سقفِ خرجِ ماهانه بگذار و مصرفِ همین ماه را ببین.
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../../core/sms/digit_utils.dart';
import '../categories/data/category.dart';
import '../dashboard/dashboard_controller.dart';
import 'data/budget.dart';

const kBudgetsEmptyKey = Key('budgets-empty');
const kAddBudgetFabKey = Key('add-budget-fab');
const kBudgetCategoryFieldKey = Key('budget-category');
const kBudgetAmountFieldKey = Key('budget-amount');
const kBudgetSaveKey = Key('budget-save');

String _fa(int n) => toPersianDigits('$n');

class BudgetsScreen extends StatefulWidget {
  final DashboardController controller;

  const BudgetsScreen({super.key, required this.controller});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  DashboardController get _c => widget.controller;
  late Future<List<BudgetUsage>> _future = _c.budgetUsages();

  void _reload() => setState(() => _future = _c.budgetUsages());

  Future<void> _edit({BudgetUsage? existing}) async {
    final cats = await _c.categories();
    if (!mounted) return;
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (_) => _BudgetDialog(
        categories: cats,
        initialCategory: existing?.categoryName,
        initialToman: existing == null ? null : existing.limitRial ~/ 10,
      ),
    );
    if (result == null) return;
    await _c.saveBudget(
      id: existing?.budget.id,
      categoryName: result.$1,
      limitRial: result.$2,
    );
    _reload();
  }

  Future<void> _delete(BudgetUsage u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف بودجه‌ی «${u.categoryName}»؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await _c.deleteBudget(u.budget.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('بودجه‌ها')),
      floatingActionButton: FloatingActionButton.extended(
        key: kAddBudgetFabKey,
        onPressed: () => _edit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('بودجه‌ی جدید'),
      ),
      body: FutureBuilder<List<BudgetUsage>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Text(
                'سقفِ خرجِ هر دسته را برای هر ماه مشخص کن؛ مصرفِ همین ماه اینجا نشان داده '
                'می‌شود. بودجه‌ها بین اعضای خانواده مشترک‌اند.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const Padding(
                  key: kBudgetsEmptyKey,
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Column(children: [
                    Icon(Icons.savings_outlined, size: 48),
                    SizedBox(height: 8),
                    Text('هنوز بودجه‌ای نگذاشته‌ای.'),
                  ]),
                )
              else
                for (final u in list)
                  _BudgetCard(
                    key: ValueKey('budget-${u.budget.id}'),
                    usage: u,
                    onEdit: () => _edit(existing: u),
                    onDelete: () => _delete(u),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final BudgetUsage usage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BudgetCard(
      {super.key,
      required this.usage,
      required this.onEdit,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final u = usage;
    final ratio = u.ratio.clamp(0.0, 1.0);
    final barColor = u.exceeded
        ? scheme.error
        : (u.ratio >= 0.8 ? Colors.orange : scheme.primary);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(u.categoryName,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'ویرایش',
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'حذف',
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 10,
                backgroundColor: scheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('خرج‌شده: ${formatToman(u.spentRial)}',
                    style: theme.textTheme.bodyMedium),
                Text('سقف: ${formatToman(u.limitRial)}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              u.exceeded
                  ? '${formatToman(-u.remainingRial)} بیشتر از سقف!'
                  : '${formatToman(u.remainingRial)} باقی مانده '
                      '(${_fa((u.ratio * 100).round())}٪ مصرف شد)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: u.exceeded ? scheme.error : scheme.onSurfaceVariant,
                fontWeight: u.exceeded ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetDialog extends StatefulWidget {
  final List<Category> categories;
  final String? initialCategory;
  final int? initialToman;

  const _BudgetDialog({
    required this.categories,
    this.initialCategory,
    this.initialToman,
  });

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  String? _category;
  final _amount = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    if (widget.initialToman != null) {
      _amount.text = groupThousands(widget.initialToman!);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final cat = _category;
    final raw = normalizeDigits(_amount.text).replaceAll(RegExp(r'[^0-9]'), '');
    final toman = int.tryParse(raw) ?? 0;
    if (cat == null || cat.isEmpty) {
      setState(() => _error = 'یک دسته انتخاب کن');
      return;
    }
    if (toman <= 0) {
      setState(() => _error = 'مبلغِ سقف را وارد کن (به تومان)');
      return;
    }
    Navigator.of(context).pop((cat, toman * 10)); // تومان → ریال
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.categories.map((c) => c.name).toList();
    return AlertDialog(
      title: Text(widget.initialCategory == null ? 'بودجه‌ی جدید' : 'ویرایش بودجه'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            key: kBudgetCategoryFieldKey,
            value: _category != null && names.contains(_category) ? _category : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'دسته'),
            items: [
              for (final n in names)
                DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 12),
          TextField(
            key: kBudgetAmountFieldKey,
            controller: _amount,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'سقفِ ماهانه (تومان)',
              hintText: '۵۰۰٬۰۰۰',
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('انصراف')),
        FilledButton(key: kBudgetSaveKey, onPressed: _save, child: const Text('ذخیره')),
      ],
    );
  }
}
