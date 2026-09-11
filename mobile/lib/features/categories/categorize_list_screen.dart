/// فهرست تراکنش‌های دسته‌بندی‌نشده؛ با لمس هرکدام، صفحه‌ی دسته‌بندی باز می‌شود.
library;

import 'package:flutter/material.dart';

import '../../core/format/money_format.dart';
import '../../core/sms/bank_registry.dart';
import '../dashboard/dashboard_controller.dart';
import 'categorize_screen.dart';

const kCategorizeListEmptyKey = Key('categorize-list-empty');

class CategorizeListScreen extends StatelessWidget {
  final DashboardController controller;

  const CategorizeListScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دسته‌بندی‌نشده‌ها')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final items = controller.uncategorized;
          if (items.isEmpty) {
            return const Center(
              key: kCategorizeListEmptyKey,
              child: Text('همه‌چیز دسته‌بندی شده 🎉'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final t = items[i];
              final sub = [
                if (t.bankId != null) bankNameById(t.bankId!),
                if (t.cardLast4 != null) 'کارت ${t.cardLast4}',
                if (t.accountRef != null) 'حساب ${t.accountRef}',
              ].join(' • ');
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: ListTile(
                  title: Text(
                    t.amountRial == null ? 'نامشخص' : formatToman(t.amountRial!),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: sub.isEmpty ? null : Text(sub),
                  trailing: const Icon(Icons.label_outline),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          CategorizeScreen(controller: controller, record: t),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
