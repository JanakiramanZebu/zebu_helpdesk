import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_exception.dart';
import 'package:zebu_helpdesk/models/common.dart';
import 'package:zebu_helpdesk/models/meta.dart';
import 'package:zebu_helpdesk/widgets/tags_dialog.dart';

/// The shared tag vocabulary `GET /meta/tags` serves.
List<MetaItem> shared(List<String> names) => [
  for (var i = 0; i < names.length; i++)
    MetaItem(id: i + 1, name: names[i], color: '#336699'),
];

Tag tag(int id, String name) => Tag(id: id, name: name);

/// Records what the dialog asked the server to do, so a test can assert the
/// diff it committed rather than just what it drew.
class _Calls {
  final added = <int>[];
  final removed = <int>[];
  final created = <String>[];
}

/// Opens the dialog over a bare app and returns the calls it made plus the
/// list it resolved with. [rejectAdd] makes every add fail the way the API
/// rejects an unknown/invisible tag: blank message, detail in `fields`.
Future<(_Calls, List<Tag>?)> open(
  WidgetTester tester, {
  required List<Tag> applied,
  required List<MetaItem> options,
  bool rejectAdd = false,
  bool canCreate = false,
  bool rejectCreate = false,
}) async {
  final calls = _Calls();
  var current = [...applied];
  List<Tag>? result;
  var resolved = false;

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showTagsDialog(
                context,
                loadApplied: () async => current,
                loadShared: () async => options,
                addTag: (id) async {
                  calls.added.add(id);
                  if (rejectAdd) {
                    throw ApiException(
                      statusCode: 422,
                      code: 'validation',
                      message: ' ',
                      fields: const {'tag': 'Unknown tag'},
                    );
                  }
                  final name = options.firstWhere((o) => o.id == id).name;
                  current = [...current, tag(id, name)];
                  return current;
                },
                removeTag: (id) async {
                  calls.removed.add(id);
                  current = current.where((t) => t.id != id).toList();
                  return current;
                },
                // Only an admin or department manager gets this — the same
                // `Tag::canCreate()` gate the web's select2 opens `tags: true`
                // for. `rejectCreate` is the server refusing the name.
                createTag: canCreate
                    ? (name) async {
                        calls.created.add(name);
                        if (rejectCreate) {
                          throw ApiException(
                            statusCode: 422,
                            code: 'validation',
                            message: ' ',
                            fields: const {
                              'tag': 'Unknown tag, or not allowed to create it',
                            },
                          );
                        }
                        current = [
                          ...current,
                          tag(100 + calls.created.length, name),
                        ];
                        return current;
                      }
                    : null,
              );
              resolved = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(resolved, isFalse, reason: 'dialog should still be open');
  return (calls, result);
}

/// The dialog's primary button. `find.text('Save')` alone would also match a
/// tag literally named Save.
Finder get saveButton => find.widgetWithText(InkWell, 'Save');

