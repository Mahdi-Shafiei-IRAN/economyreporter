/// فرستنده‌های پیامک بانک: فقط پیامک این سرشماره‌ها/نام‌ها خودکار ثبت می‌شود.
/// پیشنهادها از پیامک‌های مبلغ‌دارِ گوشی و تراکنش‌های قبلاً ثبت‌شده می‌آیند؛ برای
/// فرستنده‌ای که بانک نیست، تراکنش‌های اشتباهی‌اش یک‌جا حذف می‌شود.
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../../core/sms/bank_registry.dart';
import '../../core/theme/app_theme.dart';
import '../dashboard/dashboard_controller.dart';
import '../transactions/transaction_details_sheet.dart';
import 'data/allowed_sender.dart';
import 'data/sender_candidates.dart';

const kSendersAddKey = Key('senders-add');
const kSenderAddressFieldKey = Key('sender-address');
const kSenderSaveKey = Key('sender-save');
const kSendersEmptyKey = Key('senders-empty');
const kCandidatesEmptyKey = Key('candidates-empty');

String _fa(int n) => toPersianDigits('$n');

/// فرستنده چپ‌به‌راست (تا «+98…» درست دیده شود) ولی هم‌تراز با متن فارسی.
Widget _address(String text, TextStyle? style) => Text(
      text,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.end,
      style: style,
    );

class SendersScreen extends StatefulWidget {
  final DashboardController controller;

  const SendersScreen({super.key, required this.controller});

  @override
  State<SendersScreen> createState() => _SendersScreenState();
}

class _SendersScreenState extends State<SendersScreen> {
  DashboardController get _c => widget.controller;
  late Future<List<SenderCandidate>> _candidates = _c.senderCandidates();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  void _refresh() {
    setState(() {
      _candidates = _c.senderCandidates();
    });
  }

  void _snack(String message) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// صاحبِ تراکنش‌های این فرستنده (پیش‌فرض: خودم).
  Future<({String name, String? userId})?> _pickOwner(String address) async {
    final me = (name: _c.meName ?? 'خودم', userId: _c.meUserId);
    final others = _c.members.where((m) => m.id != _c.meUserId).toList();
    if (others.isEmpty) return me; // فقط خودم — بی‌سروصدا همین.
    return showModalBottomSheet<({String name, String? userId})>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('تراکنش‌های «$address» مالِ کیست؟',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: Text('${me.name} (من)'),
              onTap: () => Navigator.pop(context, me),
            ),
            for (final m in others)
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(m.name),
                onTap: () => Navigator.pop(context, (name: m.name, userId: m.id)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _allow(SenderCandidate s) async {
    final owner = await _pickOwner(s.address);
    if (owner == null) return;
    await _c.addAllowedSender(s.address,
        bankId: s.bankId, ownerName: owner.name, ownerUserId: owner.userId);
    if (!mounted) return;
    _refresh();
    _snack('«${s.address}» مجاز شد؛ تراکنش‌هایش به ${owner.name} نسبت داده می‌شود.');
  }

  Future<void> _reject(SenderCandidate s) async {
    final editable = s.stored.where(_c.canEdit).length;
    if (editable > 0) {
      // تراکنش هم دارد؛ حذفشان تأیید بگیر.
      if (!await confirmInvalidate(context, count: editable)) return;
    } else {
      // فقط نادیده‌گرفتن؛ یک تأیید ساده.
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('«${s.address}» بانک نیست؟'),
          content: const Text(
              'این فرستنده از فهرست پیشنهادها برداشته می‌شود و دیگر نشان داده نمی‌شود.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('انصراف')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('بانک نیست')),
          ],
        ),
      );
      if (ok != true) return;
    }
    final n = await _c.rejectSender(s.address, s.stored);
    if (!mounted) return;
    _refresh();
    _snack(n > 0
        ? '«${s.address}» رد شد و ${_fa(n)} تراکنش اشتباهی حذف شد.'
        : '«${s.address}» از پیشنهادها برداشته شد.');
  }

