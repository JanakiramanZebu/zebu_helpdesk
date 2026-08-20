import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/models/ticket.dart';

/// The documented `GET /tickets/form` payload (docs/API_V2.md), used verbatim so
/// the parsing stays pinned to the real contract.
final _payload = <String, dynamic>{
  'topic_id': 1,
  'fields': [
    {
      'name': 'clientid', 'label': 'Client Id', 'hint': null, 'type': 'text',
      'required': true, 'editable': true, 'choices': null,
      'multiselect': false, 'value': null, 'id': 45,
      'parent_field': null, 'choices_by_parent': null,
    },
    {
      'name': 'products', 'label': 'Products', 'type': 'list-2',
      'required': true, 'choices': {'99': 'Bank', '101': 'GST'}, 'id': 37,
      'parent_field': null, 'choices_by_parent': null, 'hint': null,
      'editable': true, 'multiselect': false, 'value': null,
    },
    {
      'name': 'categorys', 'label': 'Sub Issue Categories', 'type': 'list-4',
      'required': true,
      'choices': {
        '128': 'Account Closure', '133': 'Account Proof', '141': 'GST Filing',
      },
      'id': 39, 'parent_field': 'products',
      'choices_by_parent': {
        '99': {'128': 'Account Closure', '133': 'Account Proof'},
        '101': {'141': 'GST Filing'},
      },
      'hint': null, 'editable': true, 'multiselect': false, 'value': null,
    },
  ],
  'defaults': {
    'dept_id': null, 'priority_id': 3, 'sla_id': 3, 'status_id': 8,
    'staff_id': null, 'team_id': null, 'duedate': '8/19/26 8:14 AM',
  },
  'sla_locked': true,
  'sources': {
    'default': 'Phone',
    'values': [
      {'value': 'Phone', 'label': 'Phone'},
      {'value': 'Email', 'label': 'Email'},
      {'value': 'Other', 'label': 'Other'},
    ],
  },
  'statuses': {
    'default': 8,
    'values': [
      {'id': 8, 'name': 'Unassigned'},
      {'id': 1, 'name': 'Open'},
    ],
  },
  'can_assign': true,
  'can_set_duedate': false,
};

