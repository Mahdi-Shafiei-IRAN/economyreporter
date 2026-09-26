/// «منتظرِ تأیید» (طرح ۷.۲): هر پیامکِ بانک اینجا می‌ماند تا کاربر ثبت یا ردش کند.
/// کشیدن به راست = ثبت، به چپ = تراکنش نیست. «انتخابِ همه‌ی موارد بی‌مشکل» فقط انتخاب می‌کند؛
/// ثبت همیشه با دستِ کاربر است (ت۲).
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/ledger/models.dart';
import 'account_form.dart';
import 'entry_sheet.dart';
import 'ledger_controller.dart';
import 'ledger_text.dart';

const kPendingSelectReadyKey = Key('pending-select-ready');
const kPendingAcceptSelectedKey = Key('pending-accept-selected');
const kPendingRejectArchivedKey = Key('pending-reject-archived');
const kPendingEmptyKey = Key('pending-empty');

Key pendingCardKey(String key) => Key('pending-card-$key');
Key pendingAcceptKey(String key) => Key('pending-accept-$key');
Key pendingEditKey(String key) => Key('pending-edit-$key');
Key pendingNotTxKey(String key) => Key('pending-nottx-$key');
Key pendingDuplicateKey(String key) => Key('pending-dup-$key');
Key pendingNewAccountKey(String key) => Key('pending-newaccount-$key');

String _fa(int n) => toPersianDigits('$n');

class PendingScreen extends StatefulWidget {
  final LedgerController controller;

  const PendingScreen({super.key, required this.controller});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  final Set<String> _selected = {};
  LedgerController get _c => widget.controller;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _acceptSelected() async {
    final items = [for (final i in _c.pendingActive) if (_selected.contains(i.key)) i];
    final n = await _c.acceptMany(items);
    setState(_selected.clear);
    _snack('${_fa(n)} پیامک ثبت شد');
  }

