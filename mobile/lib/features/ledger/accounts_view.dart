/// «حساب‌ها» (قدمِ ۲): حساب‌هایی که در پیامک‌ها پیدا شده (مالِ من است / پیگیری نکن) و حساب‌هایی
/// که هنوز «موجودیِ الان» ندارند.
library;

import 'package:flutter/material.dart';

import '../../core/family/family_api.dart';
import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/ledger/account_candidates.dart';
import '../../core/sms/bank_registry.dart';
import 'account_card.dart';
import 'ledger_controller.dart';
import 'ledger_text.dart';

Key candidateAcceptKey(String key) => Key('candidate-accept-$key');
Key candidateDismissKey(String key) => Key('candidate-dismiss-$key');
const kCandidateBalanceKey = Key('candidate-balance');
const kCandidateSaveKey = Key('candidate-save');

String _fa(int n) => toPersianDigits('$n');

String candidateTitle(AccountCandidate c) => [
      c.bankId == null ? 'بانک؟' : bankNameById(c.bankId!),
      if (c.cardLast4 != null) 'کارت ${toPersianDigits(c.cardLast4!)}',
      if (c.accountRef != null) 'حساب ${toPersianDigits(c.accountRef!)}',
      if (!c.hasNumber) '(بی‌شماره)',
    ].join(' • ');

class LedgerAccountsView extends StatelessWidget {
  final LedgerController controller;

  const LedgerAccountsView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final c = controller;
        final needAnchor = [for (final v in c.activeAccounts) if (v.needsAnchor) v];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (c.accountCandidates.isNotEmpty) ...[
              Text('این حساب‌ها در پیامک‌هایت پیدا شد. مالِ توست؟', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text('«مالِ من است» حساب را با آخرین مانده‌ی بانک می‌سازد؛ «پیگیری نکن» پیامک‌هایش را '
                  'کنار می‌گذارد.', style: muted),
              const SizedBox(height: 8),
              for (final cand in c.accountCandidates) _CandidateCard(controller: c, candidate: cand),
            ],
            if (needAnchor.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('موجودیِ الانِ این حساب‌ها را تأیید کن', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final v in needAnchor) LedgerAccountCard(controller: c, view: v),
            ],
            if (c.accountCandidates.isEmpty && needAnchor.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('حساب‌ها آماده‌اند.', textAlign: TextAlign.center, style: muted),
              ),
          ],
        );
      },
    );
  }
}

class _CandidateCard extends StatelessWidget {
  final LedgerController controller;
  final AccountCandidate candidate;

  const _CandidateCard({required this.controller, required this.candidate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = candidate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(candidateTitle(c), style: theme.textTheme.titleMedium),
            Text(
              [
                '${_fa(c.smsCount)} پیامک',
                if (c.lastBalanceRial != null)
                  'آخرین مانده ${formatToman(c.lastBalanceRial!)} (${formatShortDateTime(c.lastBalanceAt!)})',
              ].join(' • '),
              style: theme.textTheme.bodySmall,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: candidateDismissKey(c.key),
                  onPressed: () => controller.dismissCandidate(c),
                  child: const Text('پیگیری نکن'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  key: candidateAcceptKey(c.key),
                  onPressed: () => _confirm(context),
                  child: const Text('مالِ من است'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// صاحب (پیش‌فرض خودم) و «موجودیِ الان» (پیش‌فرض آخرین مانده) — یک برگه‌ی کوتاه.
  Future<void> _confirm(BuildContext context) async {
    final people = controller.who;
    final me = (name: people.meName ?? 'من', id: people.meUserId);
    final others = <({String name, String? id})>[
      for (final FamilyMember m in people.members) if (m.id != me.id) (name: m.name, id: m.id),
    ];
    var owner = me;
    final balance = TextEditingController(text: tomanInputText(candidate.lastBalanceRial));
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(candidateTitle(candidate), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (others.isNotEmpty) ...[
                const Text('مالِ کیست؟'),
                Wrap(spacing: 8, children: [
                  for (final o in [me, ...others])
                    ChoiceChip(
                      label: Text(o == me ? '${o.name} (من)' : o.name),
                      selected: owner == o,
                      onSelected: (_) => setState(() => owner = o),
                    ),
                ]),
                const SizedBox(height: 12),
              ],
              TextField(
                key: kCandidateBalanceKey,
                controller: balance,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'موجودیِ الان (تومان)',
                  helperText: 'طبقِ آخرین پیامکِ بانک؛ اگر فرق دارد درستش کن',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: kCandidateSaveKey,
                onPressed: () async {
                  final text = balance.text.trim();
                  final rial = parseTomanInput(text);
                  if (text.isNotEmpty && rial == null) {
                    setState(() => error = 'عدد را درست وارد کن');
                    return;
                  }
                  await controller.acceptCandidate(candidate,
                      ownerName: owner.name, ownerUserId: owner.id, balanceRial: rial);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('اضافه کن'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LedgerAccountsScreen extends StatelessWidget {
  final LedgerController controller;
  const LedgerAccountsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('حساب‌ها')),
        body: LedgerAccountsView(controller: controller),
      );
}
