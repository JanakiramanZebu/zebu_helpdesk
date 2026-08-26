import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/meta_repository.dart';
import 'package:zebu_helpdesk/data/tasks_repository.dart';
import 'package:zebu_helpdesk/features/tasks/widgets/edit_task_sheet.dart';
import 'package:zebu_helpdesk/models/meta.dart';
import 'package:zebu_helpdesk/models/task.dart';
import 'package:zebu_helpdesk/providers.dart';

/// Secure storage has no platform channel in a unit test, and the fake
/// repository never reaches the network anyway.
class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

ApiClient _client() => ApiClient(tokenStorage: _NoTokens(), dio: Dio());

final _task = Task(
  id: 9,
  number: '000045',
  title: 'Reconcile ledger',
  statusName: 'Open',
  duedate: DateTime(2030, 6, 12, 17),
  priority: const TaskPriority(id: 2, name: 'Normal'),
);

/// Records what each `POST /tasks/{id}/edit` was asked to change.
class _FakeTasks extends TasksRepository {
  _FakeTasks() : super(_client());

  final List<Map<String, dynamic>> edits = [];
  final List<String> notes = [];

  @override
  Future<Task> edit(
    int id, {
    Map<String, dynamic>? fields,
    int? priorityId,
    int? progress,
    int? parentId,
  }) async {
    edits.add({
      if (fields != null) 'fields': fields,
      if (priorityId != null) 'priority_id': priorityId,
      if (progress != null) 'progress': progress,
      if (parentId != null) 'parent_id': parentId,
    });
    return _task;
  }

  @override
  Future<Task> note(
    int id, {
    String? body,
    String? title,
    List<MultipartFile> files = const [],
  }) async {
    notes.add(body ?? '');
    return _task;
  }
}

class _FakeMeta extends MetaRepository {
  _FakeMeta() : super(_client());

  @override
  Future<List<MetaItem>> get(String kind, {bool refresh = false}) async =>
      kind == MetaKind.taskPriorities
      ? const [MetaItem(id: 2, name: 'Normal'), MetaItem(id: 5, name: 'Urgent')]
      : const [];
}

Future<void> _open(
  WidgetTester tester, {
  required _FakeTasks tasks,
  Task? task,
}) async {
  // The form is taller than the default 800x600 surface; give the dialog room
  // so Save is reachable without fighting the scroll view.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(tasks),
        metaRepositoryProvider.overrideWithValue(_FakeMeta()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showEditTaskDialog(context, task: task ?? _task),
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
  testWidgets('shows the web Edit Task fields, due date included', (
    tester,
  ) async {
    await _open(tester, tasks: _FakeTasks());

    expect(find.text('Edit Task'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('Reconcile ledger'), findsOneWidget);
    // The row the tester couldn't find anywhere on a created task.
    expect(find.text('Due Date'), findsOneWidget);
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Parent Task'), findsOneWidget);
  });

  testWidgets('a closed task has no due-date editor', (tester) async {
    // The web swaps the inline pencil for a read-only completion date once the
    // task closes, so there is nothing to edit here either.
    await _open(
      tester,
      tasks: _FakeTasks(),
      task: Task(
        id: 9,
        number: '000045',
        title: 'Reconcile ledger',
        statusName: 'Completed',
        isOpen: false,
        duedate: DateTime(2030, 6, 12, 17),
      ),
    );

    expect(find.text('Due Date'), findsNothing);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('Save is inert until something changes', (tester) async {
    final tasks = _FakeTasks();
    await _open(tester, tasks: tasks);

    // `Task::updateField()` rejects a value that didn't change, so an
    // untouched form must not post at all.
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNull);
    expect(tasks.edits, isEmpty);
  });

  testWidgets('clearing the due date posts it as its own empty field', (
    tester,
  ) async {
    final tasks = _FakeTasks();
    await _open(tester, tasks: tasks);

    await tester.tap(find.text('Clear').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(_saveButton());
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    // One call carrying only the due date: the endpoint drops a rejection
    // silently whenever some *other* field in the same batch applied, so each
    // field goes on its own like the web's inline pencils.
    expect(tasks.edits, [
      {
        'fields': {'duedate': ''},
      },
    ]);
    expect(tasks.notes, isEmpty);
  });

  testWidgets('title and priority go in separate calls, note posts last', (
    tester,
  ) async {
    final tasks = _FakeTasks();
    await _open(tester, tasks: tasks);

    final title = find.ancestor(
      of: find.text('Title'),
      matching: find.byType(TextField),
    );
    await tester.enterText(title, 'Reconcile the ledger');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Normal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Urgent').last);
    await tester.pumpAndSettle();

    final note = find.ancestor(
      of: find.text('Reason for editing the task (optional)'),
      matching: find.byType(TextField),
    );
    await tester.enterText(note, 'Scope changed');
    await tester.pumpAndSettle();

    await tester.ensureVisible(_saveButton());
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();

    expect(tasks.edits, [
      {
        'fields': {'title': 'Reconcile the ledger'},
      },
      {'priority_id': 5},
    ]);
    expect(tasks.notes, ['Scope changed']);
  });
}
