/// صفحه‌ی دسته‌بندی یک تراکنش: تیک‌زدن چند دسته + توضیح کوتاه.
/// مبلغ به‌طور مساوی بین دسته‌های تیک‌خورده تقسیم می‌شود.
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../dashboard/dashboard_controller.dart';
import '../transactions/data/transaction_record.dart';
import 'data/category.dart';

const kCategorizeSaveKey = Key('categorize-save');
const kCategorizeDescKey = Key('categorize-desc');

class CategorizeScreen extends StatefulWidget {
  final DashboardController controller;
  final TransactionRecord record;

  const CategorizeScreen({
    super.key,
    required this.controller,
    required this.record,
  });

  @override
  State<CategorizeScreen> createState() => _CategorizeScreenState();
}

class _CategorizeScreenState extends State<CategorizeScreen> {
  final Set<String> _selected = {};
  final _desc = TextEditingController();
  late Future<List<Category>> _categoriesFuture;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = widget.controller.categories();
    _desc.text = widget.record.description ?? '';
  }

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected.isEmpty || _saving) return;
    setState(() => _saving = true);
    await widget.controller
        .categorize(widget.record.id, _selected.toList(), description: _desc.text.trim());
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final amount = widget.record.amountRial ?? 0;
    final perCategory = _selected.isEmpty ? 0 : amount ~/ _selected.length;

    return Scaffold(
      appBar: AppBar(title: const Text('دسته‌بندی')),
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
              Text(
                'مبلغ: ${formatToman(amount)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text('دسته‌های این خرید را تیک بزن (مبلغ مساوی تقسیم می‌شود):',
                  style: Theme.of(context).textTheme.bodySmall),
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
              if (_selected.length > 1) ...[
                const SizedBox(height: 12),
                Text('هر دسته: ${formatToman(perCategory)}',
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
              const SizedBox(height: 16),
              TextField(
                key: kCategorizeDescKey,
                controller: _desc,
                decoration: const InputDecoration(
                  labelText: 'توضیح کوتاه (اختیاری)',
                  border: OutlineInputBorder(),
                ),
              ),
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