  Future<void> _remove(AllowedSender s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('«${s.address}» از فهرست برداشته شود؟'),
        content: const Text('از این به بعد پیامک‌هایش ثبت نمی‌شود. تراکنش‌هایی که '
            'قبلاً ثبت شده‌اند می‌مانند.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('بردار')),
        ],
      ),
    );
    if (ok != true) return;
    await _c.removeAllowedSender(s.id);
    if (mounted) _refresh();
  }

  Future<void> _addManually() async {
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (_) => const _AddSenderDialog(),
    );
    if (result == null) return;
    final owner = await _pickOwner(result.$1);
    if (owner == null) return;
    await _c.addAllowedSender(result.$1,
        bankId: result.$2, ownerName: owner.name, ownerUserId: owner.userId);
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('فرستنده‌های پیامک بانک')),
        floatingActionButton: FloatingActionButton.extended(
          key: kSendersAddKey,
          onPressed: _addManually,
          icon: const Icon(Icons.add_rounded),
          label: const Text('افزودن دستی'),
        ),
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final allowed = _c.allowedSenders;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                const _Explain(),
                _Title('فرستنده‌های مجاز (${_fa(allowed.length)})'),
                if (allowed.isEmpty)
                  const _NoSenders(key: kSendersEmptyKey)
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < allowed.length; i++) ...[
                          if (i > 0) const Divider(indent: 56),
                          ListTile(
                            key: ValueKey('allowed-${allowed[i].address}'),
                            leading: Icon(Icons.verified_outlined,
                                color: theme.colorScheme.primary),
                            title: _address(allowed[i].address, null),
                            subtitle: Text([
                              allowed[i].bankId == null
                                  ? 'بانک نامشخص'
                                  : bankNameById(allowed[i].bankId!),
                              if (allowed[i].hasOwner) 'صاحب: ${allowed[i].ownerName}',
                            ].join(' • ')),
                            trailing: IconButton(
                              tooltip: 'برداشتن از فهرست',
                              icon: const Icon(Icons.remove_circle_outline_rounded),
                              onPressed: () => _remove(allowed[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                const _Title('پیشنهاد از پیامک‌های گوشی'),
                Text(
                  'فرستنده‌هایی که پیامکِ مبلغ‌دار داده‌اند ولی هنوز مجاز نیستند. متن '
                  'نمونه را ببین: اگر بانک است مجاز کن؛ اگر نیست (تبلیغ، فروشگاه، …) '
                  'تراکنش‌هایی را که قبلاً اشتباهی از آن ثبت شده حذف کن.',
                  style: muted,
                ),
                const SizedBox(height: 8),
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
                        key: kCandidatesEmptyKey,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'پیشنهادی نیست؛ همه‌ی فرستنده‌های مبلغ‌دار بررسی شده‌اند.',
                          textAlign: TextAlign.center,
                          style: muted,
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final s in list)
                          _CandidateCard(
                            key: ValueKey('candidate-${s.address}'),
                            candidate: s,
                            removable: s.stored.where(_c.canEdit).length,
                            onAllow: () => _allow(s),
                            onReject: () => _reject(s),
                          ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final String text;

  const _Title(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          )),
    );
  }
}

class _Explain extends StatelessWidget {
  const _Explain();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.secondaryContainer.withOpacity(0.6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: scheme.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('فقط پیامک بانک‌ها ثبت شود',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'فقط پیامکِ فرستنده‌هایی که این‌جا مجاز کنی (سرشماره یا نامی که بالای '
              'پیامک بانک نوشته شده) خودکار تراکنش ثبت می‌شود. پیامک هر فرستنده‌ی '
              'دیگری — تبلیغ، فروشگاه، اپراتور — حتی اگر مبلغ داشته باشد نادیده '
              'گرفته می‌شود.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSenders extends StatelessWidget {
  const _NoSenders({super.key});

  @override
  Widget build(BuildContext context) {
    final fin = FinanceColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fin.warningContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: fin.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'هنوز هیچ فرستنده‌ای مجاز نشده؛ تا مشخص نکنی هیچ پیامکی خودکار ثبت '
              'نمی‌شود. از پیشنهادهای پایین انتخاب کن یا دستی اضافه کن.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: fin.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final SenderCandidate candidate;

  /// تعداد تراکنش‌های ثبت‌شده‌ای که کاربر اجازه‌ی حذفشان را دارد.
  final int removable;
  final VoidCallback onAllow;
  final VoidCallback onReject;

  const _CandidateCard({
    super.key,
    required this.candidate,
    required this.removable,
    required this.onAllow,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final s = candidate;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counts = [
      if (s.inboxCount > 0) '${_fa(s.inboxCount)} پیامک مبلغ‌دار در گوشی',
      if (s.stored.isNotEmpty) '${_fa(s.stored.length)} تراکنش ثبت‌شده',
    ].join(' • ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.sms_outlined, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: _address(
                    s.address,
                    theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (s.bankId != null)
              Text('احتمالاً ${bankNameById(s.bankId!)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary)),
            Text(counts,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            if (s.sample != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  s.sample!.trim(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: ValueKey('allow-${s.address}'),
                  onPressed: onAllow,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('بانک است، مجاز کن'),
                ),
                TextButton.icon(
                  key: ValueKey('reject-${s.address}'),
                  style: TextButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: onReject,
                  icon: const Icon(Icons.block_rounded),
                  label: Text(removable > 0
                      ? 'بانک نیست؛ حذف ${_fa(removable)} تراکنش'
                      : 'بانک نیست'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddSenderDialog extends StatefulWidget {
  const _AddSenderDialog();

  @override
  State<_AddSenderDialog> createState() => _AddSenderDialogState();
}

class _AddSenderDialogState extends State<_AddSenderDialog> {
  final _address = TextEditingController();
  String? _bankId;
  bool _bankChosen = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _save() {
    final address = _address.text.trim();
    if (address.isEmpty) {
      setState(() => _error = 'سرشماره یا نام فرستنده را وارد کن');
      return;
    }
    Navigator.of(context).pop((address, _bankId));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('افزودن فرستنده‌ی بانک'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: kSenderAddressFieldKey,
            controller: _address,
            textDirection: TextDirection.ltr,
            autofocus: true,
            onChanged: (v) {
              // تا کاربر خودش بانک را انتخاب نکرده، از نام فرستنده حدس زده می‌شود.
              if (!_bankChosen) setState(() => _bankId = detectBank(v)?.id);
            },
            decoration: InputDecoration(
              labelText: 'سرشماره یا نام فرستنده',
              hintText: '+98200012345  یا  BankMellat',
              helperText: 'دقیقاً همان‌که بالای پیامک بانک نوشته شده',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: ValueKey(_bankId),
            value: _bankId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'بانک'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('نامشخص')),
              for (final b in kBankRegistry)
                DropdownMenuItem<String?>(
                  value: b.id,
                  child: Text(b.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() {
              _bankId = v;
              _bankChosen = true;
            }),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('انصراف'),
        ),
        FilledButton(
          key: kSenderSaveKey,
          onPressed: _save,
          child: const Text('افزودن'),
        ),
      ],
    );
  }
}
