/// شیت ویرایش/حذف یک تراکنش.
library;

import 'package:flutter/material.dart';

import '../dashboard/dashboard_controller.dart';
import 'data/transaction_record.dart';

const kEditKindKey = Key('edit-kind');
const kEditAmountKey = Key('edit-amount');
const kEditCounterpartyKey = Key('edit-counterparty');
const kEditSaveKey = Key('edit-save');
const kEditDeleteKey = Key('edit-delete');

Future<void> showEditTransactionSheet(
  BuildContext context,
  DashboardController controller,
  TransactionRecord record,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditSheet(controller: controller, record: record),
  );
}

class _EditSheet extends StatefulWidget {
  final DashboardController controller;
  final TransactionRecord record;

  const _EditSheet({required this.controller, required this.record});

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late String _kind = _validKindOr(widget.record.kind);
  late final _amount = TextEditingController(
    text: widget.record.amountRial == null
        ? ''
        : (widget.record.amountRial! ~/ 10).toString(), // نمایش به تومان
  );
  late final _counterparty =
      TextEditingController(text: widget.record.counterparty ?? '');
  late final _description =
      TextEditingController(text: widget.record.description ?? '');

  static String _validKindOr(String kind) =>
      const {'income', 'expense', 'transfer'}.contains(kind) ? kind : 'expense';

  @override
  void dispose() {
    _amount.dispose();
    _counterparty.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final tomanText = _amount.text.trim().replaceAll(',', '');
    final toman = int.tryParse(tomanText);
    await widget.controller.updateTransaction(
      widget.record.id,
      kind: _kind,
      amountRial: toman == null ? null : toman * 10,
      counterparty: _counterparty.text.trim(),
      description: _description.text.trim(),
      needsReview: false,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await widget.controller.deleteTransaction(widget.record.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ویرایش تراکنش',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: kEditKindKey,
            value: _kind,
            decoration: const InputDecoration(
              labelText: 'نوع',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'income', child: Text('درآمد')),
              DropdownMenuItem(value: 'expense', child: Text('هزینه')),
              DropdownMenuItem(value: 'transfer', child: Text('انتقال')),
            ],
            onChanged: (v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: 12),
          TextField(
            key: kEditAmountKey,
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'مبلغ (تومان)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: kEditCounterpartyKey,
            controller: _counterparty,
            decoration: const InputDecoration(
              labelText: 'طرف حساب / بابت',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'توضیح',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: kEditSaveKey,
                  onPressed: _save,
                  child: const Text('ذخیره'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: kEditDeleteKey,
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('حذف'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
