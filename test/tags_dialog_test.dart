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
}

/// Opens the dialog over a bare app and returns the calls it made plus the
/// list it resolved with. [rejectAdd] makes every add fail the way the API
/// rejects an unknown/invisible tag: blank message, detail in `fields`.
Future<(_Calls, List<Tag>?)> open(
  WidgetTester tester, {
  required List<Tag> applied,
  required List<MetaItem> options,
  bool rejectAdd = false,
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
}
