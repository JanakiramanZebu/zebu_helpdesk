import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/models/ticket.dart';

TicketField _f(
  String label, {
  bool required = false,
  bool editable = true,
  dynamic value,
  Map<String, String>? choices,
  String type = 'text',
}) => TicketField(
  name: label.toLowerCase().replaceAll(' ', '_'),
  label: label,
  type: type,
  required: required,
  editable: editable,
  value: value,
  choices: choices,
);

void main() {
  group('ticketFieldRows', () {
    test('falls back to the flat map when the form did not load', () {
      final rows = ticketFieldRows(
        {'Client Id': '273', 'Resolution': ''},
        const [],
      );
      expect(rows.map((r) => r.label), ['Client Id', 'Resolution']);
      expect(rows.first.value, '273');
      // Nothing to mark: without the form there is no required flag.
      expect(rows.every((r) => !r.missing), isTrue);
    });

    test('marks a required answer that was left blank', () {
      final rows = ticketFieldRows(
        {'Client Id': '273', 'Resolution': ''},
        [
          _f('Client Id', required: true),
          _f('Resolution', required: true),
          _f('Preventive Action'),
        ],
      );
      expect(rows.length, 3);
      expect(rows[0].missing, isFalse); // answered
      expect(rows[1].missing, isTrue); // required, blank
      expect(rows[1].value, isNull);
      expect(rows[2].missing, isFalse); // blank but optional
    });

    test('the form drives the order, not the payload', () {
      final rows = ticketFieldRows(
        {'Impact': 'High', 'Client Id': '273'},
        [_f('Client Id'), _f('Impact')],
      );
      expect(rows.map((r) => r.label), ['Client Id', 'Impact']);
    });

    test('a field the payload omits still gets a row', () {
      final rows = ticketFieldRows(const {}, [
        _f('Resolution', required: true),
      ]);
      expect(rows.single.value, isNull);
      expect(rows.single.missing, isTrue);
    });

    test('whitespace is not an answer', () {
      final rows = ticketFieldRows({'Resolution': '   '}, [
        _f('Resolution', required: true),
      ]);
      expect(rows.single.missing, isTrue);
    });

    test('falls back to the field own value, resolving choice keys', () {
      final rows = ticketFieldRows(const {}, [
        _f(
          'Impact',
          value: '2',
          type: 'choices',
          choices: {'1': 'Low', '2': 'High'},
        ),
        _f('RCA Performed', value: true, type: 'bool'),
        _f(
          'Products',
          value: ['1', '3'],
          type: 'list-2',
          choices: {'1': 'General', '2': 'Mobile', '3': 'Web'},
        ),
      ]);
      expect(rows[0].value, 'High');
      expect(rows[1].value, 'Yes');
      expect(rows[2].value, 'General, Web');
      expect(rows.every((r) => !r.missing), isTrue);
    });

    test('an editable field carries its definition, for per-field edit', () {
      final rows = ticketFieldRows(const {}, [
        _f('Client Id'),
        _f('Ticket Number', editable: false),
      ]);
      expect(rows[0].field?.name, 'client_id');
      // Read-only on the form: the row still shows, but it opens nothing.
      expect(rows[1].field, isNull);
    });

    test('the flat fallback carries no field, so a row cannot self-edit', () {
      final rows = ticketFieldRows({'Client Id': '273'}, const []);
      expect(rows.single.field, isNull);
    });

    test('the payload display value wins over the raw answer', () {
      final rows = ticketFieldRows({'Impact': 'High'}, [
        _f('Impact', value: '2', choices: {'2': 'Ignored'}),
      ]);
      expect(rows.single.value, 'High');
    });
  });
}
