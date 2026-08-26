import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/export/csv.dart';

/// The Reports screen reads `GET /tickets/export` — PHP `fputcsv` output —
/// back into rows so it can offer a column picker and re-render as PDF/Excel.
/// Ticket subjects routinely carry commas, quotes and newlines, so the parser
/// has to be a real one.
void main() {
  group('parseCsv', () {
    test('plain rows', () {
      expect(parseCsv('a,b,c\n1,2,3'), [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
    });

    test('a trailing newline does not add an empty row', () {
      expect(parseCsv('a,b\n1,2\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('CRLF line endings', () {
      expect(parseCsv('a,b\r\n1,2\r\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('quoted fields keep their commas', () {
      expect(parseCsv('num,subject\n1,"Cannot login, urgent"'), [
        ['num', 'subject'],
        ['1', 'Cannot login, urgent'],
      ]);
    });

    test('doubled quotes unescape to one', () {
      expect(parseCsv('1,"He said ""hi"""'), [
        ['1', 'He said "hi"'],
      ]);
    });

    test('a newline inside quotes stays inside the field', () {
      expect(parseCsv('1,"line one\nline two"\n2,plain'), [
        ['1', 'line one\nline two'],
        ['2', 'plain'],
      ]);
    });

    test('empty fields are preserved, including a trailing one', () {
      expect(parseCsv('1,,3\n4,5,'), [
        ['1', '', '3'],
        ['4', '5', ''],
      ]);
    });

    test('an empty input yields no rows', () {
      expect(parseCsv(''), isEmpty);
    });

    test('a ticket export row survives intact', () {
      const csv =
          'number,subject,status,priority,department,assignee,requester,'
          'created,due\n'
          '"000123","Login fails, again","Open","High","Support",'
          '"Asha Rao","Ravi K","2026-08-20 11:04:00",""\n';
      final rows = parseCsv(csv);
      expect(rows, hasLength(2));
      expect(rows[1], [
        '000123',
        'Login fails, again',
        'Open',
        'High',
        'Support',
        'Asha Rao',
        'Ravi K',
        '2026-08-20 11:04:00',
        '',
      ]);
    });
  });
}
