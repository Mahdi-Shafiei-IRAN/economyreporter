/// شیت ویرایش یک تراکنش (نوع، مبلغ، طرف حساب، توضیح).
library;

import 'package:flutter/material.dart';

import '../../core/sms/digit_utils.dart';
import '../dashboard/dashboard_controller.dart';
import 'data/transaction_record.dart';

const kEditKindKey = Key('edit-kind');
const kEditAmountKey = Key('edit-amount');
const kEditCounterpartyKey = Key('edit-counterparty');
const kEditDescriptionKey = Key('edit-description');
const kEditSaveKey = Key('edit-save');

Future<void> showEditTransactionSheet(
  BuildContext context,
  DashboardController controller,
  TransactionRecord record,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
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
  String? _amountError;

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
    final raw = normalizeDigits(_amount.text.trim()).replaceAll(RegExp(r'[,٬\s]'), '');
    final toman = int.tryParse(raw);
    if (toman == null || toman <= 0) {
      setState(() => _amountError = 'مبلغ را به تومان وارد کن');
      return;
    }
    await widget.controller.updateTransaction(
      widget.record.id,
      kind: _kind,
      amountRial: toman * 10,
      counterparty: _counterparty.text.trim(),
      description: _description.text.trim(),
      needsReview: false,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ویرایش تراکنش', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            key: kEditKindKey,
            segments: const [
              ButtonSegment(value: 'expense', label: Text('برداشت'), icon: Icon(Icons.north_east_rounded)),
              ButtonSegment(value: 'income', label: Text('واریز'), icon: Icon(Icons.south_west_rounded)),
              ButtonSegment(value: 'transfer', label: Text('انتقال'), icon: Icon(Icons.swap_horiz_rounded)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            key: kEditAmountKey,
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'مبلغ (تومان)',
              errorText: _amountError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: kEditCounterpartyKey,
            controller: _counterparty,
            decoration: const InputDecoration(labelText: 'طرف حساب / بابت'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: kEditDescriptionKey,
            controller: _description,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'توضیح'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: kEditSaveKey,
            onPressed: _save,
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }
}
