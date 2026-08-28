import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/features/tickets/widgets/thread_entry_tile.dart';
import 'package:zebu_helpdesk/models/common.dart';
import 'package:zebu_helpdesk/models/me.dart';
import 'package:zebu_helpdesk/widgets/rich_message_field.dart';
import 'package:zebu_helpdesk/widgets/thread_entry_edit.dart';

/// Agent 7 ("Agent Seven") manages dept 3 and holds `thread.edit` in dept 5
/// only — the two ways osTicket lets you edit somebody else's post.
Me _agent({bool isAdmin = false}) => Me.fromJson({
  'id': 7,
  'username': 'agent7',
  'name': 'Agent Seven',
  'email': 'a7@example.com',
  'isadmin': isAdmin,
  'permissions_by_department': {
    '5': {'thread.edit': 1},
  },
  'computed_capabilities': {
    'visibility_departments': [3],
    'managed_departments': [3],
  },
});

ThreadEntry _entry({
  int id = 1,
  String type = 'N',
  String poster = 'Someone Else',
  String format = 'html',
  bool edited = false,
  bool hasHistory = false,
}) => ThreadEntry.fromJson({
  'id': id,
  'type': type,
  'poster': poster,
  'format': format,
  'body': 'hello',
  'body_html': '<p>hello</p>',
  'created': '2026-08-24 10:00:00',
  'edited': edited,
  'edited_at': edited ? '2026-08-24 11:30:00' : null,
  'editor': edited ? 'Agent Seven' : null,
  'has_history': hasHistory,
});

