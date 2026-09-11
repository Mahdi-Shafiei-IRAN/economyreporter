/// تراکنش‌های خودم که از «شروع دسته‌بندی» به بعدند و دسته ندارند.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../dashboard/dashboard_controller.dart';
import '../transactions/widgets/tx_widgets.dart';
import 'categorize_screen.dart';

const kCategorizeListEmptyKey = Key('categorize-list-empty');

class CategorizeListScreen extends StatelessWidget {
  final DashboardController controller;

  const CategorizeListScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('منتظر دسته‌بندی')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final items = controller.uncategorized;
          final from = controller.categorizeFrom;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'تراکنش‌های خودت${from == null ? '' : ' از ${formatJalaliDate(from)} به بعد'} که هنوز '
                'دسته ندارند. تراکنش‌های قبل از این تاریخ عمداً این‌جا نمی‌آیند؛ تاریخ '
                'شروع را در «تنظیمات» می‌توانی عوض کنی.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Padding(
                  key: kCategorizeListEmptyKey,
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(Icons.task_alt_rounded, size: 48),
                      SizedBox(height: 8),
                      Text('همه‌چیز دسته‌بندی شده'),
                    ],
                  ),
                )
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(indent: 68),
                        TransactionTile(
                          key: ValueKey('uncat-${items[i].id}'),
                          record: items[i],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  CategorizeScreen(controller: controller, record: items[i]),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
