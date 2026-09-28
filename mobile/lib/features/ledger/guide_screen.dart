/// «راهنما»ی کوتاهِ نسخه‌ی ۲.
library;

import 'package:flutter/material.dart';

class LedgerGuideScreen extends StatelessWidget {
  const LedgerGuideScreen({super.key});

  static const _items = [
    (Icons.account_balance_outlined, 'بانک‌ها',
        'بگو کدام فرستنده‌ی پیامک بانک است. فقط پیامکِ همین‌ها خوانده می‌شود.'),
    (Icons.credit_card_rounded, 'حساب‌ها',
        'برنامه حساب‌هایت را از پیامک‌ها پیدا می‌کند؛ فقط بگو «مالِ من است» یا «پیگیری نکن».'),
    (Icons.account_balance_wallet_outlined, 'موجودی',
        'موجودیِ هر حساب از آخرین مانده‌ی بانک شروع می‌شود و با هر تراکنشی که تأیید کنی جلو می‌رود.'),
    (Icons.mark_email_unread_outlined, 'پیامک‌ها',
        'هیچ پیامکی خودش ثبت نمی‌شود. «ثبت» یا «تراکنش نیست»؛ از نوتیفیکیشن هم می‌شود. '
            'در فهرست: به راست بکش = ثبت، به چپ = تراکنش نیست.'),
    (Icons.flag_outlined, 'کارهای مانده',
        'تراشه‌های زیرِ خلاصه‌ی ماه می‌گویند چه کاری مانده (پیامکِ منتظر، حسابِ بی‌موجودی، اختلاف با بانک). '
            'تراشه‌ای نبود یعنی کاری نمانده.'),
    (Icons.groups_outlined, 'صفحه‌ی اصلی',
        'بالا ماه را عوض کن و عضو یا کارت را انتخاب کن تا خالص، درآمد، هزینه و موجودیِ همان‌ها را ببینی. '
            'پایین: هر عضو و کارت‌هایش، یا «روز به روز». مدیرِ خانواده همه را می‌بیند؛ مالِ بقیه فقط دیدنی است.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('راهنما')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final (icon, title, text) in _items)
            Card(
              child: ListTile(
                leading: Icon(icon, color: theme.colorScheme.primary),
                title: Text(title),
                subtitle: Text(text),
              ),
            ),
        ],
      ),
    );
  }
}
