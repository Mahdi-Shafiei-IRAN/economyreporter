/// ساخت و اشتراک‌گذاری گزارش PDF (راست‌به‌چپ، فونت فارسی برای همه‌ی وزن‌ها).
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/format/date_format.dart';
import '../../core/format/money_format.dart';
import '../transactions/data/tx_query.dart';
import 'report_data.dart';

const _brand = PdfColor.fromInt(0xFF1E40AF);
const _income = PdfColor.fromInt(0xFF047857);
const _expense = PdfColor.fromInt(0xFFB91C1C);
const _zebra = PdfColor.fromInt(0xFFF1F5F9);

/// سقف ردیف‌های فهرست تراکنش در PDF (بقیه در جمع‌ها هست).
const int kPdfMaxRows = 2000;

class PdfReport {
  PdfReport._();

  static String _t(int rial) => formatToman(rial, withUnit: false);

  static String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max)}…';

  static Future<Uint8List> build(ReportData data, {required pw.Font font}) async {
    // فونت فارسی برای همه‌ی وزن‌ها؛ وگرنه متن bold با Helvetica (بی‌حروف فارسی) خراب می‌شود.
    final doc = pw.Document(
      title: data.title,
      theme: pw.ThemeData.withFont(base: font, bold: font, italic: font, boldItalic: font),
    );

    pw.Widget sectionTitle(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
          child: pw.Text(text, style: const pw.TextStyle(fontSize: 13, color: _brand)),
        );

    pw.Widget table(
      List<String> headers,
      List<List<String>> rows, {
      Map<int, pw.TableColumnWidth>? widths,
    }) =>
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          tableDirection: pw.TextDirection.rtl,
          headerDirection: pw.TextDirection.rtl,
          headerStyle: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: _brand),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerAlignment: pw.Alignment.centerRight,
          cellAlignment: pw.Alignment.centerRight,
          oddRowDecoration: const pw.BoxDecoration(color: _zebra),
          border: null,
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          columnWidths: widths,
        );

    pw.Widget box(String label, String value, PdfColor color) => pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: color, width: 1),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                pw.SizedBox(height: 2),
                pw.Text('$value تومان', style: pw.TextStyle(fontSize: 13, color: color)),
              ],
            ),
          ),
        );

    List<List<String>> breakdownRows(List<BreakdownEntry> entries) => [
          for (final e in entries)
            [e.label, toPersianDigits('${e.count}'), _t(e.incomeRial), _t(e.expenseRial)],
        ];

    final txs = data.transactions.take(kPdfMaxRows).toList();
    final categorySum = data.categories.fold<int>(0, (a, e) => a + e.expenseRial);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('مالی خانواده • ساخته‌شده ${formatJalaliDateTime(data.generatedAt)}',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text(
              'صفحه ${toPersianDigits('${context.pageNumber}')} از ${toPersianDigits('${context.pagesCount}')}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
        build: (context) => [
          pw.Text(data.title, style: const pw.TextStyle(fontSize: 18, color: _brand)),
          pw.SizedBox(height: 2),
          pw.Text('${data.rangeLabel} — مبالغ به تومان',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 12),
          pw.Row(children: [
            box('درآمد (واریز)', _t(data.summary.incomeRial), _income),
            pw.SizedBox(width: 8),
            box('هزینه (برداشت)', _t(data.summary.expenseRial), _expense),
            pw.SizedBox(width: 8),
            box('خالص', _t(data.summary.balanceRial), _brand),
          ]),
          if (data.people.isNotEmpty) ...[
            sectionTitle('به تفکیک افراد'),
            table(['شخص', 'تعداد', 'درآمد', 'هزینه'], breakdownRows(data.people)),
          ],
          if (data.cards.isNotEmpty) ...[
            sectionTitle('به تفکیک کارت‌ها'),
            table(['کارت/حساب', 'تعداد', 'درآمد', 'هزینه'], breakdownRows(data.cards)),
          ],
          if (data.categories.isNotEmpty) ...[
            sectionTitle('هزینه به تفکیک دسته'),
            table(['دسته', 'مبلغ', 'درصد'], [
              for (final e in data.categories)
                [
                  e.label,
                  _t(e.expenseRial),
                  '${toPersianDigits('${categorySum == 0 ? 0 : (e.expenseRial * 100 / categorySum).round()}')}٪',
                ],
            ]),
          ],
          sectionTitle('فهرست تراکنش‌ها (${toPersianDigits('${data.transactions.length}')})'),
          table(
            ['تاریخ', 'شخص', 'کارت', 'نوع', 'مبلغ', 'شرح'],
            [
              for (final t in txs)
                [
                  '${formatJalaliNumeric(t.effectiveTime)} ${formatClock(t.effectiveTime)}',
                  personOf(t),
                  _clip(cardTitleOf(t), 22),
                  '${kindLabel(t.kind)}${t.needsReview ? ' (بازبینی)' : ''}',
                  t.amountRial == null ? '—' : _t(t.amountRial!),
                  _clip(t.counterparty ?? t.description ?? '', 30),
                ],
            ],
            widths: const {
              0: pw.FixedColumnWidth(78),
              1: pw.FixedColumnWidth(52),
              2: pw.FixedColumnWidth(90),
              3: pw.FixedColumnWidth(48),
              4: pw.FixedColumnWidth(62),
              5: pw.FlexColumnWidth(),
            },
          ),
          if (data.transactions.length > kPdfMaxRows)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6),
              child: pw.Text(
                'فقط ${toPersianDigits('$kPdfMaxRows')} تراکنش جدیدتر فهرست شده؛ جمع‌ها شامل همه است.',
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
              ),
            ),
        ],
      ),
    );
    return doc.save();
  }

  static Future<pw.Font> _loadFont() async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'));

  /// ساخت PDF و باز کردن پنجره‌ی اشتراک‌گذاری (ذخیره در فایل‌ها، تلگرام، ...).
  static Future<void> share(ReportData data) async {
    final bytes = await build(data, font: await _loadFont());
    await Printing.sharePdf(bytes: bytes, filename: data.fileName);
  }

  /// پیش‌نمایش/چاپ (در اندروید «ذخیره به‌صورت PDF» هم دارد).
  static Future<void> preview(ReportData data) async {
    final font = await _loadFont();
    await Printing.layoutPdf(
      name: data.fileName,
      onLayout: (_) => build(data, font: font),
    );
  }
}