void main() {
  group('TicketCreateForm.fromJson', () {
    final form = TicketCreateForm.fromJson(_payload);

    test('parses the topic fields', () {
      expect(form.topicId, 1);
      expect(form.fields.map((f) => f.name),
          ['clientid', 'products', 'categorys']);
      expect(form.fields.every((f) => f.required), isTrue);
      expect(form.fields.first.id, 45);
    });

    test('custom lists render as pickers even though type is list-N', () {
      final products = form.fields[1];
      expect(products.type, 'list-2');
      expect(products.isChoice, isTrue, reason: 'must not fall back to text');

      final clientId = form.fields[0];
      expect(clientId.isChoice, isFalse, reason: 'a text field stays text');
    });

    test('parses topic defaults', () {
      expect(form.priorityId, 3);
      expect(form.slaId, 3);
      expect(form.statusId, 8);
      expect(form.deptId, isNull);
    });

    test('an SLA-locked topic makes the due date server-owned', () {
      expect(form.slaLocked, isTrue);
      expect(form.canSetDuedate, isFalse);
    });

    test('parses the server-driven source and status options', () {
      expect(form.defaultSource, 'Phone');
      expect(form.sources.map((o) => o.value), ['Phone', 'Email', 'Other']);
      expect(form.defaultStatusId, 8);
      expect(form.statuses.map((o) => o.label), ['Unassigned', 'Open']);
      // Statuses are keyed by id so the picker can map a choice back.
      expect(form.statuses.first.value, '8');
    });

    test('derives canSetDuedate when only sla_locked is present', () {
      final j = Map<String, dynamic>.from(_payload)..remove('can_set_duedate');
      expect(TicketCreateForm.fromJson(j).canSetDuedate, isFalse);
    });
  });

  group('cascading child choices', () {
    final form = TicketCreateForm.fromJson(_payload);
    final categories = form.fields[2];

    test('is empty until the parent is answered', () {
      expect(categories.parentField, 'products');
      expect(categories.choicesFor(null), isEmpty);
      expect(categories.choicesFor(''), isEmpty);
    });

    test('narrows to the options allowed by the parent selection', () {
      expect(categories.choicesFor('99').keys, ['128', '133']);
      expect(categories.choicesFor('101').keys, ['141']);
    });

    test('a non-cascading field keeps its full choice list', () {
      expect(form.fields[1].choicesFor(null).length, 2);
    });
  });

  group('SLA-computed due date', () {
    test('parses osTicket\'s m/d/y g:i a format', () {
      // DateTime.parse rejects this outright, so the value would silently
      // vanish without the dedicated parser.
      expect(DateTime.tryParse('8/19/26 8:14 AM'), isNull);

      final d = TicketCreateForm.parseStaffDate('8/19/26 8:14 AM')!;
      expect([d.year, d.month, d.day, d.hour, d.minute], [2026, 8, 19, 8, 14]);
    });

    test('handles PM, midnight, noon and a bare date', () {
      expect(TicketCreateForm.parseStaffDate('12/1/2026 4:02 PM')!.hour, 16);
      expect(TicketCreateForm.parseStaffDate('1/2/26 12:30 AM')!.hour, 0);
      expect(TicketCreateForm.parseStaffDate('1/2/26 12:30 PM')!.hour, 12);
      expect(TicketCreateForm.parseStaffDate('1/2/26')!.day, 2);
    });

    test('reads the live d/m/Y form (this install emits it)', () {
      // GET /tickets/form defaults.duedate, 2026-08-19: "20/08/2026 10:00 AM".
      // Month-first would silently roll 2026-20-08 over into Aug 2027.
      final d = TicketCreateForm.parseStaffDate('20/08/2026 10:00 AM')!;
      expect([d.year, d.month, d.day, d.hour, d.minute], [2026, 8, 20, 10, 0]);
    });

    test('resolves day/month order from the values, then the year width', () {
      // 19 can only be a day, whichever style the install uses.
      expect(TicketCreateForm.parseStaffDate('19/08/2026')!.month, 8);
      expect(TicketCreateForm.parseStaffDate('8/19/2026')!.month, 8);
      // Ambiguous: 4-digit year goes with d/m/Y, 2-digit with osTicket's m/d/y.
      final dmy = TicketCreateForm.parseStaffDate('12/11/2026')!;
      expect([dmy.month, dmy.day], [11, 12]);
      final mdy = TicketCreateForm.parseStaffDate('12/11/26')!;
      expect([mdy.month, mdy.day], [12, 11]);
    });

    test('rejects an impossible date instead of rolling it over', () {
      expect(TicketCreateForm.parseStaffDate('20/20/2026'), isNull);
      expect(TicketCreateForm.parseStaffDate('0/8/2026'), isNull);
    });

    test('still accepts ISO values and rejects junk', () {
      expect(
        TicketCreateForm.parseStaffDate('2026-08-19 08:14:00'),
        isNotNull,
      );
      expect(TicketCreateForm.parseStaffDate('not a date'), isNull);
      expect(TicketCreateForm.parseStaffDate(null), isNull);
    });

    test('the form exposes the computed due date', () {
      final form = TicketCreateForm.fromJson(_payload);
      expect(form.duedate, isNotNull);
      expect(form.duedate!.month, 8);
      expect(form.duedate!.day, 19);
    });
  });

  group('field key (the "Priority Level is a required field" bug)', () {
    TicketCreateForm withFields(List<Map<String, dynamic>> fields) =>
        TicketCreateForm.fromJson({..._payload, 'fields': fields});

    test('a named field is addressed by its name', () {
      final f = withFields([
        {'name': 'clientid', 'label': 'Client Id', 'type': 'text', 'id': 45},
      ]).fields.single;
      expect(f.key, 'clientid');
    });

    test('an unnamed field falls back to its id, never an empty key', () {
      // osTicket resolves a field's form name as `name ?: id`, so a custom
      // field with no variable name set in admin is addressed by its id.
      // Keying it by the empty name drops the answer and the create fails with
      // "Priority Level is a required field".
      final f = withFields([
        {'name': '', 'label': 'Priority Level', 'type': 'list-9', 'id': 37},
      ]).fields.single;
      expect(f.key, '37');
      expect(f.key, isNot(''));
    });

    test('unnamed fields do not collide with each other', () {
      final fields = withFields([
        {'name': '', 'label': 'Priority Level', 'type': 'list-9', 'id': 37},
        {'name': '', 'label': 'Impact', 'type': 'list-3', 'id': 38},
      ]).fields;
      expect(fields.map((f) => f.key).toSet(), {'37', '38'},
          reason: 'each answer needs its own slot');
    });

    test('whitespace-only names are treated as unnamed', () {
      final f = withFields([
        {'name': '   ', 'label': 'Impact', 'type': 'text', 'id': 12},
      ]).fields.single;
      expect(f.key, '12');
    });
  });

  group('SLA plan options', () {
    test('none when the backend publishes no list', () {
      // Today's deployment: no SLA list anywhere, so the row stays read-only.
      expect(TicketCreateForm.fromJson(_payload).slas, isEmpty);
    });

    test('parses a wrapped {values: []} list, like sources/statuses', () {
      final form = TicketCreateForm.fromJson({
        ..._payload,
        'slas': {
          'default': 3,
          'values': [
            {'id': 0, 'name': 'System Default'},
            {'id': 3, 'name': 'High (2 hours - Active)'},
          ],
        },
      });
      expect(form.slas.map((o) => o.label),
          ['System Default', 'High (2 hours - Active)']);
      expect(form.slas.first.value, '0');
    });

    test('also accepts a bare list under sla_plans', () {
      final form = TicketCreateForm.fromJson({
        ..._payload,
        'sla_plans': [
          {'id': 2, 'name': 'Default SLA'},
        ],
      });
      expect(form.slas.single.value, '2');
      expect(form.slas.single.label, 'Default SLA');
    });

    test('skips malformed rows instead of throwing', () {
      final form = TicketCreateForm.fromJson({
        ..._payload,
        'slas': [
          'nonsense',
          {'name': 'no id'},
          {'id': 5},
        ],
      });
      expect(form.slas.single.value, '5');
      expect(form.slas.single.label, '#5', reason: 'falls back to the id');
    });
  });

  group('subject/message duplication', () {
    TicketCreateForm withFields(List<Map<String, dynamic>> fields) =>
        TicketCreateForm.fromJson({..._payload, 'fields': fields});

    test('a stock topic form leaves subject/message to the client', () {
      // The endpoint excludes the built-ins, so nothing here stands in for them
      // and the screen must render its own inputs.
      final form = TicketCreateForm.fromJson(_payload);
      expect(form.summaryField, isNull);
      expect(form.detailsField, isNull);
    });

    test('detects a topic that publishes its own summary/description', () {
      final form = withFields([
        {'name': 'issue_summary', 'label': 'Issue Summary', 'type': 'text'},
        {'name': 'desc', 'label': 'Description', 'type': 'memo'},
      ]);
      expect(form.summaryField?.name, 'issue_summary');
      expect(form.detailsField?.name, 'desc');
    });

    test('matches on the field name as well as the label', () {
      final form = withFields([
        {'name': 'subject', 'label': 'Betreff', 'type': 'text'},
        {'name': 'message', 'label': 'Nachricht', 'type': 'memo'},
      ]);
      expect(form.summaryField?.name, 'subject');
      expect(form.detailsField?.name, 'message');
    });

    test('does not mistake similarly-named fields for the body', () {
      // "Resolution" / "Preventive Action" are ordinary fields on this install
      // and must not be swallowed as the issue description.
      final form = withFields([
        {'name': 'resolution', 'label': 'Resolution', 'type': 'memo'},
        {'name': 'preventive', 'label': 'Preventive Action', 'type': 'memo'},
        {'name': 'summary_of_calls', 'label': 'Summary of calls', 'type': 'text'},
      ]);
      expect(form.detailsField, isNull);
      expect(form.summaryField, isNull, reason: 'only an exact match counts');
    });
  });
}
