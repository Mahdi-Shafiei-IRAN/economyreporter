/// دسته‌بندی یک یا چند تراکنش: تیک‌زدن چند دسته + توضیح کوتاه.
/// مبلغ هر تراکنش به‌طور مساوی بین دسته‌های تیک‌خورده تقسیم می‌شود.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../dashboard/dashboard_controller.dart';
import '../transactions/data/transaction_record.dart';
import '../transactions/data/tx_query.dart';
import 'data/category.dart';

const kCategorizeSaveKey = Key('categorize-save');
const kCategorizeDescKey = Key('categorize-desc');

class CategorizeScreen extends StatefulWidget {
  final DashboardController controller;
  final List<TransactionRecord> records;

  CategorizeScreen({
    super.key,
    required this.controller,
    TransactionRecord? record,
    List<TransactionRecord>? records,
  }) : records = records ?? [record!];

  @override
  State<CategorizeScreen> createState() => _CategorizeScreenState();
}

class _CategorizeScreenState extends State<CategorizeScreen> {
  final Set<String> _selected = {};
  final _desc = TextEditingController();
  late Future<List<Category>> _categoriesFuture;
  bool _saving = false;

  bool get _single => widget.records.length == 1;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = widget.controller.categories().then((cats) {
      // دسته‌های فعلیِ تراکنش (اگر قبلاً دسته‌بندی شده) از پیش تیک بخورند.
      if (_single) {
        final current = widget.records.first.allocations.map((a) => a.categoryName).toSet();
        _selected.addAll(cats.where((c) => current.contains(c.name)).map((c) => c.id));
      }
      return cats;
    });
    if (_single) _desc.text = widget.records.first.description ?? '';
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    await widget.controller.categorizeMany(
      [for (final r in widget.records) r.id],
      _selected.toList(),
      description: _single ? _desc.text.trim() : null,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    if (_single) {
      final t = widget.records.first;
      return Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          title: Text(
            t.amountRial == null ? 'مبلغ نامشخص' : formatToman(t.amountRial!),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          subtitle: Text([
            formatJalaliDateTime(t.effectiveTime),
            personOf(t),
            cardTitleOf(t),
            if (t.counterparty?.isNotEmpty ?? false) t.counterparty!,
          ].join(' • ')),
        ),
      );
    }
    final total = widget.records.fold<int>(0, (a, t) => a + (t.amountRial ?? 0));
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text('${toPersianDigits('${widget.records.length}')} تراکنش — جمع ${formatToman(total)}',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: const Text('دسته‌های انتخابی به همه‌ی این تراکنش‌ها داده می‌شود.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = _single ? (widget.records.first.amountRial ?? 0) : 0;
    final perCategory = _selected.isEmpty ? 0 : amount ~/ _selected.length;

    return Scaffold(
      appBar: AppBar(title: Text(_single ? 'دسته‌بندی تراکنش' : 'دسته‌بندی گروهی')),
      body: FutureBuilder<List<Category>>(
        future: _categoriesFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final categories = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(context),
              const SizedBox(height: 16),
              Text('دسته‌ها را تیک بزن', style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                'اگر یک خرید چند دسته دارد (مثلاً میوه و نان)، همه را تیک بزن؛ '
                'مبلغ مساوی بینشان تقسیم می‌شود.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in categories)
                    FilterChip(
                      label: Text(c.name),
                      selected: _selected.contains(c.id),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _selected.add(c.id);
                        } else {
                          _selected.remove(c.id);
                        }
                      }),
                    ),
                ],
              ),
              if (_single && _selected.length > 1) ...[
                const SizedBox(height: 12),
                Text('سهم هر دسته: ${formatToman(perCategory)}',
                    style: theme.textTheme.bodyMedium),
              ],
              if (_single) ...[
                const SizedBox(height: 16),
                TextField(
                  key: kCategorizeDescKey,
                  controller: _desc,
                  decoration: const InputDecoration(labelText: 'توضیح کوتاه (اختیاری)'),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: kCategorizeSaveKey,
                onPressed: _selected.isEmpty || _saving ? null : _save,
                child: Text(_saving ? 'در حال ذخیره...' : 'ذخیره'),
              ),
            ],
          );
        },
      ),
    );
  }
}
