import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/paginated.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/tasks_repository.dart';
import 'package:zebu_helpdesk/features/tasks/task_detail_screen.dart';
import 'package:zebu_helpdesk/models/common.dart';
import 'package:zebu_helpdesk/models/me.dart';
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

Task _task({List<Tag> tags = const []}) => Task(
  id: 12,
  number: '000045',
  title: 'Reconcile payouts',
  statusName: 'Open',
  departmentId: 3,
  departmentName: 'Support',
  tags: tags,
);

/// Serves the task detail plus its side loads. Tags ride on the detail payload
/// itself (`GET /tasks/{id}` carries them), not on a separate call.
class _FakeTasks extends TasksRepository {
  _FakeTasks({this.tags_ = const []})
      : super(ApiClient(tokenStorage: _NoTokens(), dio: Dio()));

  final List<Tag> tags_;

  @override
  Future<Task> get(int id) async => _task(tags: tags_);

  @override
  Future<Paginated<ThreadEntry>> thread(
    int id, {
    int page = 1,
    int limit = 25,
    String? order,
  }) async => const Paginated(items: <ThreadEntry>[], page: 1, limit: 25, total: 0);

  @override
  Future<List<ThreadEvent>> events(int id) async => const [];

  @override
  Future<List<Task>> subtasks(int id) async => const [];

  @override
  Future<List<TaskDependency>> dependencies(int id) async => const [];
}

/// Agent 7 in dept 3, holding [perms] there.
Me _agent(List<String> perms) => Me.fromJson({
  'id': 7,
  'name': 'Agent Seven',
  'permissions_by_department': {
    '3': {for (final p in perms) p: 1},
  },
});

/// Opens the task detail on its Details tab.
Future<void> _openDetails(
  WidgetTester tester, {
  List<Tag> tags = const [],
  List<String> perms = const ['task.edit'],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(_FakeTasks(tags_: tags)),
        meProvider.overrideWith((ref) async => _agent(perms)),
      ],
      child: const MaterialApp(home: TaskDetailScreen(taskId: 12)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Details'));
  await tester.pumpAndSettle();
}

void main() {
  group('task detail — Tags row', () {
    testWidgets('lists the applied tags', (tester) async {
      await _openDetails(
        tester,
        tags: const [Tag(id: 1, name: 'Billing'), Tag(id: 2, name: 'VIP')],
      );

      expect(find.text('Tags'), findsOneWidget);
      expect(find.text('Billing, VIP'), findsOneWidget);
    });

    // An agent who can't edit still needs to *see* the tags — the ⋮ → Tags
    // editor is gated on task.edit, so this row is their only view of them.
    testWidgets('shows them without task.edit too', (tester) async {
      await _openDetails(
        tester,
        tags: const [Tag(id: 1, name: 'Billing')],
        perms: const [],
      );

      expect(find.text('Billing'), findsOneWidget);
    });

    testWidgets('reads "No tags" when the task has none', (tester) async {
      await _openDetails(tester);

      expect(find.text('No tags'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);
    });
  });
}
