import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../widgets/svg_icon.dart';
import '../assets.dart';

/// The file formats a list screen can export to via [exportTable].
enum ExportFormat {
  pdf(
    label: 'PDF',
    ext: 'pdf',
    mimeType: 'application/pdf',
    icon: Icons.picture_as_pdf_outlined,
    tint: Color(0xFFE53935),
  ),
  excel(
    label: 'Excel',
    ext: 'xlsx',
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    icon: Icons.grid_on_outlined,
    tint: Color(0xFF1E8E3E),
  );

  const ExportFormat({
    required this.label,
    required this.ext,
    required this.mimeType,
    required this.icon,
    required this.tint,
  });

  final String label;
  final String ext;

  /// MIME type passed to open_filex so Android resolves the right viewer.
  final String mimeType;
  final IconData icon;

  /// Brand-ish accent for the format's glyph in the download menu.
  final Color tint;
}

/// App-bar download control: a download glyph that opens a styled popup menu
/// offering each [ExportFormat], or a spinner while [busy]. Shared by the
/// tickets and tasks list screens so the menu looks identical everywhere.
class ExportMenuButton extends StatelessWidget {
  const ExportMenuButton({
    super.key,
    required this.busy,
    required this.onSelected,
  });

  final bool busy;
  final ValueChanged<ExportFormat> onSelected;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const IconButton(
        tooltip: 'Downloading…',
        onPressed: null,
        icon: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<ExportFormat>(
      tooltip: 'Download',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      elevation: 8,
      color: scheme.surface,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      icon: const SvgIcon(Assets.download, size: 22),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final f in ExportFormat.values)
          PopupMenuItem<ExportFormat>(
            value: f,
            height: 48,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: f.tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(f.icon, size: 18, color: f.tint),
                ),
                const SizedBox(width: 12),
                Text(
                  'Download ${f.label}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Build a tabular document (PDF or Excel) from [columns]/[rows], write it to a
/// temp file named `<baseName>.<ext>`, open it with the platform handler, and
/// return the written file.
///
/// [rows] cells are plain strings; missing values should be passed as `''`.
///
/// Throws [ExportOpenException] if the file was written but no installed app
/// could open it (so callers can distinguish "saved but couldn't open" from a
/// build/write failure).
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

  // Write to the app's cache dir and hand the path to open_filex, which exposes
  // it through a FileProvider content:// URI. A raw file:// URI (the old
  // launchUrl path) is blocked by Android and never opened anything.
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$baseName.${format.ext}');
  await file.writeAsBytes(bytes, flush: true);
  final result = await OpenFilex.open(file.path, type: format.mimeType);
  if (result.type != ResultType.done) {
    throw ExportOpenException(file, result.message);
  }
  return file;
}

/// Thrown by [exportTable] when the document was written but no app on the
/// device could open it.
class ExportOpenException implements Exception {
  const ExportOpenException(this.file, this.message);

  final File file;
  final String message;

  @override
  String toString() => 'ExportOpenException: $message (${file.path})';
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
