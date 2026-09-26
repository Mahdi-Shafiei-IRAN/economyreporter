/// «حسابِ تازه» با «موجودیِ الان» (طرح ۶.۲) و پنجره‌ی «موجودیِ الانِ این حساب؟».
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/ledger/models.dart';
import '../../core/sms/bank_registry.dart';
import 'ledger_controller.dart';
import 'ledger_text.dart';

const kAccountOwnerKey = Key('account-owner');
const kAccountLabelKey = Key('account-label');
const kAccountBankKey = Key('account-bank');
const kAccountCardKey = Key('account-card');
const kAccountRefKey = Key('account-ref');
const kAccountBalanceKey = Key('account-balance');
const kAccountSaveKey = Key('account-save');
const kAccountErrorKey = Key('account-error');
const kBalanceFieldKey = Key('balance-field');
const kBalanceSaveKey = Key('balance-save');

Future<LedgerAccount?> showAccountForm(BuildContext context, LedgerController controller,
    {AccountPrefill prefill = const AccountPrefill()}) {
  return showModalBottomSheet<LedgerAccount>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AccountForm(controller: controller, prefill: prefill),
  );
}

class _AccountForm extends StatefulWidget {
  final LedgerController controller;
  final AccountPrefill prefill;

  const _AccountForm({required this.controller, required this.prefill});

  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  late final TextEditingController _owner;
  final _label = TextEditingController();
  late final TextEditingController _card;
  late final TextEditingController _ref;
  late final TextEditingController _balance;
  String? _ownerUserId;
  String? _bankId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final people = widget.controller.people?.call();
    final p = widget.prefill;
    _owner = TextEditingController(text: people?.meName ?? '');
    _ownerUserId = people?.meUserId;
    _bankId = p.bankId;
    _card = TextEditingController(text: p.cardLast4 ?? '');
    _ref = TextEditingController(text: p.accountRef ?? '');
    _balance = TextEditingController(text: tomanInputText(p.balanceRial));
  }

  @override
  void dispose() {
    for (final c in [_owner, _label, _card, _ref, _balance]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final owner = _owner.text.trim();
    if (owner.isEmpty) {
      setState(() => _error = 'صاحبِ حساب کیست؟');
      return;
    }
    final balanceText = _balance.text.trim();
    final balance = parseTomanInput(balanceText);
    if (balanceText.isNotEmpty && balance == null) {
      setState(() => _error = 'موجودی را درست وارد کن');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final label = _label.text.trim().isNotEmpty
        ? _label.text.trim()
        : (_bankId == null ? 'نقد' : bankNameById(_bankId!));
    try {
      final a = await widget.controller.createAccount(
        ownerName: owner,
        ownerUserId: _ownerUserId,
        label: label,
        bankId: _bankId,
        cardLast4: _card.text,
        accountRef: _ref.text,
        balanceRial: balance,
      );
      if (mounted) Navigator.of(context).pop(a);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'ذخیره نشد: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final people = widget.controller.people?.call();
    final members = people?.members ?? const [];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('حسابِ تازه', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              key: kAccountOwnerKey,
              controller: _owner,
              decoration: const InputDecoration(labelText: 'صاحبِ حساب'),
              onChanged: (_) => setState(() => _ownerUserId = null),
            ),
            if (members.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  for (final m in members)
                    ChoiceChip(
                      label: Text(m.name),
                      selected: _ownerUserId == m.id,
                      onSelected: (_) => setState(() {
                        _owner.text = m.name;
                        _ownerUserId = m.id;
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: kAccountBankKey,
              value: _bankId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'بانک'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('نقد / بدون بانک')),
                for (final b in kBankRegistry)
                  DropdownMenuItem<String?>(value: b.id, child: Text(b.name)),
              ],
              onChanged: (id) => setState(() => _bankId = id),
            ),
            const SizedBox(height: 12),
            TextField(
              key: kAccountLabelKey,
              controller: _label,
              decoration: const InputDecoration(
                  labelText: 'نام (اختیاری)', hintText: 'مثلاً «ملت حقوق»'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: kAccountCardKey,
                    controller: _card,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(labelText: 'کارت (۴ رقم)', counterText: ''),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: kAccountRefKey,
                    controller: _ref,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'شماره‌ی حساب (اختیاری)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: kAccountBalanceKey,
              controller: _balance,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'موجودیِ الان (تومان)',
                helperText: widget.prefill.balanceRial != null
                    ? 'طبقِ آخرین پیامکِ بانک؛ اگر فرق دارد درستش کن'
                    : 'همه‌ی حساب‌ها از همین عدد شروع می‌شوند',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  key: kAccountErrorKey, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: kAccountSaveKey,
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('ساختِ حساب'),
            ),
          ],
        ),
      ),
    );
  }
}

/// «موجودیِ الانِ این حساب؟» (لنگر) یا «تطبیق با موجودیِ واقعی» ([reconcile]).
Future<void> showBalanceDialog(BuildContext context, LedgerController controller, AccountView v,
    {bool reconcile = false}) async {
  final initial = reconcile ? v.balance?.balanceRial : v.lastBankBalance;
  final field = TextEditingController(text: tomanInputText(initial));
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(reconcile
            ? 'موجودیِ واقعیِ «${accountTitle(v.account)}»'
            : 'موجودیِ الانِ «${accountTitle(v.account)}» چقدر است؟'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!reconcile && v.lastBankBalance != null)
              Text('طبقِ پیامکِ ${formatShortDateTime(v.lastBankBalanceAt!)}: '
                  '${formatToman(v.lastBankBalance!)} — درست است؟'),
            if (reconcile)
              const Text('عددی که الان در بانک/کیف داری؛ اگر با حساب‌شده نخواند، اختلاف نشان داده می‌شود.'),
            const SizedBox(height: 12),
            TextField(
              key: kBalanceFieldKey,
              controller: field,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'تومان', errorText: error),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('انصراف')),
          FilledButton(
            key: kBalanceSaveKey,
            onPressed: () async {
              final rial = parseTomanInput(field.text);
              if (rial == null) {
                setState(() => error = 'عدد را وارد کن');
                return;
              }
              await controller.setBalanceNow(v.account.id, rial);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('ثبت'),
          ),
        ],
      ),
    ),
  );
}
