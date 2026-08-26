import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/features/reports/report_spec.dart';
import 'package:zebu_helpdesk/models/meta.dart';
import 'package:zebu_helpdesk/models/reports.dart';

/// The Reports screen no longer decides what a report *is* — the server does,
/// through `GET /reports/exports/{type}/fields`. What is left on the app side
/// is the two status vocabularies the export endpoints accept, and reading the
/// catalog back. Both are covered here.
void main() {
  group('ticket status payload', () {
    const statuses = [
      MetaItem(id: 1, name: 'Open', state: 'open'),
      MetaItem(id: 2, name: 'Pending', state: 'open'),
      MetaItem(id: 3, name: 'Resolved', state: 'closed'),
    ];

    test('the picker leads with both state shortcuts, then every status', () {
      final options = ticketStatusOptions(statuses);
      expect(options.map((o) => o.name).take(2), [
        'Any open status',
        'Any closed status',
      ]);
      expect(options.skip(2).map((o) => o.id), [1, 2, 3]);
    });

    test('the shortcut ids can never collide with a real status id', () {
      expect(anyOpenStatusId, lessThan(0));
      expect(anyClosedStatusId, lessThan(0));
      expect(anyOpenStatusId, isNot(anyClosedStatusId));
    });

    test('an empty selection sends nothing — every status is included', () {
      expect(ticketStatusPayload({}), isEmpty);
    });

    test('ids go out as strings', () {
      expect(ticketStatusPayload({3, 1}), ['1', '3']);
    });

    test('shortcuts become state: tokens and lead the payload', () {
      expect(ticketStatusPayload({anyOpenStatusId}), ['state:open']);
      expect(ticketStatusPayload({anyClosedStatusId}), ['state:closed']);
      expect(ticketStatusPayload({2, anyOpenStatusId}), [
        'state:open',
        '2',
      ]);
    });

    test('tokens and ids mix freely, in a stable order', () {
      // The endpoint ORs them together, so the same selection must always
      // mint the same payload regardless of the order it was clicked in.
      expect(ticketStatusPayload({3, anyClosedStatusId, 1, anyOpenStatusId}), [
        'state:open',
        'state:closed',
        '1',
        '3',
      ]);
    });
  });

  group('task status payload', () {
    test('All is an absent filter, not a literal "all"', () {
      expect(taskStatusPayload(TaskStatusMode.all), isNull);
    });

    test('the other two are single-element arrays — only the first is read', () {
      expect(taskStatusPayload(TaskStatusMode.open), ['open']);
      expect(taskStatusPayload(TaskStatusMode.closed), ['closed']);
    });
  });

  group('ReportType', () {
    test('the four keys match the path segments the API uses', () {
      expect(ReportType.values.map((t) => t.key), [
        'tickets',
        'tasks',
        'users',
        'orgs',
      ]);
    });

    test('an unknown key is null rather than a wrong tab', () {
      expect(ReportType.fromKey('tickets'), ReportType.tickets);
      expect(ReportType.fromKey('orgs'), ReportType.orgs);
      expect(ReportType.fromKey('queues'), isNull);
    });
  });

  group('selectionSummary', () {
    const items = [
      MetaItem(id: 4, name: 'Support'),
      MetaItem(id: 5, name: 'Billing'),
    ];

    test('nothing selected reads as All', () {
      expect(selectionSummary(const {}, items), 'All');
    });

    test('one selection shows its name', () {
      expect(selectionSummary(const {5}, items), 'Billing');
    });

    test('an unknown single id falls back to the count', () {
      expect(selectionSummary(const {99}, items), '1 selected');
    });

    test('several selections are counted', () {
      expect(selectionSummary(const {4, 5}, items), '2 selected');
    });
  });

  group('ReportFieldSet.fromJson', () {
    // Trimmed from the documented `GET /reports/exports/tickets/fields` body.
    final json = <String, dynamic>{
      'type': 'tickets',
      'label': 'Tickets',
      'count': 128,
      'filters': ['date_range', 'status', 'department', 'topic', 'agent'],
      'columns': [
        {'key': 'number', 'label': 'Ticket Number', 'default': true},
        {'key': 'cdata.subject', 'label': 'Subject', 'default': true},
        {'key': 'source', 'label': 'Source', 'default': false},
        {'key': 'dept::getLocalName', 'label': 'Department', 'default': true},
        {'key': 'cdata.account_no', 'label': 'Account Number',
          'default': false},
      ],
    };

    test('filters land as a set the screen can test membership on', () {
      final set = ReportFieldSet.fromJson(json);
      expect(set.filters, contains(ReportFilter.topic));
      expect(set.filters, contains(ReportFilter.dateRange));
      expect(set.filters, isNot(contains('queue')));
    });

    test('columns keep catalog order — the export follows it', () {
      final set = ReportFieldSet.fromJson(json);
      expect(set.columns.map((c) => c.key), [
        'number',
        'cdata.subject',
        'source',
        'dept::getLocalName',
        'cdata.account_no',
      ]);
    });

    test('the default flags seed the picker, and are not the whole set', () {
      final set = ReportFieldSet.fromJson(json);
      expect(set.defaultColumnKeys, {
        'number',
        'cdata.subject',
        'dept::getLocalName',
      });
      // Omitting `columns` when minting exports everything, so the default
      // subset is strictly a UI hint.
      expect(set.defaultColumnKeys.length, lessThan(set.columns.length));
    });

    test('custom form fields are distinguishable from the fixed set', () {
      final set = ReportFieldSet.fromJson(json);
      final custom = set.columns.where((c) => c.isCustomField).map((c) => c.key);
      // `cdata.subject` is a standard column that happens to live on the form;
      // the flag is about the `cdata.` namespace, which is what varies between
      // installs.
      expect(custom, ['cdata.subject', 'cdata.account_no']);
      expect(
        set.columns.firstWhere((c) => c.key == 'source').isCustomField,
        isFalse,
      );
    });

    test('a missing body degrades to an empty catalog rather than throwing', () {
      final set = ReportFieldSet.fromJson(const {});
      expect(set.columns, isEmpty);
      expect(set.filters, isEmpty);
      expect(set.count, 0);
    });
  });
}
