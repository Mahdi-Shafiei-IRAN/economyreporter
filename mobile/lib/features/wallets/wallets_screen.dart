/// مدیریت کارت/حساب اعضای خانواده.
library;

import 'package:flutter/material.dart';

import '../../core/sms/bank_registry.dart';
import '../dashboard/dashboard_controller.dart';
import 'data/wallet.dart';

const kWalletAddFabKey = Key('wallet-add-fab');
const kWalletOwnerFieldKey = Key('wallet-owner');
const kWalletLabelFieldKey = Key('wallet-label');
const kWalletCardFieldKey = Key('wallet-card');
const kWalletAccountFieldKey = Key('wallet-account');
const kWalletSaveKey = Key('wallet-save');
const kWalletsEmptyKey = Key('wallets-empty');

class WalletsScreen extends StatelessWidget {
  final DashboardController controller;

  const WalletsScreen({super.key, required this.controller});

  Future<void> _openAdd(BuildContext context) async {
    final wallet = await showModalBottomSheet<Wallet>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddWalletSheet(),
    );
    if (wallet != null) await controller.addWallet(wallet);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('حساب‌ها و کارت‌ها')),
      floatingActionButton: FloatingActionButton.extended(
        key: kWalletAddFabKey,
        onPressed: () => _openAdd(context),
        icon: const Icon(Icons.add_card),
        label: const Text('افزودن'),
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final wallets = controller.wallets;
          if (wallets.isEmpty) {
            return const Center(
              key: kWalletsEmptyKey,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'هنوز کارت/حسابی ثبت نشده.\nبا دکمه‌ی «افزودن»، کارت‌های خانواده را'
                  ' با نام صاحبشان ثبت کن تا هر تراکنش به شخص و کارتش وصل شود.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final w in wallets)
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text('${w.ownerName} • ${w.label}'),
                    subtitle: Text([
                      if (w.bankId != null && w.bankId!.isNotEmpty)
                        bankNameById(w.bankId!),
                      if (w.cardLast4 != null && w.cardLast4!.isNotEmpty)
                        'کارت ${w.cardLast4}',
                      if (w.accountRef != null && w.accountRef!.isNotEmpty)
                        'حساب ${w.accountRef}',
                    ].join(' • ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => controller.deleteWallet(w.id),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AddWalletSheet extends StatefulWidget {
  const _AddWalletSheet();

  @override
  State<_AddWalletSheet> createState() => _AddWalletSheetState();
}

class _AddWalletSheetState extends State<_AddWalletSheet> {
  final _owner = TextEditingController();
  final _label = TextEditingController();
  final _card = TextEditingController();
  final _account = TextEditingController();
  String? _bankId;

  @override
  void dispose() {
    _owner.dispose();
    _label.dispose();
    _card.dispose();
    _account.dispose();
    super.dispose();
  }

  void _save() {
    final owner = _owner.text.trim();
    final label = _label.text.trim();
    final card = _card.text.trim();
    final account = _account.text.trim();
    if (owner.isEmpty || label.isEmpty) return;
    if (card.isEmpty && account.isEmpty) return; // حداقل یکی لازم است
    Navigator.of(context).pop(Wallet(
      id: '',
      ownerName: owner,
      label: label,
      bankId: _bankId,
      cardLast4: card.isEmpty ? null : card,
      accountRef: account.isEmpty ? null : account,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('افزودن کارت/حساب',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            key: kWalletOwnerFieldKey,
            controller: _owner,
            decoration: const InputDecoration(
                labelText: 'نام صاحب (مثلاً بابا)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            key: kWalletLabelFieldKey,
            controller: _label,
            decoration: const InputDecoration(
                labelText: 'برچسب (مثلاً کارت حقوق)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _bankId,
            decoration: const InputDecoration(
                labelText: 'بانک (اختیاری)', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('بدون بانک')),
              for (final b in kBankRegistry)
                DropdownMenuItem(value: b.id, child: Text(b.name)),
            ],
            onChanged: (v) => setState(() => _bankId = v),
          ),
          const SizedBox(height: 10),
          TextField(
            key: kWalletCardFieldKey,
            controller: _card,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: '۴ رقم آخر کارت', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            key: kWalletAccountFieldKey,
            controller: _account,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'شماره حساب (یا یکی از این دو)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
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
