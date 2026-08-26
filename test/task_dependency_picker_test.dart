import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/api_exception.dart';
import 'package:zebu_helpdesk/core/api/paginated.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/tasks_repository.dart';
import 'package:zebu_helpdesk/features/tasks/task_detail_screen.dart';
import 'package:zebu_helpdesk/models/common.dart';
import 'package:zebu_helpdesk/models/me.dart';
import 'package:zebu_helpdesk/models/task.dart';
import 'package:zebu_helpdesk/providers.dart';

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

const _task = Task(
  id: 12,
  number: '000045',
  title: 'Reconcile payouts',
  statusName: 'Open',
  departmentId: 3,
  departmentName: 'Support',
);

/// The task an agent picks as the blocker. Its `#number` is what the UI shows;
/// the id (410) is what the dependency endpoint wants.
const _blocker = Task(
  id: 410,
  number: '000099',
  title: 'Approve payout batch',
  statusName: 'Open',
  departmentId: 3,
  departmentName: 'Support',
);

/// An edge already on the task: this task is blocked by #000099.
const _edge = TaskDependency(
  id: 5,
  required: true,
  blocker: DependencyBlocker(
    id: 410,
    number: '000099',
    title: 'Approve payout batch',
  ),
);

class _FakeTasks extends TasksRepository {
  _FakeTasks() : super(ApiClient(tokenStorage: _NoTokens(), dio: Dio()));

  int? addedDependsOn;
  int? removedDepId;
  List<TaskDependency> deps = const [];

  /// Rejection to throw from [addDependency] instead of linking.
  ApiException? addError;

  /// When true the removal is refused server-side — which this API reports as
  /// a 200 carrying the unchanged edge list.
  bool removeSticks = false;

  @override
  Future<Task> get(int id) async => _task;

  @override
  Future<Paginated<ThreadEntry>> thread(
    int id, {
    int page = 1,
    int limit = 25,
    String? order,
  }) async =>
      const Paginated(items: <ThreadEntry>[], page: 1, limit: 25, total: 0);

  @override
  Future<List<ThreadEvent>> events(int id) async => const [];

  @override
  Future<List<Task>> subtasks(int id) async => const [];

  @override
  Future<List<Tag>> tags(int id) async => const [];

  @override
  Future<List<TaskDependency>> dependencies(int id) async => deps;

  @override
  Future<Paginated<Task>> list(TaskQuery query) async => const Paginated(
    items: [_blocker],
    page: 1,
    limit: 25,
    total: 1,
  );

  @override
  Future<List<TaskDependency>> addDependency(int id, int dependsOnId) async {
    addedDependsOn = dependsOnId;
    final error = addError;
    if (error != null) throw error;
    deps = const [
      TaskDependency(
        id: 5,
        required: true,
        blocker: DependencyBlocker(
          id: 410,
          number: '000099',
          title: 'Approve payout batch',
        ),
      ),
    ];
    return deps;
  }

  @override
  Future<List<TaskDependency>> removeDependency(int id, int depId) async {
    removedDepId = depId;
    if (!removeSticks) {
      deps = deps.where((d) => d.id != depId).toList();
    }
    return deps;
  }
}

Me _agent(List<String> perms) => Me.fromJson({
  'id': 7,
  'name': 'Agent Seven',
  'permissions_by_department': {
    '3': {for (final p in perms) p: 1},
  },
});

Future<_FakeTasks> _openDetails(
  WidgetTester tester, {
  List<String> perms = const ['task.edit'],
  List<TaskDependency> deps = const [],
}) async {
  final repo = _FakeTasks()..deps = deps;
  // A tall surface so the whole Details tab (Dependencies included) is laid
  // out — the tab scrolls, and offscreen sections are never built.
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(repo),
        meProvider.overrideWith((ref) async => _agent(perms)),
      ],
      child: const MaterialApp(home: TaskDetailScreen(taskId: 12)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Details'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  group('task detail — Add dependency', () {
    // TC_662: the old dialog asked for the blocker's internal task id, which an
    // agent has no way of knowing, so a task could never be blocked from the
    // app. The action now opens the shared task picker.
    testWidgets('picks a real task instead of prompting for an id', (
      tester,
    ) async {
      final repo = await _openDetails(tester);

      expect(find.text('No dependencies'), findsOneWidget);
      await tester.tap(find.text('Add dependency'));
      await tester.pumpAndSettle();

      expect(find.text('Select blocking task'), findsOneWidget);
      expect(find.text('Blocking task id'), findsNothing);

      // The picker lists tasks by #number — tap the one to block on.
      await tester.tap(find.text('Approve payout batch'));
      await tester.pumpAndSettle();

      // The internal id goes to the endpoint, not the displayed number.
      expect(repo.addedDependsOn, 410);
      expect(find.text('#000099 Approve payout batch'), findsOneWidget);
    });

    testWidgets('is hidden without task.edit', (tester) async {
      await _openDetails(tester, perms: const []);

      expect(find.text('No dependencies'), findsOneWidget);
      expect(find.text('Add dependency'), findsNothing);
    });

    // TC_799/TC_800: every rejection carries the same headline, with the part
    // an agent can act on in `fields.err`. Toasting the headline alone left
    // "Could not add dependency" and nothing to do about it.
    testWidgets('toasts the server reason, not the generic headline', (
      tester,
    ) async {
      final repo = await _openDetails(tester);
      repo.addError = ApiException(
        statusCode: 422,
        code: 'validation',
        message: 'Could not add dependency',
        fields: const {'err': 'That dependency already exists'},
      );

      await tester.tap(find.text('Add dependency'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve payout batch'));
      await tester.pumpAndSettle();

      expect(find.text('That dependency already exists'), findsOneWidget);
      expect(find.text('Could not add dependency'), findsNothing);
    });

    // The server falls back to `{'err': 'Unknown error'}` when it has no
    // reason of its own — the headline says more than that.
    testWidgets('keeps the headline when the detail is a placeholder', (
      tester,
    ) async {
      final repo = await _openDetails(tester);
      repo.addError = ApiException(
        statusCode: 422,
        code: 'validation',
        message: 'Could not add dependency',
        fields: const {'err': 'Unknown error'},
      );

      await tester.tap(find.text('Add dependency'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve payout batch'));
      await tester.pumpAndSettle();

      expect(find.text('Could not add dependency'), findsOneWidget);
    });
  });

  group('task detail — Remove dependency', () {
    testWidgets('drops the card when the removal sticks', (tester) async {
      final repo = await _openDetails(tester, deps: const [_edge]);

      expect(find.text('#000099 Approve payout batch'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();

      expect(repo.removedDepId, 5);
      expect(find.text('No dependencies'), findsOneWidget);
      expect(find.text('Could not remove dependency'), findsNothing);
    });

    // TC_802: `Task::removeDependency()`'s result is discarded server-side, so
    // a refused removal answers 200 with the edge still in the list — without
    // this check it reads as a success that simply did nothing.
    testWidgets('reports a removal the server silently refused', (
      tester,
    ) async {
      final repo = await _openDetails(tester, deps: const [_edge]);
      repo.removeSticks = true;

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Could not remove dependency'), findsOneWidget);
      expect(find.text('#000099 Approve payout batch'), findsOneWidget);
    });

    testWidgets('is hidden without task.edit', (tester) async {
      await _openDetails(tester, perms: const [], deps: const [_edge]);

      expect(find.text('#000099 Approve payout batch'), findsOneWidget);
      expect(find.byTooltip('Remove'), findsNothing);
    });
  });
}
