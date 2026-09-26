/// گزارشِ ماه (طرح ۷.۸ و ۱۲.۶): موجودیِ اول/آخرِ ماه، درآمد، هزینه، انتقال، و دسته‌ها با بودجه.
library;

import 'package:flutter/material.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../../core/ledger/month_report.dart';
import '../../core/sms/jalali.dart';
import 'entry_sheet.dart';
import 'ledger_controller.dart';
import 'ledger_text.dart';

const kReportPrevKey = Key('report-prev');
const kReportNextKey = Key('report-next');
const kReportUncategorizedKey = Key('report-uncategorized');
const kReportScopeKey = Key('report-scope');
Key reportCategoryKey(String name) => Key('report-cat-$name');
const kBudgetFieldKey = Key('budget-field');
const kBudgetSaveKey = Key('budget-save');

String monthTitle(DateTime at) {
  final j = JalaliDate.fromDateTime(at);
  return '${jalaliMonthName(j.month)} ${toPersianDigits('${j.year}')}';
}

class MonthReportScreen extends StatefulWidget {
  final LedgerController controller;

  const MonthReportScreen({super.key, required this.controller});

  @override
  State<MonthReportScreen> createState() => _MonthReportScreenState();
}

class _MonthReportScreenState extends State<MonthReportScreen> {
  late DateTime _month = widget.controller.now;

  /// کلِ خانواده (فقط مدیر که حساب‌های بقیه را دارد).
  bool _family = false;

  void _shift(int months) {
    final (from, to) = jalaliMonthRange(_month);
    setState(() => _month = months > 0 ? to.add(const Duration(days: 1)) : from.subtract(const Duration(days: 1)));
  }

  Future<void> _editBudget(CategoryLine line) async {
    final field = TextEditingController(text: tomanInputText(line.limitRial));
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('سقفِ ماهانه‌ی «${line.name}»'),
        content: TextField(
          key: kBudgetFieldKey,
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'تومان (خالی = بی‌سقف)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
          FilledButton(
            key: kBudgetSaveKey,
            onPressed: () async {
              await widget.controller.setBudget(line.name, parseTomanInput(field.text));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('ثبت'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final hasFamily = widget.controller.familyAccounts.isNotEmpty;
        final r = widget.controller.monthReport(_month, family: _family && hasFamily);
        final isCurrent = !widget.controller.now.isBefore(r.from) && widget.controller.now.isBefore(r.to);
        final maxSpent = r.categories.fold<int>(
            1, (m, c) => [m, c.spentRial, c.limitRial ?? 0].reduce((a, b) => a > b ? a : b));
        return Scaffold(
          appBar: AppBar(
            title: Text('گزارشِ ${monthTitle(_month)}'),
            actions: [
              IconButton(
                key: kReportPrevKey,
                tooltip: 'ماهِ قبل',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => _shift(-1),
              ),
              IconButton(
                key: kReportNextKey,
                tooltip: 'ماهِ بعد',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: isCurrent ? null : () => _shift(1),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (hasFamily)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SegmentedButton<bool>(
                    key: kReportScopeKey,
                    segments: const [
                      ButtonSegment(value: false, label: Text('فقط من')),
                      ButtonSegment(value: true, label: Text('کلِ خانواده')),
                    ],
                    selected: {_family},
                    onSelectionChanged: (s) => setState(() => _family = s.first),
                  ),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _Line('موجودیِ اولِ ماه', r.openingRial),
                    _Line('درآمد', r.incomeRial, color: Colors.green.shade700),
                    _Line('هزینه', r.expenseRial, color: theme.colorScheme.error),
                    if (r.transferRial > 0) _Line('انتقال بینِ حساب‌ها', r.transferRial),
                    const Divider(),
                    _Line(isCurrent ? 'موجودیِ الان' : 'موجودیِ آخرِ ماه', r.closingRial, bold: true),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                child: Text('هزینه به تفکیکِ دسته (لمس = سقفِ ماهانه)', style: theme.textTheme.titleSmall),
              ),
              if (r.categories.isEmpty && r.uncategorized.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('هزینه‌ای در این ماه ثبت نشده.', textAlign: TextAlign.center),
                ),
              for (final c in r.categories)
                Card(
                  child: InkWell(
                    key: reportCategoryKey(c.name),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _editBudget(c),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Expanded(child: Text(c.name)),
                            Text(formatToman(c.spentRial),
                                style: TextStyle(color: c.exceeded ? theme.colorScheme.error : null)),
                          ]),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: c.limitRial == null
                                ? c.spentRial / maxSpent
                                : (c.spentRial / c.limitRial!).clamp(0, 1).toDouble(),
                            color: c.exceeded ? theme.colorScheme.error : null,
                          ),
                          if (c.limitRial != null)
                            Text(
                              c.exceeded
                                  ? '${formatToman(c.spentRial - c.limitRial!)} بیشتر از سقفِ ${formatToman(c.limitRial!)}'
                                  : 'مانده تا سقف: ${formatToman(c.limitRial! - c.spentRial)}',
                              style: theme.textTheme.labelSmall,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (r.uncategorized.isNotEmpty)
                Card(
                  child: ExpansionTile(
                    key: kReportUncategorizedKey,
                    title: Text('بی‌دسته: ${formatToman(r.uncategorizedRial)}'),
                    subtitle: Text('${toPersianDigits('${r.uncategorized.length}')} هزینه؛ لمس کن تا دسته بدهی'),
                    children: [
                      for (final e in r.uncategorized)
                        ListTile(
                          dense: true,
                          title: Text(formatToman(e.amountRial)),
                          subtitle: Text([
                            formatShortDateTime(e.occurredAt),
                            if (widget.controller.account(e.accountId) case final a?) accountTitle(a),
                            if (e.note?.trim().isNotEmpty ?? false) e.note!.trim(),
                          ].join(' • ')),
                          onTap: widget.controller.canEdit(e.accountId)
                              ? () => showEntrySheet(context, widget.controller, entry: e)
                              : null,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final int? rial;
  final Color? color;
  final bool bold;

  const _Line(this.label, this.rial, {this.color, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: color, fontWeight: bold ? FontWeight.w700 : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(rial == null ? '—' : formatToman(rial!), style: style),
      ]),
    );
  }
}