Future<void> _pumpTile(
  WidgetTester tester, {
  required ThreadEntry entry,
  ValueChanged<ThreadEntry>? onEdit,
  ValueChanged<ThreadEntry>? onHistory,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ThreadEntryTile(
          entry: entry,
          onEdit: onEdit,
          onHistory: onHistory,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ThreadEntry edit metadata', () {
    test('the payload\'s edit fields are parsed', () {
      final e = _entry(edited: true, hasHistory: true);
      expect(e.edited, isTrue);
      expect(e.editor, 'Agent Seven');
      // The API sends UTC without a zone suffix; J.dateTime localises it.
      expect(e.editedAt, DateTime.parse('2026-08-24 11:30:00Z').toLocal());
      expect(e.hasHistory, isTrue);
    });

    test('an un-edited entry carries no marker', () {
      final e = _entry();
      expect(e.edited, isFalse);
      expect(e.editedAt, isNull);
      expect(e.hasHistory, isFalse);
    });
  });

  group('Me.canEditThreadEntry', () {
    test('a reply is editable — the web offers "Edit and Resend"', () {
      // TEA_EditThreadEntry skips type R, but TEA_EditAndResendThreadEntry
      // picks it up under the same isEnabled() test.
      expect(
        _agent().canEditThreadEntry(
          _entry(type: 'R', poster: 'Agent Seven'),
          3,
        ),
        isTrue,
      );
      expect(_agent().canEditThreadEntry(_entry(type: 'R'), 5), isTrue);
      // Still gated by permission, not waved through on type alone.
      expect(_agent().canEditThreadEntry(_entry(type: 'R'), 99), isFalse);
    });

    test('system posts (no poster) are never editable', () {
      expect(_agent().canEditThreadEntry(_entry(poster: ''), 3), isFalse);
    });

    test('your own post is editable anywhere', () {
      expect(
        _agent().canEditThreadEntry(_entry(poster: 'Agent Seven'), 99),
        isTrue,
      );
    });

    test('a department manager may edit posts in that department', () {
      expect(_agent().canEditThreadEntry(_entry(), 3), isTrue);
      expect(_agent().canEditThreadEntry(_entry(), 4), isFalse);
    });

    test('a role holding thread.edit may edit in its department', () {
      expect(_agent().canEditThreadEntry(_entry(), 5), isTrue);
    });

    test('admin is no shortcut — isEnabled() tests roles, not isAdmin()', () {
      // Role::hasPerm has no isAdmin() bypass, and this agent's primary role
      // carries no thread.edit, so dept 99 stays closed to them.
      expect(_agent(isAdmin: true).canEditThreadEntry(_entry(), 99), isFalse);
      expect(_agent(isAdmin: true).canEditThreadEntry(_entry(), 3), isTrue);
      expect(_agent(isAdmin: true).canEditThreadEntry(_entry(), 5), isTrue);
    });

    test('the primary role stands in for an assigned ticket', () {
      // getRole($dept, $assigned) falls back to the primary role when
      // def_assn_role is set, and that attribute defaults to true.
      final agent = Me.fromJson({
        'id': 7,
        'username': 'agent7',
        'name': 'Agent Seven',
        'email': 'a7@example.com',
        'global_permissions': {'thread.edit': 1},
      });
      expect(agent.canEditThreadEntry(_entry(), 99), isTrue);
    });

    test('the server verdict wins over every local guess', () {
      final allowed = ThreadEntry.fromJson({
        'id': 1,
        'type': 'R', // client rule alone would refuse a response
        'poster': 'Someone Else',
        'can_edit': true,
      });
      final refused = ThreadEntry.fromJson({
        'id': 2,
        'type': 'N',
        'poster': 'Agent Seven', // ...and would allow your own note
        'can_edit': false,
      });
      expect(_agent().canEditThreadEntry(allowed, 99), isTrue);
      expect(_agent().canEditThreadEntry(refused, 3), isFalse);
    });
  });

  group('showEditEntryDialog', () {
    // osTicket re-encodes the posted body in the entry's ORIGINAL format
    // (TEA_EditThreadEntry::updateEntry), so an HTML payload for a text entry
    // is stored escaped and the message turns into visible markup. The web
    // dodges that by only mounting its rich editor for `format == 'html'`.
    Future<void> pumpDialog(WidgetTester tester, ThreadEntry entry) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEditEntryDialog(context, entry: entry),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('an html entry gets the rich editor', (tester) async {
      await pumpDialog(tester, _entry());
      expect(find.byType(RichMessageField), findsOneWidget);
    });

    testWidgets('a text entry gets a plain field, seeded from body', (
      tester,
    ) async {
      await pumpDialog(tester, _entry(format: 'text'));
      expect(find.byType(RichMessageField), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'hello');
    });
  });

  group('ThreadEntryTile', () {
    testWidgets('an edited bubble is marked', (tester) async {
      await _pumpTile(tester, entry: _entry(edited: true));
      expect(find.text('Edited'), findsOneWidget);
    });

    testWidgets('an un-edited bubble is not', (tester) async {
      await _pumpTile(tester, entry: _entry());
      expect(find.text('Edited'), findsNothing);
    });

    testWidgets('Edit is offered only when the host allows it', (tester) async {
      await _pumpTile(tester, entry: _entry());
      await tester.longPress(find.byType(ThreadEntryTile));
      await tester.pumpAndSettle();
      expect(find.text('Edit message'), findsNothing);
      expect(find.text('Copy text'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
      await tester.pumpAndSettle();

      ThreadEntry? edited;
      await _pumpTile(tester, entry: _entry(), onEdit: (e) => edited = e);
      await tester.longPress(find.byType(ThreadEntryTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit message'));
      await tester.pumpAndSettle();
      expect(edited?.id, 1);
    });

    testWidgets('View history needs an entry that has some', (tester) async {
      await _pumpTile(tester, entry: _entry(edited: true), onHistory: (_) {});
      await tester.longPress(find.byType(ThreadEntryTile));
      await tester.pumpAndSettle();
      expect(find.text('View history'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await _pumpTile(
        tester,
        entry: _entry(edited: true, hasHistory: true),
        onHistory: (_) {},
      );
      await tester.longPress(find.byType(ThreadEntryTile));
      await tester.pumpAndSettle();
      expect(find.text('View history'), findsOneWidget);
    });
  });
}
