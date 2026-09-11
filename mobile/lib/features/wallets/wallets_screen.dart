/// کارت‌ها و حساب‌های اعضا: هر کارت به صاحبش وصل می‌شود تا تراکنش‌ها زیر نام او
/// بیایند؛ اگر صاحب در اپ حساب دارد، فقط خودش تراکنش‌های آن کارت را ویرایش می‌کند.
///
/// پیامکِ بیشتر بانک‌ها شماره‌ی کارت ندارد (حساب دارد یا هیچ)؛ پس کارت را می‌شود فقط
/// با بانک هم ثبت کرد تا همه‌ی پیامک‌های بی‌شماره‌ی آن بانک مال همین کارت شود.
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../../core/sms/bank_registry.dart';
import '../../core/sms/digit_utils.dart';
import '../dashboard/dashboard_controller.dart';
import '../transactions/widgets/tx_widgets.dart';
import 'data/wallet.dart';

const kWalletAddFabKey = Key('wallet-add-fab');
const kWalletOwnerFieldKey = Key('wallet-owner');
const kWalletLabelFieldKey = Key('wallet-label');
const kWalletCardFieldKey = Key('wallet-card');
const kWalletAccountFieldKey = Key('wallet-account');
const kWalletSaveKey = Key('wallet-save');
const kWalletsEmptyKey = Key('wallets-empty');
const kWalletErrorKey = Key('wallet-error');

/// فرم افزودن/ویرایش کارت. [bankId]/[cardLast4]/[accountRef] برای پیش‌پرکردن
/// از روی یک کارتِ بی‌صاحب.
Future<void> showWalletForm(
  BuildContext context,
  DashboardController controller, {
  Wallet? wallet,
  String? bankId,
  String? cardLast4,
  String? accountRef,
}) async {
  final result = await showModalBottomSheet<Wallet>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _WalletForm(
      controller: controller,
      initial: wallet ??
          Wallet(
            id: '',
            ownerName: '',
            label: '',
            bankId: bankId,
            cardLast4: cardLast4,
            accountRef: accountRef,
          ),
      isNew: wallet == null,
    ),
  );
  if (result == null) return;
  if (wallet == null) {
    await controller.addWallet(result);
  } else {
    await controller.updateWallet(result);
  }
}

class WalletsScreen extends StatelessWidget {
  final DashboardController controller;

  const WalletsScreen({super.key, required this.controller});

