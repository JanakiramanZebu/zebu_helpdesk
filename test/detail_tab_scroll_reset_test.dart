import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/paginated.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/meta_repository.dart';
import 'package:zebu_helpdesk/data/tasks_repository.dart';
import 'package:zebu_helpdesk/data/tickets_repository.dart';
import 'package:zebu_helpdesk/features/tasks/task_detail_screen.dart';
import 'package:zebu_helpdesk/features/tickets/ticket_detail_screen.dart';
import 'package:zebu_helpdesk/models/common.dart';
import 'package:zebu_helpdesk/models/me.dart';
import 'package:zebu_helpdesk/models/meta.dart';
import 'package:zebu_helpdesk/models/task.dart';
import 'package:zebu_helpdesk/models/ticket.dart';
import 'package:zebu_helpdesk/providers.dart';

/// Switching tabs on a ticket / task must open the new tab at the top.
///
/// Both detail screens hang their three tabs off ONE [NestedScrollView], so
/// every tab shares the outer (collapsing-header) offset and the inner list
/// positions ride a single controller. Scrolling the conversation therefore
/// collapsed the header for Details and Activity too — tapping a tab landed
/// the reader halfway down a list they had never scrolled.
class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

ApiClient _api() => ApiClient(tokenStorage: _NoTokens(), dio: Dio());

/// A conversation long enough to scroll the header away.
List<ThreadEntry> _thread() => [
  for (var i = 0; i < 30; i++)
    ThreadEntry(
      id: i,
      type: 'M',
      poster: 'Agent Seven',
      body: 'Entry number $i',
      created: DateTime(2026, 8, 1),
    ),
];

List<ThreadEvent> _events() => [
  for (var i = 0; i < 30; i++)
    ThreadEvent(
      id: i,
      state: 'edited',
      actor: 'Agent Seven',
      description: 'Event $i',
      created: DateTime(2026, 8, 1),
    ),
];

class _FakeTasks extends TasksRepository {
  _FakeTasks() : super(_api());

  @override
  Future<Task> get(int id) async => Task(
    id: 12,
    number: '000045',
    title: 'Reconcile payouts',
    statusName: 'Open',
    departmentId: 3,
    departmentName: 'Support',
  );

  @override
  Future<Paginated<ThreadEntry>> thread(
    int id, {
    int page = 1,
    int limit = 25,
    String? order,
  }) async => Paginated(items: _thread(), page: 1, limit: 30, total: 30);

  @override
  Future<List<ThreadEvent>> events(int id) async => _events();

  @override
  Future<List<Task>> subtasks(int id) async => const [];

  @override
  Future<List<TaskDependency>> dependencies(int id) async => const [];
}

class _FakeTickets extends TicketsRepository {
  _FakeTickets() : super(_api());

  @override
  Future<Ticket> get(int id) async => Ticket(
    id: 9,
    number: '100001',
    subject: 'Payout not received',
    statusName: 'Open',
    departmentId: 3,
    departmentName: 'Support',
    created: DateTime(2026, 8, 1),
  );

  @override
  Future<Paginated<ThreadEntry>> thread(
    int id, {
    int page = 1,
    int limit = 25,
  }) async => Paginated(items: _thread(), page: 1, limit: 30, total: 30);

  @override
  Future<List<ThreadEvent>> events(int id) async => _events();

  @override
  Future<List<Tag>> tags(int id) async => const [];

  @override
  Future<List<Collaborator>> collaborators(int id) async => const [];

  @override
  Future<List<TicketField>> fields(int id) async => const [];
}

class _NoMeta extends MetaRepository {
  _NoMeta() : super(_api());

  @override
  Future<List<MetaItem>> get(String kind, {bool refresh = false}) async =>
      const [];
}

Me _agent() => Me.fromJson({
  'id': 7,
  'name': 'Agent Seven',
  'permissions_by_department': {
    '3': {'task.edit': 1, 'ticket.edit': 1},
  },
});

/// Every vertical scroll position on screen, outermost first: the
/// NestedScrollView's header position, then the active tab's list.
List<ScrollPosition> _positions(WidgetTester t) => t
    .stateList<ScrollableState>(find.byType(Scrollable))
    .where((s) => s.position.axis == Axis.vertical)
    .map((s) => s.position)
    .toList();

void _expectAtTop(WidgetTester t, String where) {
  for (final p in _positions(t)) {
    expect(p.pixels, 0, reason: 'a list is still scrolled $where');
  }
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
  });

  /// A phone-sized viewport: the header has somewhere to collapse to and the
  /// conversation genuinely overflows.
  void phoneViewport(WidgetTester t) {
    t.view.physicalSize = const Size(720, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  testWidgets('task detail — every tab opens at the top', (t) async {
    phoneViewport(t);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          tasksRepositoryProvider.overrideWithValue(_FakeTasks()),
          metaRepositoryProvider.overrideWithValue(_NoMeta()),
          meProvider.overrideWith((ref) async => _agent()),
        ],
        child: const MaterialApp(home: TaskDetailScreen(taskId: 12)),
      ),
    );
    await t.pumpAndSettle();

    // The conversation opens on the newest message, so the header is already
    // scrolled away — exactly the state that used to leak into the next tab.
    expect(_positions(t).first.pixels, greaterThan(0));

    await t.tap(find.text('Details'));
    await t.pumpAndSettle();
    _expectAtTop(t, 'after opening Details');

    await t.tap(find.text('Activity'));
    await t.pumpAndSettle();
    _expectAtTop(t, 'after opening Activity');

    await t.tap(find.text('Conversation'));
    await t.pumpAndSettle();
    _expectAtTop(t, 'after returning to Conversation');
  });

  testWidgets('ticket detail — every tab opens at the top', (t) async {
    phoneViewport(t);
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          ticketsRepositoryProvider.overrideWithValue(_FakeTickets()),
          metaRepositoryProvider.overrideWithValue(_NoMeta()),
          meProvider.overrideWith((ref) async => _agent()),
        ],
        child: const MaterialApp(home: TicketDetailScreen(ticketId: 9)),
      ),
    );
    await t.pumpAndSettle();

    expect(_positions(t).first.pixels, greaterThan(0));

    await t.tap(find.text('Details'));
    await t.pumpAndSettle();
    _expectAtTop(t, 'after opening Details');

    await t.tap(find.text('Activity'));
    await t.pumpAndSettle();
    _expectAtTop(t, 'after opening Activity');

    await t.tap(find.text('Conversation'));
    await t.pumpAndSettle();
    _expectAtTop(t, 'after returning to Conversation');
  });
}