void main() {
  testWidgets('lists the whole shared vocabulary, not just applied tags', (
    tester,
  ) async {
    await open(
      tester,
      applied: [tag(2, 'Billing')],
      options: shared(['Urgent', 'Billing', 'KYC']),
    );

    expect(find.text('Urgent'), findsOneWidget);
    expect(find.text('Billing'), findsOneWidget);
    expect(find.text('KYC'), findsOneWidget);
  });

  testWidgets('Save is inert until the selection changes', (tester) async {
    await open(
      tester,
      applied: const [],
      options: shared(['Urgent', 'Billing']),
    );

    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.text('Urgent'), findsOneWidget,
        reason: 'a clean Save must not close the dialog');

    await tester.tap(find.text('Urgent'));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.text('Urgent'), findsNothing, reason: 'saved and closed');
  });

  testWidgets('Save commits adds and removes in one pass', (tester) async {
    final (calls, _) = await open(
      tester,
      applied: [tag(2, 'Billing')],
      options: shared(['Urgent', 'Billing', 'KYC']),
    );

    await tester.tap(find.text('Urgent')); // tick
    await tester.tap(find.text('Billing')); // untick
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(calls.added, [1]);
    expect(calls.removed, [2]);
  });

  testWidgets('ticking then unticking leaves nothing to save', (tester) async {
    final (calls, _) = await open(
      tester,
      applied: const [],
      options: shared(['Urgent', 'Billing']),
    );

    await tester.tap(find.text('Urgent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Urgent'));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(calls.added, isEmpty);
    expect(calls.removed, isEmpty);
  });

  testWidgets('a rejected add surfaces the reason instead of failing silently',
      (tester) async {
    await open(
      tester,
      applied: const [],
      options: shared(['Urgent']),
      rejectAdd: true,
    );

    await tester.tap(find.text('Urgent'));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // The API sends a blank message and puts the detail in `fields`; that
    // detail is what the agent has to see.
    expect(find.text('Unknown tag'), findsOneWidget);
    expect(find.text('Urgent'), findsOneWidget, reason: 'dialog stays open');
  });

  testWidgets('an applied tag missing from the shared list stays removable', (
    tester,
  ) async {
    final (calls, _) = await open(
      tester,
      // Department-scoped: applied by another team, so /meta/tags omits it.
      applied: [tag(9, 'Escalation')],
      options: shared(['Urgent']),
    );

    expect(find.text('Escalation'), findsOneWidget);
    await tester.tap(find.text('Escalation'));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(calls.removed, [9]);
  });

  testWidgets('says why an empty shared list is empty', (tester) async {
    await open(tester, applied: const [], options: const []);

    expect(
      find.textContaining('No tags are available for your department'),
      findsOneWidget,
    );
  });

  // --- Creating a tag from the dialog (the web's select2 `tags: true`) ------

  testWidgets('a regular agent gets no way to create a tag', (tester) async {
    await open(
      tester,
      applied: const [],
      options: shared(['Urgent', 'Billing']),
    );

    // No box to type into at all: the list is short, and without the
    // permission there is nothing to type for.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('typing an unknown name offers to create it, and Save mints it', (
    tester,
  ) async {
    final (calls, _) = await open(
      tester,
      applied: const [],
      options: shared(['Urgent', 'Billing']),
      canCreate: true,
    );

    await tester.enterText(find.byType(TextField), 'Refund');
    await tester.pumpAndSettle();
    expect(find.text('Create "Refund"'), findsOneWidget);

    await tester.tap(find.text('Create "Refund"'));
    await tester.pumpAndSettle();
    // Queued, badged, and the box is clear for the next one — nothing sent.
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Refund'), findsOneWidget);
    expect(calls.created, isEmpty);

    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(calls.created, ['Refund']);
    expect(calls.added, isEmpty);
  });

  testWidgets('pressing Enter queues the typed name', (tester) async {
    final (calls, _) = await open(
      tester,
      applied: const [],
      options: shared(['Urgent']),
      canCreate: true,
    );

    await tester.enterText(find.byType(TextField), 'Refund');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('New'), findsOneWidget);

    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(calls.created, ['Refund']);
  });

  testWidgets('an existing tag is offered as a tick, not a duplicate', (
    tester,
  ) async {
    final (calls, _) = await open(
      tester,
      applied: const [],
      options: shared(['Urgent', 'Billing']),
      canCreate: true,
    );

    // Different case: the server dedupes on a normalised slug, so creating
    // this would be a no-op at best and a confusing error at worst.
    await tester.enterText(find.byType(TextField), 'urgent');
    await tester.pumpAndSettle();
    expect(find.textContaining('Create "'), findsNothing);

    await tester.tap(find.text('Urgent'));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(calls.created, isEmpty);
    expect(calls.added, [1]);
  });

  testWidgets('a queued name can be dropped before Save', (tester) async {
    final (calls, _) = await open(
      tester,
      applied: const [],
      options: shared(['Urgent']),
      canCreate: true,
    );

    await tester.enterText(find.byType(TextField), 'Refund');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create "Refund"'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refund')); // untick the queued row
    await tester.pumpAndSettle();
    expect(find.text('New'), findsNothing);

    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(calls.created, isEmpty, reason: 'nothing left to commit');
  });

  testWidgets('a refused name keeps what was typed, with the reason', (
    tester,
  ) async {
    await open(
      tester,
      applied: const [],
      options: shared(['Urgent']),
      canCreate: true,
      rejectCreate: true,
    );

    await tester.enterText(find.byType(TextField), 'Refund');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create "Refund"'));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(
      find.text('Unknown tag, or not allowed to create it'),
      findsOneWidget,
    );
    expect(find.text('Refund'), findsOneWidget, reason: 'still queued');
  });

  testWidgets('an empty vocabulary invites the first tag when allowed', (
    tester,
  ) async {
    await open(
      tester,
      applied: const [],
      options: const [],
      canCreate: true,
    );

    expect(
      find.textContaining('Type a name above to create the first one'),
      findsOneWidget,
    );
  });
}
