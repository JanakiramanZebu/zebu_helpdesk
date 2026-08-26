/// Minimal RFC 4180 CSV reader.
///
/// `GET /reports/download` streams the server's own CSV (PHP `fputcsv`) for a
/// report export, and `GET /tickets/export` does the same for a queue export.
/// Both carry columns the list serializers never return. Reading a download
/// back into rows lets the Reports screen report an honest row count before it
/// hands the file to a viewer.
///
/// Handles quoted fields, doubled `""` escapes, embedded commas/newlines, and
/// both `\n` and `\r\n` line endings. A trailing newline yields no extra row.
List<List<String>> parseCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var started = false; // this row has content (guards the trailing newline)

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
    started = false;
  }

  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
      continue;
    }
    switch (c) {
      case '"':
        quoted = true;
        started = true;
      case ',':
        endField();
        started = true;
      case '\r':
        // Swallow; the \n that follows (or a lone \r) closes the row.
        if (i + 1 < input.length && input[i + 1] == '\n') continue;
        endRow();
      case '\n':
        endRow();
      default:
        field.write(c);
        started = true;
    }
  }
  if (started || field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
