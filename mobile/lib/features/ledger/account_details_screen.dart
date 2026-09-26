/// جزئیاتِ حساب (طرح ۷.۴ و ۱۲.۶): موجودی، خط‌زمانِ تراکنش‌ها و نقطه‌های مانده، و کارتِ اختلاف
/// سرِ جای خودش با پیشنهادهایش. هیچ پیشنهادی خودکار اجرا نمی‌شود (I1).
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/ledger/ledger_math.dart';
import '../../core/ledger/models.dart';
import '../../core/ledger/suggestion.dart';
import 'account_form.dart';
import 'entry_sheet.dart';
import 'ledger_controller.dart';
import 'ledger_text.dart';

const kDetailsReconcileKey = Key('details-reconcile');
Key windowCardKey(int i) => Key('window-$i');
Key windowAcceptSmsKey(String smsKey) => Key('window-accept-$smsKey');
Key windowFlipKey(String entryId) => Key('window-flip-$entryId');
Key windowAddMissingKey(int i) => Key('window-missing-$i');
Key windowAdjustKey(int i) => Key('window-adjust-$i');
Key entryRowKey(String id) => Key('entry-row-$id');
const kAdjustNoteKey = Key('adjust-note');
const kAdjustSaveKey = Key('adjust-save');

String _signed(int rial) => '${rial >= 0 ? '+' : '−'}${formatToman(rial.abs())}';

class AccountDetailsScreen extends StatelessWidget {
  final LedgerController controller;
  final String accountId;

  const AccountDetailsScreen({super.key, required this.controller, required this.accountId});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final v = controller.view(accountId);
        if (v == null) return const Scaffold(body: SizedBox.shrink());
        final theme = Theme.of(context);
        final seq = controller.ledgerOf(accountId);
        // حسابِ عضوِ دیگر: فقط دیدنی؛ درست کردنِ اختلافش کارِ خودش است.
        final readOnly = !controller.canEdit(accountId);
        final windows = readOnly ? const <DiscrepancyWindow>[] : controller.windowsOf(accountId);
        final windowAt = {for (var i = 0; i < windows.length; i++) windows[i].to: i};
        final rows = <Widget>[];
        String? lastDay;
        for (final item in seq.reversed) {
          final day = formatDayHeader(item.at);
          if (day != lastDay) {
            lastDay = day;
            rows.add(Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(day, style: theme.textTheme.labelLarge),
            ));
          }
          final wi = windowAt[item];
          if (wi != null) {
            rows.add(_WindowCard(
                controller: controller, window: windows[wi], index: wi, hints: controller.hintsFor(windows[wi])));
          }
          rows.add(switch (item) {
            EntryItem(:final entry) => _EntryRow(controller: controller, entry: entry, readOnly: readOnly),
            CheckpointItem(:final checkpoint) =>
              _CheckpointRow(controller: controller, checkpoint: checkpoint, readOnly: readOnly),
          });
        }
        final balance = v.balance;
        return Scaffold(
          appBar: AppBar(title: Text(accountTitle(v.account))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(accountSubtitle(v.account), style: theme.textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Text(balance == null ? 'موجودی نامعلوم' : formatToman(balance.balanceRial),
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      if (balance != null)
                        Text('از ${formatShortDateTime(balance.anchor.at)}',
                            style: theme.textTheme.labelSmall),
                      const SizedBox(height: 8),
                      if (readOnly)
                        Text('حسابِ ${v.account.ownerName}؛ فقط دیدنی.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                      else
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: OutlinedButton.icon(
                            key: kDetailsReconcileKey,
                            onPressed: () =>
                                showBalanceDialog(context, controller, v, reconcile: balance != null),
                            icon: const Icon(Icons.fact_check_outlined),
                            label: Text(balance == null ? 'موجودیِ الانش را وارد کن' : 'موجودیِ واقعی را وارد کن'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (windows.isEmpty && balance != null && !readOnly)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                  child: Text('همه‌ی تراکنش‌ها با مانده‌های بانک می‌خوانند.',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade700)),
                ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('هنوز تراکنشی ثبت نشده.', textAlign: TextAlign.center),
                ),
              ...rows,
            ],
          ),
        );
      },
    );
  }
}

class _EntryRow extends StatelessWidget {
  final LedgerController controller;
  final Entry entry;
  final bool readOnly;

  const _EntryRow({required this.controller, required this.entry, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    final cats = controller.allocations[e.id] ?? const [];
    final title = (e.note?.trim().isNotEmpty ?? false)
        ? e.note!.trim()
        : cats.isNotEmpty
            ? cats.map((c) => c.name).join('، ')
            : switch (e.source) {
                EntrySource.sms => kindLabel(e.kind),
                EntrySource.manual => '${kindLabel(e.kind)} (دستی)',
                EntrySource.adjustment => 'اصلاح',
              };
    final income = e.kind == EntryKind.income;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        key: entryRowKey(e.id),
        dense: true,
        leading: Icon(
          e.isTransfer
              ? Icons.swap_horiz_rounded
              : income
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
          color: income ? Colors.green.shade700 : theme.colorScheme.error,
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          formatClock(e.occurredAt),
          if (e.bankBalanceAfter != null) 'مانده ${formatToman(e.bankBalanceAfter!)}',
          if (e.isTransfer) 'انتقال',
          if (cats.isEmpty && !income && !e.isTransfer) 'بی‌دسته',
        ].join(' • ')),
        trailing: Text(_signed(e.signed),
            style: theme.textTheme.titleSmall?.copyWith(
                color: income ? Colors.green.shade700 : null, fontWeight: FontWeight.w700)),
        onTap: readOnly ? null : () => showEntrySheet(context, controller, entry: e),
      ),
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  final LedgerController controller;
  final Checkpoint checkpoint;
  final bool readOnly;