  Future<void> _delete(BuildContext context, Wallet w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف «${w.label}»؟'),
        content: const Text(
            'تراکنش‌ها حذف نمی‌شوند؛ فقط دیگر به این شخص وصل نیستند و زیر «نامشخص» می‌آیند.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) await controller.deleteWallet(w.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('کارت‌ها و حساب‌ها')),
      floatingActionButton: FloatingActionButton.extended(
        key: kWalletAddFabKey,
        onPressed: () => showWalletForm(context, controller),
        icon: const Icon(Icons.add_card_rounded),
        label: const Text('افزودن کارت'),
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final wallets = controller.wallets;
          if (wallets.isEmpty) {
            return const Center(
              key: kWalletsEmptyKey,
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'هنوز کارت/حسابی ثبت نشده.\nبا «افزودن کارت»، کارت‌های خانواده را با '
                  'نام صاحبشان ثبت کن تا هر تراکنش زیر نام همان شخص بیاید.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final byOwner = <String, List<Wallet>>{};
          for (final w in wallets) {
            byOwner.putIfAbsent(w.ownerName, () => []).add(w);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text(
                'هر کارت را به صاحبش وصل کن. اگر صاحب کارت در اپ حساب دارد، او را از '
                'اعضا انتخاب کن تا فقط خودش بتواند تراکنش‌های آن کارت را ویرایش و '
                'دسته‌بندی کند؛ بقیه فقط می‌بینند. اگر پیامک‌های بانک شماره‌ی کارت '
                'ندارند، کافی است فقط بانک را انتخاب کنی.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              for (final entry in byOwner.entries) ...[
                SectionHeader(
                  title: entry.key,
                  trailing: entry.value.first.ownerUserId != null ? 'عضو اپ' : 'بدون حساب در اپ',
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                ),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < entry.value.length; i++) ...[
                        if (i > 0) const Divider(indent: 56),
                        _WalletTile(
                          wallet: entry.value[i],
                          onTap: () =>
                              showWalletForm(context, controller, wallet: entry.value[i]),
                          onDelete: () => _delete(context, entry.value[i]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _WalletTile extends StatelessWidget {
  final Wallet wallet;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _WalletTile({required this.wallet, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final w = wallet;
    final digits = [
      if (w.cardLast4 != null && w.cardLast4!.isNotEmpty) 'کارت ${toPersianDigits(w.cardLast4!)}',
      if (w.accountRef != null && w.accountRef!.isNotEmpty) 'حساب ${toPersianDigits(w.accountRef!)}',
    ];
    final details = [
      if (w.bankId != null && w.bankId!.isNotEmpty) bankNameById(w.bankId!),
      if (digits.isEmpty) 'همه‌ی پیامک‌های بی‌شماره‌ی این بانک' else ...digits,
    ].join(' • ');
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.credit_card_rounded),
      title: Text(w.label),
      subtitle: details.isEmpty ? null : Text(details),
      trailing: IconButton(
        tooltip: 'حذف',
        icon: const Icon(Icons.delete_outline_rounded),
        onPressed: onDelete,
      ),
    );
  }
}

class _WalletForm extends StatefulWidget {
  final DashboardController controller;
  final Wallet initial;
  final bool isNew;

  const _WalletForm({required this.controller, required this.initial, required this.isNew});

  @override
  State<_WalletForm> createState() => _WalletFormState();
}

class _WalletFormState extends State<_WalletForm> {
  late final _owner = TextEditingController(text: widget.initial.ownerName);
  late final _label = TextEditingController(text: widget.initial.label);
  late final _card = TextEditingController(text: widget.initial.cardLast4 ?? '');
  late final _account = TextEditingController(text: widget.initial.accountRef ?? '');
  late String? _bankId = widget.initial.bankId;

  /// عضوِ انتخاب‌شده؛ null یعنی «شخص دیگر (بدون حساب در اپ)». کارت تازه پیش‌فرض
  /// مال خود کاربر است (هر کس کارت‌های خودش را تعریف می‌کند).
  late String? _memberId =
      widget.initial.ownerUserId ?? (widget.isNew ? _meAsMember : null);

  String? get _meAsMember {
    final me = widget.controller.meUserId;
    return widget.controller.members.any((m) => m.id == me) ? me : null;
  }

  String? _error;

  @override
  void dispose() {
    _owner.dispose();
    _label.dispose();
    _card.dispose();
    _account.dispose();
    super.dispose();
  }

  void _save() {
    final members = widget.controller.members;
    String? memberName;
    for (final m in members) {
      if (m.id == _memberId) memberName = m.name;
    }
    final owner = memberName ?? _owner.text.trim();
    final label = _label.text.trim();
    final card = normalizeDigits(_card.text.trim());
    final account = normalizeDigits(_account.text.trim());
    String? error;
    if (owner.isEmpty) {
      error = 'صاحب کارت را انتخاب یا نامش را وارد کن.';
    } else if (label.isEmpty) {
      error = 'یک برچسب بده (مثلاً «کارت حقوق»).';
    } else if (card.isEmpty && account.isEmpty && _bankId == null) {
      error = 'بانک را انتخاب کن (یا ۴ رقم آخر کارت / شماره حساب را بنویس).';
    } else if (card.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(card)) {
      error = 'از شماره کارت فقط ۴ رقم آخر را وارد کن.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(Wallet(
      id: widget.initial.id,
      ownerName: owner,
      ownerUserId: memberName == null ? null : _memberId,
      label: label,
      bankId: _bankId,
      cardLast4: card.isEmpty ? null : card,
      accountRef: account.isEmpty ? null : account,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final members = widget.controller.members;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final showNameField = members.isEmpty || _memberId == null;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.isNew ? 'افزودن کارت/حساب' : 'ویرایش کارت/حساب',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          Text('صاحب کارت', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (members.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in members)
                  ChoiceChip(
                    label: Text(m.id == widget.controller.meUserId ? '${m.name} (من)' : m.name),
                    selected: _memberId == m.id,
                    onSelected: (_) => setState(() => _memberId = m.id),
                  ),
                ChoiceChip(
                  label: const Text('شخص دیگر'),
                  selected: _memberId == null,
                  onSelected: (_) => setState(() => _memberId = null),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (showNameField)
            TextField(
              key: kWalletOwnerFieldKey,
              controller: _owner,
              decoration: InputDecoration(
                labelText: 'نام صاحب (مثلاً بابا)',
                helperText: members.isEmpty
                    ? 'اعضای خانواده با اتصال به سرور این‌جا می‌آیند.'
                    : 'برای کسی که در اپ حساب ندارد؛ تراکنش‌هایش را همین گوشی ویرایش می‌کند.',
                helperMaxLines: 2,
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            key: kWalletLabelFieldKey,
            controller: _label,
            decoration: const InputDecoration(labelText: 'برچسب (مثلاً کارت حقوق)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            value: _bankId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'بانک',
              helperText: 'پیامک بیشتر بانک‌ها شماره‌ی کارت ندارد؛ آن‌وقت انتخاب بانک کافی '
                  'است و همه‌ی پیامک‌های بی‌شماره‌ی این بانک مال همین کارت می‌شود.',
              helperMaxLines: 3,
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('نامشخص')),
              for (final b in kBankRegistry)
                DropdownMenuItem<String?>(
                  value: b.id,
                  child: Text(b.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _bankId = v),
          ),
          const SizedBox(height: 12),
          TextField(
            key: kWalletCardFieldKey,
            controller: _card,
            keyboardType: TextInputType.number,
            maxLength: 4,
            decoration: const InputDecoration(
              labelText: '۴ رقم آخر کارت (اگر در پیامک هست)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: kWalletAccountFieldKey,
            controller: _account,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'شماره حساب (اگر در پیامک هست، همان‌طور که آمده)',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                key: kWalletErrorKey,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: kWalletSaveKey,
            onPressed: _save,
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
  }
}
