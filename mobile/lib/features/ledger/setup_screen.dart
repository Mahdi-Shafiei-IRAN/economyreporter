/// راهنمای سه‌قدمیِ اولین اجرا (طرح ۱۲.۵): بانک‌ها ← حساب‌های پیداشده ← پیامک‌های این ماه.
/// هر قدم «بعدی» یا «رد شدن» دارد؛ کارتِ «قدمِ بعدی» در خانه بقیه‌اش را یادآوری می‌کند.
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import 'accounts_view.dart';
import 'banks_view.dart';
import 'ledger_controller.dart';
import 'pending_screen.dart';

const kSetupNextKey = Key('setup-next');
const kSetupSkipKey = Key('setup-skip');

class LedgerSetupScreen extends StatefulWidget {
  final LedgerController controller;

  const LedgerSetupScreen({super.key, required this.controller});

  @override
  State<LedgerSetupScreen> createState() => _LedgerSetupScreenState();
}

class _LedgerSetupScreenState extends State<LedgerSetupScreen> {
  int _step = 0;
  LedgerController get _c => widget.controller;

  static const _titles = ['۱ از ۳ — بانک‌هایت کدام‌اند؟', '۲ از ۳ — حساب‌هایت', '۳ از ۳ — پیامک‌های این ماه'];

  Future<void> _finish({bool openPending = false}) async {
    await _c.finishSetup();
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    if (openPending) {
      nav.push(MaterialPageRoute(builder: (_) => PendingScreen(controller: _c)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _step == 2;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(_titles[_step]),
        actions: [
          TextButton(
            key: kSetupSkipKey,
            onPressed: () => _finish(),
            child: const Text('بعداً'),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_step + 1) / 3),
          Expanded(
            child: switch (_step) {
              0 => LedgerBanksView(controller: _c),
              1 => LedgerAccountsView(controller: _c),
              _ => AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mark_email_unread_outlined, size: 48, color: theme.colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          _c.pendingCount == 0
                              ? 'پیامکی منتظرِ تأیید نیست.'
                              : '${toPersianDigits('${_c.pendingCount}')} پیامکِ این ماه منتظرِ تأییدِ توست.',
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'هیچ پیامکی خودش ثبت نمی‌شود. هر کدام را «ثبت» کن یا بگو «تراکنش نیست». '
                          'از این به بعد هر پیامکِ تازه با دو دکمه‌ی همین‌ها در نوتیفیکیشن می‌آید.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
            },
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton(
                      onPressed: () => setState(() => _step--),
                      child: const Text('قبلی'),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: kSetupNextKey,
                    onPressed: last
                        ? () => _finish(openPending: _c.pendingCount > 0)
                        : () => setState(() => _step++),
                    child: Text(last
                        ? (_c.pendingCount > 0 ? 'برو سراغشان' : 'تمام')
                        : 'بعدی'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
