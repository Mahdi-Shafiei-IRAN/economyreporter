/// برگه‌ی «ثبت / ویرایش و ثبت»ِ یک پیامک، یا «افزودنِ دستی» (طرح ۷.۵ و ۷.۶).
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/ledger/models.dart';
import '../../core/sms/jalali.dart';
import 'ledger_controller.dart';
import 'ledger_text.dart';

const kEntryAccountKey = Key('entry-account');
const kEntryKindKey = Key('entry-kind');
const kEntryAmountKey = Key('entry-amount');
const kEntryDayKey = Key('entry-day');
const kEntryNoteKey = Key('entry-note');
const kEntrySaveKey = Key('entry-save');
const kEntryErrorKey = Key('entry-error');

/// [item] = پیامکی که ثبت می‌شود؛ null = افزودنِ دستی. true یعنی ذخیره شد.
Future<bool> showEntrySheet(BuildContext context, LedgerController controller,
    {SmsItem? item}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EntrySheet(controller: controller, item: item),
  );
  return saved ?? false;
}

class _EntrySheet extends StatefulWidget {
  final LedgerController controller;
  final SmsItem? item;

  const _EntrySheet({required this.controller, this.item});

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  LedgerController get _c => widget.controller;
  String? _accountId;
  EntryKind? _kind;
  late final TextEditingController _amount;
  final _note = TextEditingController();
  late DateTime _day; // آغازِ روز به وقتِ ایران (UTC)
  late Duration _clock; // ساعتِ همان روز
  late final List<DateTime> _days;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final g = widget.item?.suggestion;
    final suggested = _c.account(g?.accountId);
    _accountId = (suggested != null && !suggested.archived) ? suggested.id : null;
    if (_accountId == null && _c.activeAccounts.length == 1) {
      _accountId = _c.activeAccounts.single.account.id;
    }
    _kind = g?.kind;
    _amount = TextEditingController(text: tomanInputText(g?.amountRial));
    final at = g?.occurredAt ?? widget.item?.receivedAt ?? _c.now;
    _day = JalaliDate.fromDateTime(at).toUtcStart();
    _clock = at.difference(_day);
    final today = JalaliDate.fromDateTime(_c.now).toUtcStart();
    _days = [for (var i = 0; i < 45; i++) today.subtract(Duration(days: i))];
    if (!_days.contains(_day)) _days.add(_day);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _clock.inHours, minute: _clock.inMinutes % 60),
    );
    if (picked != null) {
      setState(() => _clock = Duration(hours: picked.hour, minutes: picked.minute));
    }
  }

  Future<void> _save() async {
    final amount = parseTomanInput(_amount.text);
    final error = _accountId == null
        ? 'حساب را انتخاب کن'
        : _kind == null
            ? 'واریز است یا برداشت؟'
            : (amount == null || amount <= 0)
                ? 'مبلغ را وارد کن'
                : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final at = _day.add(_clock);
    try {
      final item = widget.item;
      if (item != null) {
        await _c.accept(item,
            accountId: _accountId!, kind: _kind!, amountRial: amount!, occurredAt: at, note: note);
      } else {
        await _c.addManual(
            accountId: _accountId!, kind: _kind!, amountRial: amount!, occurredAt: at, note: note);
      }
      if (mounted) Navigator.of(context).pop(true);
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
    final item = widget.item;
    final accounts = _c.activeAccounts;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item == null ? 'افزودنِ تراکنش' : 'ثبتِ پیامک',
                style: theme.textTheme.titleLarge),
            if (item?.body != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(item!.body!, style: theme.textTheme.bodySmall),
              ),
            ],
            const SizedBox(height: 16),
            if (accounts.isEmpty)
              Text('هنوز حسابی نیست؛ اول از صفحه‌ی اصلی «حسابِ تازه» بساز.',
                  style: TextStyle(color: theme.colorScheme.error))
            else
              DropdownButtonFormField<String>(
                key: kEntryAccountKey,
                value: _accountId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'حساب'),
                items: [
                  for (final v in accounts)
                    DropdownMenuItem(
                      value: v.account.id,
                      child: Text('${accountTitle(v.account)} — ${v.account.ownerName}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) => setState(() => _accountId = id),
              ),
            const SizedBox(height: 16),
            SegmentedButton<EntryKind>(
              key: kEntryKindKey,
              emptySelectionAllowed: true,
              segments: const [
                ButtonSegment(
                    value: EntryKind.expense,
                    label: Text('برداشت / هزینه'),
                    icon: Icon(Icons.north_east_rounded)),
                ButtonSegment(
                    value: EntryKind.income,
                    label: Text('واریز / درآمد'),
                    icon: Icon(Icons.south_west_rounded)),
              ],
              selected: {if (_kind != null) _kind!},
              onSelectionChanged: (s) => setState(() => _kind = s.isEmpty ? null : s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              key: kEntryAmountKey,
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'مبلغ (تومان)'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<DateTime>(
                    key: kEntryDayKey,
                    value: _day,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'روز'),
                    items: [
                      for (final d in _days)
                        DropdownMenuItem(value: d, child: Text(formatDayHeader(d))),
                    ],
                    onChanged: (d) => setState(() => _day = d ?? _day),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_rounded),
                  label: Text(formatClock(_day.add(_clock))),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              key: kEntryNoteKey,
              controller: _note,
              decoration: const InputDecoration(labelText: 'یادداشت (اختیاری)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  key: kEntryErrorKey, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              key: kEntrySaveKey,
              onPressed: _saving || accounts.isEmpty ? null : _save,
              icon: const Icon(Icons.check_rounded),
              label: const Text('ثبت'),
            ),
          ],
        ),
      ),
    );
  }
}
