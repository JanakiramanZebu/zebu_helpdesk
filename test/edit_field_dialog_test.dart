import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/tickets_repository.dart';
import 'package:zebu_helpdesk/features/tickets/widgets/edit_field_dialog.dart';
import 'package:zebu_helpdesk/models/ticket.dart';
import 'package:zebu_helpdesk/providers.dart';

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

const _ticket = Ticket(
  id: 7,
  number: '026870',
  subject: 'test',
  statusName: 'Open',
);

class _FakeTickets extends TicketsRepository {
  _FakeTickets() : super(ApiClient(tokenStorage: _NoTokens(), dio: Dio()));

  final List<Map<String, dynamic>> edits = [];

  @override
  Future<Ticket> editFields(int id, Map<String, dynamic> fields) async {
    edits.add(fields);
    return _ticket;
  }
}

/// Products -> Sub Issue Categories, the cascading pair from the live form.
const _products = TicketField(
  name: 'products',
  label: 'Products',
  type: 'list-2',
  required: true,
  choices: {'1': 'General', '2': 'Trading'},
  value: '1',
);

const _subIssue = TicketField(
  name: 'sub_issue',
  label: 'Sub Issue Categories',
  type: 'list-4',
  required: true,
  parentField: 'products',
  choices: {'10': 'General Query', '20': 'Order Rejected'},
  choicesByParent: {
    '1': {'10': 'General Query'},
    '2': {'20': 'Order Rejected'},
  },
  value: '10',
);

Future<void> _open(
  WidgetTester tester, {
  required _FakeTickets tickets,
  required TicketField field,
  List<TicketField> fields = const [],
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [ticketsRepositoryProvider.overrideWithValue(tickets)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showEditFieldDialog(
                context,
                ticketId: 7,
                field: field,
                fields: fields,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _saveButton() => find.widgetWithText(FilledButton, 'Save');

void main() {
  testWidgets('opens on the tapped field alone, titled with its label', (
    tester,
  ) async {
    const resolution = TicketField(
      name: 'resolution',
      label: 'Resolution',
      type: 'memo',
      required: true,
    );
    await _open(
      tester,
      tickets: _FakeTickets(),
      field: resolution,
      fields: const [_products, _subIssue, resolution],
    );

    // The dialog is titled with the label, and carries that one input.
    expect(find.text('Resolution'), findsOneWidget);
    expect(find.text('Resolution *'), findsOneWidget);
    // The rest of the form stays out of the way.
    expect(find.text('Products *'), findsNothing);
    expect(find.text('Sub Issue Categories *'), findsNothing);
  });

  testWidgets('Save is inert until the answer changes', (tester) async {
    final tickets = _FakeTickets();
    await _open(
      tester,
      tickets: tickets,
      field: const TicketField(
        name: 'client_id',
        label: 'Client Id',
        type: 'text',
        value: '273',
      ),
    );

    // osTicket rejects a write that re-sends the value already stored, so an
    // untouched dialog must not post at all.
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNull);
    expect(tickets.edits, isEmpty);
  });

  testWidgets('posts only the field that was edited', (tester) async {
    final tickets = _FakeTickets();
    await _open(
      tester,
      tickets: tickets,
      field: const TicketField(
        name: 'client_id',
        label: 'Client Id',
        type: 'text',
        value: '273',
      ),
    );

    await tester.enterText(find.byType(TextField), '9001');
    await tester.pumpAndSettle();
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(tickets.edits, [
      {'client_id': '9001'},
    ]);
  });

  testWidgets('a cascading child brings its parent along, so it is selectable', (
    tester,
  ) async {
    final tickets = _FakeTickets();
    await _open(
      tester,
      tickets: tickets,
      field: _subIssue,
      fields: const [_products, _subIssue],
    );

    // Without the parent in the dialog the child would render its blocked
    // state instead of the current answer.
    expect(find.text('Select Products first'), findsNothing);
    expect(find.text('Products *'), findsOneWidget);
    expect(find.text('General'), findsOneWidget);
    expect(find.text('General Query'), findsOneWidget);
    // Nothing changed yet, so there is still nothing to save.
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNull);
  });

  testWidgets('a blank required answer can be filled in from its own row', (
    tester,
  ) async {
    final tickets = _FakeTickets();
    await _open(
      tester,
      tickets: tickets,
      field: const TicketField(
        name: 'resolution',
        label: 'Resolution',
        type: 'memo',
        required: true,
      ),
    );

    expect(find.text('Resolution *'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Closed after callback');
    await tester.pumpAndSettle();
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(tickets.edits, [
      {'resolution': 'Closed after callback'},
    ]);
  });
}