  const _CheckpointRow({required this.controller, required this.checkpoint, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(Icons.flag_outlined, color: theme.colorScheme.primary),
      title: Text('موجودی را وارد کردی: ${formatToman(checkpoint.balanceRial)}'),
      subtitle: Text(formatClock(checkpoint.at)),
      trailing: readOnly ? null : IconButton(
        tooltip: 'حذف',
        icon: const Icon(Icons.close_rounded, size: 18),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('این موجودیِ واردشده حذف شود؟'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
              ],
            ),
          );
          if (ok == true) await controller.deleteCheckpoint(checkpoint.id);
        },
      ),
    );
  }
}

/// «اینجا X کم/زیاد است» — نارنجی: پیامکِ منتظر در بازه هست؛ قرمز: بی‌توضیح.
class _WindowCard extends StatelessWidget {
  final LedgerController controller;
  final DiscrepancyWindow window;
  final int index;
  final WindowHints hints;

  const _WindowCard(
      {required this.controller, required this.window, required this.index, required this.hints});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = window;
    final orange = hints.hasPendingInRange;
    final color = orange ? Colors.orange.shade800 : theme.colorScheme.error;
    final diff = w.diffRial;
    final missingKind = diff > 0 ? EntryKind.income : EntryKind.expense;
    return Card(
      key: windowCardKey(index),
      color: color.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.error_outline_rounded, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  diff < 0
                      ? '${formatToman(-diff)} برداشتِ ثبت‌نشده'
                      : '${formatToman(diff)} واریزِ ثبت‌نشده',
                  style: theme.textTheme.titleSmall?.copyWith(color: color),
                ),
              ),
            ]),
            Text(
              'بانک بینِ ${formatShortDateTime(w.start)} و ${formatShortDateTime(w.end)} این را نشان می‌دهد ولی '
              'در تراکنش‌ها نیست${orange ? '؛ شاید فقط پیامکی هنوز تأیید نشده' : ''}.',
              style: theme.textTheme.bodySmall,
            ),
            for (final key in hints.explainingSmsKeys)
              if (controller.smsItemByKey(key) case final SmsItem sms)
                _HintRow(
                  text: 'پیامکِ ${formatToman(sms.suggestion.amountRial ?? 0)}، '
                      '${formatShortDateTime(sms.suggestion.occurredAt ?? sms.receivedAt)}'
                      '${sms.status == SmsStatus.rejected ? ' (ردش کرده بودی)' : ' (هنوز منتظر)'}',
                  action: 'ثبتش کن',
                  buttonKey: windowAcceptSmsKey(key),
                  onPressed: () => controller.accept(sms,
                      accountId: w.accountId,
                      kind: sms.suggestion.kind ?? missingKind,
                      amountRial: sms.suggestion.amountRial!),
                ),
            for (final e in w.entries)
              if (hints.reversedEntryIds.contains(e.id))
                _HintRow(
                  text: '«${formatToman(e.amountRial)}» شاید ${e.kind == EntryKind.income ? 'برداشت' : 'واریز'} بوده',
                  action: 'نوعش را برعکس کن',
                  buttonKey: windowFlipKey(e.id),
                  onPressed: () => controller.flipKind(e),
                ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton(
                  key: windowAddMissingKey(index),
                  onPressed: () => showEntrySheet(context, controller,
                      draft: EntryDraft(
                          accountId: w.accountId,
                          kind: missingKind,
                          amountRial: diff.abs(),
                          at: controller.gapTime(w))),
                  child: const Text('تراکنشِ جاافتاده را اضافه کن'),
                ),
                TextButton(
                  key: windowAdjustKey(index),
                  onPressed: () => _adjust(context),
                  child: const Text('«اصلاح» ثبت کن'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _adjust(BuildContext context) async {
    final note = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('«اصلاح» ${_signed(window.diffRial)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('وقتی نمی‌دانی چه بوده (کارمزد، سود، …). یک تراکنشِ دیدنی با همین مبلغ ثبت می‌شود.'),
              TextField(
                key: kAdjustNoteKey,
                controller: note,
                autofocus: true,
                decoration: InputDecoration(labelText: 'یادداشت (لازم)', errorText: error),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
            FilledButton(
              key: kAdjustSaveKey,
              onPressed: () async {
                if (note.text.trim().isEmpty) {
                  setState(() => error = 'بنویس بابتِ چیست');
                  return;
                }
                await controller.addAdjustment(window, note.text.trim());
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('ثبت'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  final String text;
  final String action;
  final Key buttonKey;
  final VoidCallback onPressed;

  const _HintRow(
      {required this.text, required this.action, required this.buttonKey, required this.onPressed});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          const Icon(Icons.lightbulb_outline_rounded, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
          FilledButton.tonal(key: buttonKey, onPressed: onPressed, child: Text(action)),
        ]),
      );
}

