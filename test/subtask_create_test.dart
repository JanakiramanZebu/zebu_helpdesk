import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/tasks_repository.dart';
import 'package:zebu_helpdesk/features/tasks/create_task_screen.dart';
import 'package:zebu_helpdesk/models/task.dart';

const _parent = Task(
  id: 12,
  number: '5748',
  title: 'testing',
  statusName: 'Open',
  departmentId: 3,
  departmentName: 'IT Development',
);

Future<void> _openSubtaskForm(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(home: CreateTaskScreen(parentTask: _parent)),
    ),
  );
  await tester.pumpAndSettle();
}

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

/// Records the request and answers with a minimal created task.
class _Recording implements HttpClientAdapter {
  RequestOptions? seen;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen = options;
    return ResponseBody.fromString(
      jsonEncode({
        'data': {
          'id': 99,
          'number': '5749',
          'title': 'test 2',
          'status': 'Open',
          'parent_id': 12,
        },
      }),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  // "Add subtask" used to open a title+description sheet that posted neither a
  // department nor a due date. osTicket validates a subtask like any other
  // staff-created task, so every create came back "Could not create task" with
  // the offending fields keyed by numeric id — invisible in the sheet. The
  // action now opens the full create form with the parent pre-filled.
  group('subtask create', () {
    testWidgets('seeds the parent and its department', (tester) async {
      await _openSubtaskForm(tester);

      expect(find.text('New subtask'), findsOneWidget);
      expect(
        find.text('This subtask will be added under #5748'),
        findsOneWidget,
      );
      // Department comes from the parent — the server does not inherit it.
      expect(find.text('IT Development'), findsOneWidget);
      expect(find.text('#5748 · testing'), findsOneWidget);
      expect(find.text('Create subtask'), findsOneWidget);
    });

    testWidgets('names the missing required field instead of failing the API', (
      tester,
    ) async {
      await _openSubtaskForm(tester);

      await tester.enterText(find.byType(TextField).first, 'test 2');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create subtask'));
      await tester.pumpAndSettle();

      expect(find.text('Due date is required'), findsOneWidget);
      // Seeded from the parent, so this one is never the blocker.
      expect(find.text('Please select a department'), findsNothing);
      expect(find.text('Could not create task'), findsNothing);
    });
  });

  // The parent was being posted only as a top-level `parent_id`, which the API
  // applies to the model *after* Task::create() — so it never reached the row.
  group('subtask create payload', () {
    Future<RequestOptions> post({int? parentId}) async {
      final adapter = _Recording();
      final repo = TasksRepository(
        ApiClient(
          tokenStorage: _NoTokens(),
          apiRoot: 'https://example.invalid/api/v2',
          dio: Dio()..httpClientAdapter = adapter,
        ),
      );
      await repo.create({
        'dept_id': 3,
        'title': 'test 2',
        'description': 'testing subtask',
        'parent_id': 12,
        'custom_fields': {'parent_id': 12},
      }, parentId: parentId);
      return adapter.seen!;
    }

    test('a seeded parent posts to the parent-scoped endpoint', () async {
      final req = await post(parentId: 12);

      expect(req.path, '/tasks/12/subtasks');
    });

    test('without a parent it posts to /tasks', () async {
      final req = await post();

      expect(req.path, '/tasks');
    });

    test('carries the parent where TaskInternalForm reads it', () async {
      final req = await post(parentId: 12);
      final body = req.data as Map<String, dynamic>;

      // custom_fields is merged into the form source the internal form parses,
      // which is where the web's locked parent field lands too.
      expect(body['custom_fields'], containsPair('parent_id', 12));
      expect(body['parent_id'], 12);
    });
  });
}
