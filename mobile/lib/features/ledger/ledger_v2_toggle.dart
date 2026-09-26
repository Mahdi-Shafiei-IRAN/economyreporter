/// کلیدِ «نسخه‌ی ۲ (آزمایشی)» در تنظیمات (پرچمِ `ledger_v2`؛ طرح ۹.۵).
library;

import 'package:flutter/material.dart';

import 'ledger_controller.dart';

const kLedgerV2ToggleKey = Key('ledger-v2-toggle');

class LedgerV2Toggle extends StatelessWidget {
  final LedgerController controller;

  const LedgerV2Toggle({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Card(
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          key: kLedgerV2ToggleKey,
          secondary: const Icon(Icons.science_outlined),
          title: const Text('نسخه‌ی ۲ (آزمایشی): دفترِ حساب با تأییدِ تو'),
          subtitle: const Text(
              'هیچ پیامکی خودش ثبت نمی‌شود؛ هر کدام منتظرِ تأییدِ تو می‌ماند و موجودیِ هر حساب از '
              '«موجودیِ الانش» حساب می‌شود. فعلاً فقط روی همین گوشی ذخیره می‌شود (همگام‌سازی با '
              'سرور در قدمِ بعد). خاموش کردنش نسخه‌ی قبلی را برمی‌گرداند.'),
          value: controller.enabled,
          onChanged: controller.setEnabled,
        ),
      ),
    );
  }
}
