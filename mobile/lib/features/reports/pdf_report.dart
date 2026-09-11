/// ساخت و اشتراک‌گذاری گزارش دسته‌ها به‌صورت PDF (با فونت فارسی).
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/format/money_format.dart';
import '../categories/data/category.dart';

class PdfReport {
  static Future<void> shareCategoryReport({
    required String periodLabel,
    required List<CategoryTotal> totals,
    required int totalRial,
  }) async {
    final fontData =
        await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: ttf),
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('گزارش هزینه‌ها — $periodLabel'),
          ),
          pw.Text('جمع کل: ${formatToman(totalRial)}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headerDecoration:
                const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0D9488)),
            headerStyle: pw.TextStyle(
                color: PdfColors.white, fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerRight,
            headers: ['دسته', 'مبلغ', 'درصد'],
            data: [
              for (final t in totals)
                [
                  t.name,
                  formatToman(t.amountRial),
                  totalRial == 0
                      ? '۰٪'
                      : '${toPersianDigits((t.amountRial * 100 / totalRial).round().toString())}٪',
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'ساخته‌شده توسط اپ مالی خانواده',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey),
          ),
        ],
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: 'گزارش-مالی.pdf');
  }
}
