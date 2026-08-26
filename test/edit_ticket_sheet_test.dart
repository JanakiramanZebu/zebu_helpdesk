import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/meta_repository.dart';
import 'package:zebu_helpdesk/data/tickets_repository.dart';
import 'package:zebu_helpdesk/features/tickets/widgets/edit_ticket_sheet.dart';
import 'package:zebu_helpdesk/models/meta.dart';
import 'package:zebu_helpdesk/models/ticket.dart';
import 'package:zebu_helpdesk/providers.dart';

/// Secure storage has no platform channel in a unit test, and neither fake
/// repository reaches the network anyway.
class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

ApiClient _client() => ApiClient(tokenStorage: _NoTokens(), dio: Dio());

const _ticket = Ticket(
  id: 7,
  number: '000123',
  subject: 'Cannot login',
  statusName: 'Open',
  priority: 'High',
  source: 'Phone',
  topicId: 3,
);

/// Records what `POST /tickets/{id}/edit` was asked to change.
class _FakeTickets extends TicketsRepository {
  _FakeTickets({this.custom = const []}) : super(_client());

  final List<TicketField> custom;
  final List<Map<String, dynamic>> edits = [];
  final List<String> notes = [];

  @override
  Future<List<TicketField>> fields(int id) async => custom;

  @override
  Future<Ticket> editFields(int id, Map<String, dynamic> fields) async {
    edits.add(fields);
    return _ticket;
  }

  @override
  Future<Ticket> note(
    int id, {
    String? body,
    String? title,
    List<MultipartFile> files = const [],
  }) async {
    notes.add(body ?? '');
    return _ticket;
  }
}

class _FakeMeta extends MetaRepository {
  _FakeMeta() : super(_client());

  @override
  Future<List<MetaItem>> get(String kind, {bool refresh = false}) async =>
      switch (kind) {
        MetaKind.topics => const [
          MetaItem(id: 3, name: 'Support'),
          MetaItem(id: 4, name: 'Billing'),
        ],
        MetaKind.priorities => const [
          MetaItem(id: 1, name: 'Low'),
          MetaItem(id: 3, name: 'High'),
        ],
        MetaKind.slaPlans => const [MetaItem(id: 1, name: 'Default SLA')],
        _ => const [],
      };
}

Future<bool?> _open(
  WidgetTester tester, {
  required _FakeTickets tickets,
  Ticket ticket = _ticket,
  bool dueLocked = false,
}) async {
  // The form is taller than the default 800x600 test surface; a real phone
  // scrolls it, but here give the dialog room so Save is reachable.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  bool? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ticketsRepositoryProvider.overrideWithValue(tickets),
        metaRepositoryProvider.overrideWithValue(_FakeMeta()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showEditTicketDialog(
                  context,
                  ticket: ticket,
                  dueLocked: dueLocked,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

Finder _saveButton() => find.widgetWithText(FilledButton, 'Save');

void main() {
  testWidgets('shows the web Update Ticket fields, not just custom ones', (
    tester,
  ) async {
    await _open(tester, tickets: _FakeTickets());

    expect(find.text('Update Ticket'), findsOneWidget);
    // Ticket Information, in the web's order.
    expect(find.text('Ticket Source *'), findsOneWidget);
    expect(find.text('Help Topic *'), findsOneWidget);
    expect(find.text('SLA Plan'), findsOneWidget);
    expect(find.text('Due Date'), findsOneWidget);
    // The ticket's own form answers, pre-filled from the ticket.
    expect(find.text('Subject *'), findsOneWidget);
    expect(find.text('Cannot login'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
  });

  testWidgets('Save is inert until something changes', (tester) async {
    final tickets = _FakeTickets();
    await _open(tester, tickets: tickets);

    // The whole-form POST is what osTicket rejects field by field ("... is
    // already assigned this value"), so an untouched form must not send one.
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNull);
    expect(tickets.edits, isEmpty);
    // ...and the dialog is still standing, with its values intact.
    expect(find.text('Cannot login'), findsOneWidget);
  });

  testWidgets('only the changed field is posted', (tester) async {
    final tickets = _FakeTickets(
      custom: const [
        TicketField(
          name: 'account',
          label: 'Account',
          type: 'text',
          value: 'ZB123',
        ),
      ],
    );
    await _open(tester, tickets: tickets);

    final subject = find.ancestor(
      of: find.text('Subject *'),
      matching: find.byType(TextField),
    );
    await tester.enterText(subject, 'Cannot login on web');
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNotNull);
    await tester.ensureVisible(_saveButton());
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(tickets.edits, [
      {'subject': 'Cannot login on web'},
    ]);
    expect(tickets.notes, isEmpty);
  });

  testWidgets('the internal note posts once, after the field edit', (
    tester,
  ) async {
    final tickets = _FakeTickets();
    await _open(tester, tickets: tickets);

    final note = find.ancestor(
      of: find.text('Reason for editing the ticket (optional)'),
      matching: find.byType(TextField),
    );
    await tester.enterText(note, 'Wrong topic at intake');
    await tester.pumpAndSettle();

    await tester.ensureVisible(_saveButton());
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(tickets.edits, isEmpty);
    expect(tickets.notes, ['Wrong topic at intake']);
  });

  testWidgets('an SLA-driven due date is locked, not editable', (tester) async {
    await _open(tester, tickets: _FakeTickets(), dueLocked: true);

    expect(find.text('Computed from the SLA plan'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.byIcon(Icons.event_outlined), findsNothing);
  });

  testWidgets('a closed ticket says to reopen instead of offering Save', (
    tester,
  ) async {
    await _open(
      tester,
      tickets: _FakeTickets(),
      ticket: const Ticket(
        id: 7,
        number: '000123',
        subject: 'Cannot login',
        statusName: 'Closed',
      ),
    );

    expect(find.text('Reopen the ticket to edit it'), findsOneWidget);
    expect(_saveButton(), findsNothing);
  });
}
