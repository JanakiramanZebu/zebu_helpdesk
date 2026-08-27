import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/paginated.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/tasks_repository.dart';
import 'package:zebu_helpdesk/features/tasks/create_task_screen.dart';
import 'package:zebu_helpdesk/models/task.dart';
import 'package:zebu_helpdesk/providers.dart';

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

const _parent = Task(
  id: 12,
  number: '5748',
  title: 'testing',
  statusName: 'Open',
  departmentId: 3,
  departmentName: 'IT Development',
);

/// A list row as `GET /tasks` can serve it: `department` came through as a bare
/// name, so the row carries no id to post.
const _rowWithoutDeptId = Task(
  id: 12,
  number: '5748',
  title: 'testing',
  statusName: 'Open',
  departmentName: 'IT Development',
);

class _FakeTasks extends TasksRepository {
  _FakeTasks({required this.row, required this.full})
    : super(ApiClient(tokenStorage: _NoTokens(), dio: Dio()));

  /// What the picker lists.
  final Task row;

  /// What `GET /tasks/{id}` answers with.
  final Task full;

  int getCalls = 0;

  @override
  Future<Paginated<Task>> list(TaskQuery query) async =>
      Paginated(items: [row], page: 1, limit: 25, total: 1);

  @override
  Future<Task> get(int id) async {
    getCalls++;
    return full;
  }
}

Future<_FakeTasks> _openForm(
  WidgetTester tester, {
  Task? parentTask,
  Task row = _parent,
  Task full = _parent,
}) async {
  final repo = _FakeTasks(row: row, full: full);
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [tasksRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: CreateTaskScreen(parentTask: parentTask)),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// Opens the Parent task picker and taps the one row it lists.
Future<void> _pickParent(WidgetTester tester) async {
  await tester.tap(find.text('Parent task'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('testing').last);
  await tester.pumpAndSettle();
}

void main() {
  // TC_790: the header, banner, submit label and success toast were all keyed
  // off the parent handed to the constructor, which the Parent task row cannot
  // change — so clearing the parent left a form that still called itself a
  // subtask "added under #5748", and picking one on a plain new task said
  // nothing at all.
  group('parent task row drives the whole form', () {
    testWidgets('clearing the parent turns it back into a plain task', (
      tester,
    ) async {
      await _openForm(tester, parentTask: _parent);

      expect(find.text('New subtask'), findsOneWidget);
      expect(
        find.text('This subtask will be added under #5748'),
        findsOneWidget,
      );

      // Only the Parent task row has a clear button here — Due date is unset.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('This subtask will be added under #5748'), findsNothing);
      expect(find.text('New subtask'), findsNothing);
      expect(find.text('New task'), findsOneWidget);
      expect(find.text('Create task'), findsOneWidget);
    });

    testWidgets('picking a parent on a new task turns it into a subtask', (
      tester,
    ) async {
      await _openForm(tester);

      expect(find.text('New task'), findsOneWidget);

      await _pickParent(tester);

      expect(find.text('New subtask'), findsOneWidget);
      expect(
        find.text('This subtask will be added under #5748'),
        findsOneWidget,
      );
      expect(find.text('Create subtask'), findsOneWidget);
    });
  });

  // TC_789: the department was seeded in initState only, so a parent chosen
  // through the picker inherited nothing and the agent had to re-pick the
  // department it was already looking at.
  group('a picked parent seeds its department', () {
    testWidgets('from the picked row when it carries the id', (tester) async {
      final repo = await _openForm(tester);

      await _pickParent(tester);

      expect(find.text('IT Development'), findsOneWidget);
      expect(find.text('Please select a department'), findsNothing);
      // The row had everything needed; no second round-trip.
      expect(repo.getCalls, 0);
    });

    testWidgets('falling back to the full task when the row has no id', (
      tester,
    ) async {
      final repo = await _openForm(tester, row: _rowWithoutDeptId);

      await _pickParent(tester);

      expect(repo.getCalls, 1);
      expect(find.text('IT Development'), findsOneWidget);
    });

    testWidgets('a later pick overwrites a hand-picked department', (
      tester,
    ) async {
      const other = Task(
        id: 40,
        number: '5750',
        title: 'testing',
        statusName: 'Open',
        departmentId: 9,
        departmentName: 'Support',
      );
      await _openForm(tester, parentTask: _parent, row: other, full: other);

      expect(find.text('IT Development'), findsOneWidget);

      await _pickParent(tester);

      expect(find.text('Support'), findsOneWidget);
      expect(find.text('IT Development'), findsNothing);
    });
  });
}
