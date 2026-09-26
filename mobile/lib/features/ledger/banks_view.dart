/// «بانک‌ها» (قدمِ ۱): از روی پیامک‌های گوشی می‌پرسد کدام فرستنده بانک است. فقط پیامکِ این‌ها می‌آید.
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../../core/sms/bank_registry.dart';
import '../senders/data/sender_candidates.dart';
import 'ledger_controller.dart';

Key bankAllowKey(String address) => Key('bank-allow-$address');
Key bankDismissKey(String address) => Key('bank-dismiss-$address');
Key bankRemoveKey(String id) => Key('bank-remove-$id');
const kBankPickSaveKey = Key('bank-pick-save');

String _fa(int n) => toPersianDigits('$n');

class LedgerBanksView extends StatefulWidget {
  final LedgerController controller;

  const LedgerBanksView({super.key, required this.controller});

  @override
  State<LedgerBanksView> createState() => _LedgerBanksViewState();
}

class _LedgerBanksViewState extends State<LedgerBanksView> {
  LedgerController get _c => widget.controller;
  late Future<List<SenderCandidate>> _candidates = _c.senderCandidates();

  void _refresh() {
    final next = _c.senderCandidates();
    setState(() {
      _candidates = next;
    });
  }

  Future<void> _allow(SenderCandidate s) async {
    final bank = await showDialog<String?>(
      context: context,
      builder: (_) => _BankPick(initial: s.bankId),
    );
    if (bank == null || !mounted) return;
    await _c.allowSender(s.address, bank.isEmpty ? null : bank);
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('فقط پیامکِ فرستنده‌هایی که «بانک است» بزنی خوانده می‌شود؛ تبلیغ و فروشگاه نه.',
              style: muted),
          const SizedBox(height: 12),
          FutureBuilder<List<SenderCandidate>>(
            future: _candidates,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final list = snap.data!;
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('فرستنده‌ی تازه‌ای در پیامک‌ها نیست.', style: muted),
                );
              }
              return Column(
                children: [
                  for (final s in list)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(
                                  s.bankId == null ? 'بانک؟' : bankNameById(s.bankId!),
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              Text(s.address,
                                  textDirection: TextDirection.ltr, style: theme.textTheme.bodySmall),
                            ]),
                            Text('${_fa(s.weight)} پیامکِ مبلغ‌دار', style: muted),
                            if (s.sample != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(s.sample!,
                                    maxLines: 2, overflow: TextOverflow.ellipsis, style: muted),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  key: bankDismissKey(s.address),
                                  onPressed: () async {
                                    await _c.dismissSender(s.address);
                                    _refresh();
                                  },
                                  child: const Text('بانک نیست'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.tonal(
                                  key: bankAllowKey(s.address),
                                  onPressed: () => _allow(s),
                                  child: const Text('بانک است'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (_c.banks.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
              child: Text('بانک‌های انتخاب‌شده', style: theme.textTheme.titleSmall),
            ),
            Card(
              child: Column(
                children: [
                  for (final b in _c.banks)
                    ListTile(
                      leading: const Icon(Icons.account_balance_outlined),
                      title: Text(b.bankId == null ? 'بانک نامشخص' : bankNameById(b.bankId!)),
                      subtitle: Text(b.address, textDirection: TextDirection.ltr),
                      trailing: IconButton(
                        key: bankRemoveKey(b.id),
                        tooltip: 'برداشتن',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () async {
                          await _c.removeSender(b.id);
                          _refresh();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// انتخابِ بانکِ یک فرستنده. '' = بانک نامشخص؛ null = انصراف.
class _BankPick extends StatefulWidget {
  final String? initial;
  const _BankPick({this.initial});

  @override
  State<_BankPick> createState() => _BankPickState();
}

class _BankPickState extends State<_BankPick> {
  late String _bank = widget.initial ?? '';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('کدام بانک؟'),
        content: DropdownButtonFormField<String>(
          value: _bank,
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: '', child: Text('نمی‌دانم')),
            for (final b in kBankRegistry) DropdownMenuItem(value: b.id, child: Text(b.name)),
          ],
          onChanged: (v) => setState(() => _bank = v ?? ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
            key: kBankPickSaveKey,
            onPressed: () => Navigator.pop(context, _bank),
            child: const Text('تأیید'),
          ),
        ],
      );
}

class LedgerBanksScreen extends StatelessWidget {
  final LedgerController controller;
  const LedgerBanksScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('بانک‌ها')),
        body: LedgerBanksView(controller: controller),
      );
}
