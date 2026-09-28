/// «بانک‌ها» (قدمِ ۱): از روی پیامک‌های گوشی می‌پرسد کدام فرستنده بانک است. فقط پیامکِ این‌ها می‌آید.
/// اگر برنامه فرستنده‌ای را تشخیص نداد، «افزودنِ دستی» (تایپ یا انتخاب از صندوق). زیرِ هر فرستنده‌ی انتخاب‌شده
/// می‌گوید پیامک‌هایش چه شده‌اند و به کدام کارت رفته‌اند (طرح ۱۲.۱۰).
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../../core/sms/bank_registry.dart';
import '../senders/data/allowed_sender.dart';
import '../senders/data/sender_candidates.dart';
import 'ledger_controller.dart';
import 'ledger_text.dart';

Key bankAllowKey(String address) => Key('bank-allow-$address');
Key bankDismissKey(String address) => Key('bank-dismiss-$address');
Key bankRemoveKey(String id) => Key('bank-remove-$id');
Key bankStatusKey(String id) => Key('bank-status-$id');
Key inboxSenderKey(String address) => Key('inbox-sender-$address');
const kBankPickSaveKey = Key('bank-pick-save');
const kBankManualAddKey = Key('bank-manual-add');
const kBankManualAddressKey = Key('bank-manual-address');
const kBankManualSaveKey = Key('bank-manual-save');
const kBankManualErrorKey = Key('bank-manual-error');

String _fa(int n) => toPersianDigits('$n');

/// «این فرستنده چه شد؟» — تا کاربر خودش ببیند چرا کارتی دیده نمی‌شود.
String senderStatusText(SenderStatus s) {
  if (s.total == 0) {
    return 'از تاریخِ شروع پیامکی از این فرستنده خوانده نشده (یا نشانی‌اش در پیامک‌ها فرق دارد).';
  }
  final counts = [
    '${_fa(s.total)} پیامک',
    if (s.accepted > 0) '${_fa(s.accepted)} ثبت',
    if (s.pending > 0) '${_fa(s.pending)} منتظر',
    if (s.rejected > 0) '${_fa(s.rejected)} رد',
  ].join(' • ');
  final where = s.accounts.isNotEmpty
      ? 'کارت: ${s.accounts.map(accountShortLabel).join('، ')}'
      : s.unknownAccount > 0
          ? 'حسابش هنوز ساخته نشده — تراشه‌ی «حسابِ تازه در پیامک‌ها» را بزن'
          : 'به هیچ کارتی نرفته (پیامک‌هایش تراکنش نیستند یا رد شده‌اند)';
  return [
    counts,
    where,
    if (s.accounts.isNotEmpty && s.unknownAccount > 0) '${_fa(s.unknownAccount)} پیامک با حسابِ ناشناخته',
  ].join('\n');
}

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

  Future<void> _manualAdd() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ManualSenderSheet(controller: _c),
    );
    if (added == true && mounted) _refresh();
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
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: kBankManualAddKey,
              onPressed: _manualAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('بانکم در فهرست نیست؛ افزودنِ دستی'),
            ),
          ),
          const SizedBox(height: 4),
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
                      isThreeLine: true,
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.address, textDirection: TextDirection.ltr),
                          Text(senderStatusText(_c.senderStatus(b)), key: bankStatusKey(b.id)),
                        ],
                      ),
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

/// «افزودنِ دستی»: نشانیِ فرستنده (همان که بالای پیامک نوشته) یا انتخاب از فرستنده‌های صندوق، و بانکش.
class _ManualSenderSheet extends StatefulWidget {
  final LedgerController controller;
  const _ManualSenderSheet({required this.controller});

  @override
  State<_ManualSenderSheet> createState() => _ManualSenderSheetState();
}

class _ManualSenderSheetState extends State<_ManualSenderSheet> {
  final _address = TextEditingController();
  String _bank = '';
  String? _error;
  bool _saving = false;
  late final Future<List<InboxSender>> _inbox = widget.controller.inboxSenders();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _pick(InboxSender s) {
    setState(() {
      _address.text = s.address;
      _bank = detectBank(s.address)?.id ?? _bank;
      _error = null;
    });
  }

  Future<void> _save() async {
    final address = _address.text.trim();
    if (address.isEmpty) {
      setState(() => _error = 'نشانیِ فرستنده را بنویس یا از فهرستِ پایین انتخاب کن');
      return;
    }
    if (findAllowedSender(widget.controller.banks, address) != null) {
      setState(() => _error = 'این فرستنده از قبل انتخاب شده');
      return;
    }
    setState(() => _saving = true);
    await widget.controller.allowSender(address, _bank.isEmpty ? null : _bank);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('افزودنِ دستیِ فرستنده‌ی بانک', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('همان نشانی‌ای که بالای پیامکِ بانک نوشته شده (مثلاً +98200045 یا BankMellat).',
                style: muted),
            const SizedBox(height: 12),
            TextField(
              key: kBankManualAddressKey,
              controller: _address,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: 'فرستنده', border: OutlineInputBorder()),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _bank,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'بانک', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: '', child: Text('نمی‌دانم')),
                for (final b in kBankRegistry) DropdownMenuItem(value: b.id, child: Text(b.name)),
              ],
              onChanged: (v) => setState(() => _bank = v ?? ''),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, key: kBankManualErrorKey, style: TextStyle(color: theme.colorScheme.error)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: kBankManualSaveKey,
              onPressed: _saving ? null : _save,
              child: const Text('بانک است؛ پیامک‌هایش خوانده شود'),
            ),
            const SizedBox(height: 16),
            Text('یا از فرستنده‌های پیامک‌های گوشی انتخاب کن', style: theme.textTheme.titleSmall),
            FutureBuilder<List<InboxSender>>(
              future: _inbox,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                      padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                }
                final list = snap.data!;
                if (list.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('پیامکی در گوشی خوانده نشد (مجوزِ پیامک؟).', style: muted),
                  );
                }
                return Column(children: [
                  for (final s in list.take(40))
                    ListTile(
                      key: inboxSenderKey(s.address),
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.address, textDirection: TextDirection.ltr, textAlign: TextAlign.end),
                      subtitle: Text(
                        [
                          '${_fa(s.count)} پیامک',
                          if (s.sample != null) s.sample!.replaceAll('\n', ' '),
                        ].join(' • '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _pick(s),
                    ),
                ]);
              },
            ),
          ],
        ),
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