  Future<void> _rejectArchived() async {
    final count = _c.pendingArchived.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ردِ ${_fa(count)} پیامکِ حساب‌های کنارگذاشته؟'),
        content: const Text('این پیامک‌ها «تراکنش نیست» علامت می‌خورند؛ بعداً هم می‌شود ثبتشان کرد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ردِ همه')),
        ],
      ),
    );
    if (ok == true) await _c.rejectArchived();
  }

  /// true = حذف از فهرست (ثبت یا رد شد).
  Future<bool> _swipe(SmsItem item, bool toRight) async {
    if (!toRight) {
      await _c.reject(item, RejectReason.notTx);
      _snack('«تراکنش نیست» ثبت شد');
      return true;
    }
    if (item.suggestion.isComplete) {
      await _c.acceptSuggested(item);
      _snack('ثبت شد');
      return true;
    }
    return showEntrySheet(context, _c, item: item);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final items = _c.pendingActive;
        _selected.retainWhere((k) => items.any((i) => i.key == k));
        final selecting = _selected.isNotEmpty;
        final ltr = Directionality.of(context) == TextDirection.ltr;
        return Scaffold(
          appBar: selecting
              ? AppBar(
                  leading: IconButton(
                    tooltip: 'لغوِ انتخاب',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(_selected.clear),
                  ),
                  title: Text('${_fa(_selected.length)} انتخاب‌شده'),
                  actions: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: FilledButton(
                        key: kPendingAcceptSelectedKey,
                        onPressed: _acceptSelected,
                        child: const Text('ثبتِ انتخاب‌شده‌ها'),
                      ),
                    ),
                  ],
                )
              : AppBar(
                  title: Text('منتظرِ تأیید (${_fa(items.length)})'),
                  actions: [
                    if (_c.readyToAccept.isNotEmpty)
                      TextButton(
                        key: kPendingSelectReadyKey,
                        onPressed: () =>
                            setState(() => _selected.addAll(_c.readyToAccept.map((i) => i.key))),
                        child: const Text('انتخابِ بی‌مشکل‌ها'),
                      ),
                  ],
                ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
            children: [
              if (_c.pendingArchived.isNotEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.archive_outlined),
                    title: Text('${_fa(_c.pendingArchived.length)} پیامکِ حساب‌های کنارگذاشته'),
                    subtitle: const Text('در شمارشِ منتظرها نیستند'),
                    trailing: TextButton(
                      key: kPendingRejectArchivedKey,
                      onPressed: _rejectArchived,
                      child: const Text('ردِ همه'),
                    ),
                  ),
                ),
              if (items.isEmpty)
                const Padding(
                  key: kPendingEmptyKey,
                  padding: EdgeInsets.all(40),
                  child: Text('هیچ پیامکی منتظرِ تأیید نیست.', textAlign: TextAlign.center),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(
                    'به راست بکش = ثبت، به چپ = تراکنش نیست. نگه داشتن = انتخاب.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              for (final item in items)
                Dismissible(
                  key: ValueKey('dismiss-${item.key}'),
                  direction: selecting ? DismissDirection.none : DismissDirection.horizontal,
                  // در راست‌به‌چپ، startToEnd یعنی کشیدن به چپ.
                  background: _SwipeBackground(accept: ltr),
                  secondaryBackground: _SwipeBackground(accept: !ltr),
                  confirmDismiss: (dir) =>
                      _swipe(item, (dir == DismissDirection.startToEnd) == ltr),
                  child: _PendingCard(
                    controller: _c,
                    item: item,
                    selected: _selected.contains(item.key),
                    onToggle: () => setState(() {
                      if (!_selected.remove(item.key)) _selected.add(item.key);
                    }),
                    selecting: selecting,
                    onDone: _snack,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  final bool accept;

  const _SwipeBackground({required this.accept});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final revealLeft = accept; // ثبت = کشیدن به راست = سمتِ چپ پیدا می‌شود
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: accept ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: revealLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(accept ? Icons.check_rounded : Icons.block_rounded),
          const SizedBox(width: 8),
          Text(accept ? 'ثبت' : 'تراکنش نیست'),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final LedgerController controller;
  final SmsItem item;
  final bool selected;
  final bool selecting;
  final VoidCallback onToggle;
  final void Function(String) onDone;

  const _PendingCard({
    required this.controller,
    required this.item,
    required this.selected,
    required this.selecting,
    required this.onToggle,
    required this.onDone,
  });

  Future<void> _reject(RejectReason reason) async {
    await controller.reject(item, reason);
    onDone(reason == RejectReason.duplicate ? '«تکراری» ثبت شد' : '«تراکنش نیست» ثبت شد');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final g = item.suggestion;
    final account = controller.account(g.accountId);
    final at = g.occurredAt ?? item.receivedAt;
    final notTx = notTxText(g.notTxReason);
    final reason = accountReasonText(g.accountReason);
    return Card(
      key: pendingCardKey(item.key),
      color: selected ? scheme.secondaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onLongPress: onToggle,
        onTap: selecting ? onToggle : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (selecting)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                          color: selected ? scheme.primary : scheme.outline),
                    ),
                  Expanded(
                    child: Text(
                      account == null ? 'حساب؟' : accountTitle(account),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    g.amountRial == null ? '—' : formatToman(g.amountRial!),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: g.kind == EntryKind.income ? Colors.green.shade700 : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  kindLabel(g.kind),
                  formatShortDateTime(at),
                  if (g.balanceRial != null) 'مانده ${formatToman(g.balanceRial!)}',
                ].join(' • '),
                style: theme.textTheme.bodySmall,
              ),
              if (reason != null || notTx != null || g.likelyDuplicate || g.unknownAccountNumber)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (notTx != null) _Hint(notTx, color: scheme.error),
                      if (g.likelyDuplicate) _Hint('احتمالاً تکراری', color: scheme.tertiary),
                      if (g.unknownAccountNumber)
                        _Hint('شماره‌ی حساب/کارتِ ناشناخته', color: scheme.tertiary),
                      if (reason != null) _Hint(reason, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              if (item.body != null) ...[
                const SizedBox(height: 8),
                Text(
                  item.body!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (!selecting)
                Wrap(
                  spacing: 4,
                  children: [
                    if (g.unknownAccountNumber)
                      TextButton.icon(
                        key: pendingNewAccountKey(item.key),
                        onPressed: () => showAccountForm(context, controller,
                            prefill: controller.prefillFrom(item)),
                        icon: const Icon(Icons.add_card_rounded, size: 18),
                        label: const Text('حسابِ تازه است'),
                      ),
                    if (g.isComplete)
                      FilledButton.tonal(
                        key: pendingAcceptKey(item.key),
                        onPressed: () async {
                          await controller.acceptSuggested(item);
                          onDone('ثبت شد');
                        },
                        child: const Text('ثبت'),
                      ),
                    TextButton(
                      key: pendingEditKey(item.key),
                      onPressed: () => showEntrySheet(context, controller, item: item),
                      child: Text(g.isComplete ? 'ویرایش و ثبت' : 'ثبت…'),
                    ),
                    if (g.looksLikeTx)
                      TextButton(
                        key: pendingNotTxKey(item.key),
                        onPressed: () => _reject(RejectReason.notTx),
                        child: const Text('تراکنش نیست'),
                      )
                    else
                      FilledButton.tonal(
                        key: pendingNotTxKey(item.key),
                        onPressed: () => _reject(RejectReason.notTx),
                        child: const Text('تراکنش نیست'),
                      ),
                    TextButton(
                      key: pendingDuplicateKey(item.key),
                      onPressed: () => _reject(RejectReason.duplicate),
                      child: const Text('تکراری است'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  final Color color;

  const _Hint(this.text, {required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
      );
}
