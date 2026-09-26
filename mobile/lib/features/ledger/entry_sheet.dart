/// برگه‌ی تراکنش (طرح ۷.۵، ۷.۶ و ۱۲.۶): «ثبت / ویرایش و ثبت»ِ یک پیامک، افزودنِ دستی (با پیش‌پر برای
/// «تراکنشِ جاافتاده»)، یا ویرایش/حذفِ یک تراکنشِ ثبت‌شده. دسته‌ها و «انتقال بینِ حساب‌های خودم» هم اینجاست.
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
const kEntryTransferKey = Key('entry-transfer');
const kEntryDeleteKey = Key('entry-delete');
Key entryCategoryKey(String id) => Key('entry-cat-$id');

/// پیش‌پرِ افزودنِ دستی (مثلاً «تراکنشِ جاافتاده» از پنجره‌ی اختلاف).
class EntryDraft {
  final String? accountId;
  final EntryKind? kind;
  final int? amountRial;
  final DateTime? at;
  const EntryDraft({this.accountId, this.kind, this.amountRial, this.at});
}

/// [item] = پیامکی که ثبت می‌شود؛ [entry] = ویرایشِ تراکنشِ ثبت‌شده؛ هیچ‌کدام = افزودنِ دستی.
/// true یعنی ذخیره یا حذف شد.
Future<bool> showEntrySheet(BuildContext context, LedgerController controller,
    {SmsItem? item, Entry? entry, EntryDraft? draft}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _EntrySheet(controller: controller, item: item, entry: entry, draft: draft),
  );
  return saved ?? false;
}

class _EntrySheet extends StatefulWidget {
  final LedgerController controller;
  final SmsItem? item;
  final Entry? entry;
  final EntryDraft? draft;

  const _EntrySheet({required this.controller, this.item, this.entry, this.draft});

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  LedgerController get _c => widget.controller;
  String? _accountId;
  EntryKind? _kind;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late DateTime _day; // آغازِ روز به وقتِ ایران (UTC)
  late Duration _clock; // ساعتِ همان روز
  late final List<DateTime> _days;
  final Set<String> _categories = {};
  bool _categoriesTouched = false;
  bool _transfer = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.item, entry = widget.entry, draft = widget.draft;
    final g = item?.suggestion;
    final wanted = entry?.accountId ?? draft?.accountId ?? g?.accountId;
    final account = _c.account(wanted);
    _accountId = (account != null && (!account.archived || entry != null)) ? account.id : null;
    if (_accountId == null && _c.activeAccounts.length == 1) {
      _accountId = _c.activeAccounts.single.account.id;
    }
    _kind = entry?.kind ?? draft?.kind ?? g?.kind;
    _amount = TextEditingController(
        text: tomanInputText(entry?.amountRial ?? draft?.amountRial ?? g?.amountRial));
    _note = TextEditingController(text: entry?.note ?? '');
    _transfer = entry?.isTransfer ?? false;
    final at = entry?.occurredAt ?? draft?.at ?? g?.occurredAt ?? item?.receivedAt ?? _c.now;
    _day = JalaliDate.fromDateTime(at).toUtcStart();
    _clock = at.difference(_day);
    final today = JalaliDate.fromDateTime(_c.now).toUtcStart();
    _days = [for (var i = 0; i < 45; i++) today.subtract(Duration(days: i))];
    if (!_days.contains(_day)) _days.add(_day);
    if (entry != null) {
      _categories.addAll([for (final p in _c.allocations[entry.id] ?? const []) p.categoryId]);
    } else if (item != null) {
      _c.suggestedCategoryIds(item).then((ids) {
        if (mounted && !_categoriesTouched) setState(() => _categories.addAll(ids));
      }).ignore();
    }
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

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('این تراکنش حذف شود؟'),
        content: Text(widget.entry!.smsKey != null
            ? 'پیامکش «تراکنش نیست» علامت می‌خورد؛ بعداً از پنجره‌ی اختلاف هم می‌شود دوباره ثبتش کرد.'
            : 'از موجودی و گزارش برداشته می‌شود.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await _c.deleteEntry(widget.entry!.id);
    if (mounted) Navigator.of(context).pop(true);
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
    final note = _note.text.trim();
    final at = _day.add(_clock);
    final cats = _categories.toList();
    try {
      final item = widget.item, entry = widget.entry;
      if (entry != null) {
        await _c.updateEntry(
            entry.copyWith(
                accountId: _accountId,
                kind: _kind,
                amountRial: amount,
                occurredAt: at,
                note: note,
                isTransfer: _transfer),
            categoryIds: cats);
      } else if (item != null) {
        await _c.accept(item,
            accountId: _accountId!,
            kind: _kind!,
            amountRial: amount!,
            occurredAt: at,
            note: note.isEmpty ? null : note,
            isTransfer: _transfer,
            categoryIds: cats);
      } else {
        await _c.addManual(
            accountId: _accountId!,
            kind: _kind!,
            amountRial: amount!,
            occurredAt: at,
            note: note.isEmpty ? null : note,
            isTransfer: _transfer,
            categoryIds: cats);
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
    final item = widget.item, entry = widget.entry;
    final accounts = [
      ..._c.activeAccounts.map((v) => v.account),
      if (entry != null && _c.account(entry.accountId)?.archived == true) _c.account(entry.accountId)!,
    ];
    final smsBody = item?.body ?? (entry?.smsKey == null ? null : _c.smsItemByKey(entry!.smsKey!)?.body);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                      entry != null
                          ? 'ویرایشِ تراکنش'
                          : item != null
                              ? 'ثبتِ پیامک'
                              : 'افزودنِ تراکنش',
                      style: theme.textTheme.titleLarge),
                ),
                if (entry != null)
                  IconButton(
                    key: kEntryDeleteKey,
                    tooltip: 'حذف',
                    icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
                    onPressed: _delete,
                  ),
              ],
            ),
            if (smsBody != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(smsBody, style: theme.textTheme.bodySmall),
              ),
            ],
            const SizedBox(height: 16),
            if (accounts.isEmpty)
              Text('هنوز حسابی نیست؛ اول از صفحه‌ی اصلی حساب بساز.',
                  style: TextStyle(color: theme.colorScheme.error))
            else
              DropdownButtonFormField<String>(
                key: kEntryAccountKey,
                value: _accountId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'حساب'),
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text('${accountTitle(a)} — ${a.ownerName}', overflow: TextOverflow.ellipsis),
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
            if (_c.categories.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('دسته (اختیاری؛ چند تا هم می‌شود)', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final cat in _c.categories)
                    FilterChip(
                      key: entryCategoryKey(cat.id),
                      label: Text(cat.name),
                      selected: _categories.contains(cat.id),
                      onSelected: (on) => setState(() {
                        _categoriesTouched = true;
                        on ? _categories.add(cat.id) : _categories.remove(cat.id);
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              key: kEntryTransferKey,
              contentPadding: EdgeInsets.zero,
              title: const Text('انتقال بینِ حساب‌های خودم'),
              subtitle: const Text('موجودی را عوض می‌کند ولی درآمد/هزینه حساب نمی‌شود'),
              value: _transfer,
              onChanged: (v) => setState(() => _transfer = v),
            ),
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
              label: Text(entry != null ? 'ذخیره' : 'ثبت'),
            ),
          ],
        ),
      ),
    );
  }
}
