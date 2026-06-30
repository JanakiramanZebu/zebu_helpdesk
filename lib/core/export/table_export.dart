import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:url_launcher/url_launcher.dart';

/// The file formats a list screen can export to via [exportTable].
enum ExportFormat {
  pdf(label: 'PDF', ext: 'pdf', icon: Icons.picture_as_pdf_outlined),
  excel(label: 'Excel', ext: 'xlsx', icon: Icons.grid_on_outlined);

  const ExportFormat({
    required this.label,
    required this.ext,
    required this.icon,
  });

  final String label;
  final String ext;
  final IconData icon;
}

/// Build a tabular document (PDF or Excel) from [columns]/[rows], write it to a
/// temp file named `<baseName>.<ext>`, open it with the platform handler, and
/// return the written file.
///
/// [rows] cells are plain strings; missing values should be passed as `''`.
Future<File> exportTable({
  required ExportFormat format,
  required String baseName,
  required String title,
  required List<String> columns,
  required List<List<String>> rows,
}) async {
  final bytes = switch (format) {
    ExportFormat.pdf => await _buildPdf(title, columns, rows),
    ExportFormat.excel => _buildExcel(title, columns, rows),
  };

  final file = File('${Directory.systemTemp.path}/$baseName.${format.ext}');
  await file.writeAsBytes(bytes);
  await launchUrl(Uri.file(file.path));
  return file;
}

Future<Uint8List> _buildPdf(
  String title,
  List<String> columns,
  List<List<String>> rows,
) async {
  final doc = pw.Document(title: title);
  final generated = DateTime.now();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      header: (context) => context.pageNumber == 1
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '${rows.length} record(s) · generated '
                  '${generated.toString().split('.').first}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.SizedBox(height: 10),
              ],
            )
          : pw.SizedBox(),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
        ),
      ),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headers: columns,
          data: rows,
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
          ),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFF0037B7),
          ),
          cellStyle: const pw.TextStyle(fontSize: 8),
          cellAlignment: pw.Alignment.centerLeft,
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 3,
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

Uint8List _buildExcel(
  String title,
  List<String> columns,
  List<List<String>> rows,
) {
  final book = xls.Excel.createExcel();
  // Rename the default sheet to the export title (Excel caps tab names at 31).
  final sheetName = title.length > 31 ? title.substring(0, 31) : title;
  book.rename(book.getDefaultSheet()!, sheetName);
  final sheet = book[sheetName];

  sheet.appendRow([
    for (final c in columns) xls.TextCellValue(c),
  ]);
  for (final row in rows) {
    sheet.appendRow([
      for (final cell in row) xls.TextCellValue(cell),
    ]);
  }

  final bytes = book.save();
  return Uint8List.fromList(bytes ?? const []);
}
