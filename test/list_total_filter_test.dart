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
import 'package:zebu_helpdesk/features/tasks/tasks_list_screen.dart';
import 'package:zebu_helpdesk/features/tickets/tickets_list_screen.dart';
import 'package:zebu_helpdesk/models/ticket.dart';
import 'package:zebu_helpdesk/models/meta.dart';
import 'package:zebu_helpdesk/models/task.dart';
import 'package:zebu_helpdesk/providers.dart';

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

ApiClient _api() => ApiClient(tokenStorage: _NoTokens(), dio: Dio());

final _rows = <Task>[
  Task(
    id: 1,
    number: '000001',
    title: 'Reconcile payouts',
    statusName: 'Open',
    departmentName: 'Support',
    created: DateTime(2026, 8, 1),
  ),
  Task(
    id: 2,
    number: '000002',
    title: 'Renew certificate',
    statusName: 'Open',
    departmentName: 'Support',
    created: DateTime(2026, 8, 2),
  ),
  Task(
    id: 3,
    number: '000003',
    title: 'Archive old files',
    statusName: 'Open',
    departmentName: 'Support',
    created: DateTime(2026, 8, 3),
  ),
];

/// Serves the same three rows to every query, over a server total that is
/// deliberately larger — so an unfiltered header ("40 total") and a searched
/// one ("1 total") can never be confused.
class _FakeTasks extends TasksRepository {
  _FakeTasks() : super(_api());

  @override
  Future<Paginated<Task>> list(TaskQuery query) async =>
      Paginated(items: _rows, page: query.page, limit: query.limit, total: 40);

  @override
  Future<int> count({String view = 'open', TaskQuery? query}) async => 40;
}

final _tickets = <Ticket>[
  Ticket(
    id: 1,
    number: '100001',
    subject: 'Payout not received',
    statusName: 'Open',
    departmentName: 'Support',
    created: DateTime(2026, 8, 1),
  ),
  Ticket(
    id: 2,
    number: '100002',
    subject: 'Certificate renewal',
    statusName: 'Open',
    departmentName: 'Support',
    created: DateTime(2026, 8, 2),
  ),
];

class _FakeTickets extends TicketsRepository {
  _FakeTickets() : super(_api());

  @override
  Future<Paginated<Ticket>> list(TicketQuery query) async => Paginated(
    items: _tickets,
    page: query.page,
    limit: query.limit,
    total: 40,
  );

  @override
  Future<int> count({String view = 'open', TicketQuery? query}) async => 40;
}

class _NoMeta extends MetaRepository {
  _NoMeta() : super(_api());

  @override
  Future<List<MetaItem>> get(String kind, {bool refresh = false}) async =>
      const [];
}

void main() {
  // The layout preference is read from secure storage, which has no platform
  // channel under test.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
  });

  // TC_621 follow-up: the header followed a tab change but not a filter. On a
  // client-counted tab (any search / date window / facet) the list callback
  // shows `_counts[view]`, which is still the pre-filter map while the recount
  // is in flight — and the recount only ever wrote the header back for "mine",
  // so every other tab kept the stale number until the user switched tabs.
  testWidgets('the app-bar total follows a filter without a tab change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tasksRepositoryProvider.overrideWithValue(_FakeTasks()),
          metaRepositoryProvider.overrideWithValue(_NoMeta()),
        ],
        child: const MaterialApp(home: TasksListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // No filter yet: Open is counted by the server, so the list's own total.
    expect(find.text('40 total'), findsOneWidget);

    // Search is one of the client-counted narrowings, and it does not change
    // refreshKey — so the recount is the only thing that can move the header.
    await tester.enterText(find.byType(TextField).first, 'Renew');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('1 total'), findsOneWidget);
    expect(find.text('40 total'), findsNothing);

    // Clearing it puts the server total back, still without touching a tab.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('40 total'), findsOneWidget);
  });

  // The same two lines were wrong on the tickets list.
  testWidgets('the tickets header follows a filter too', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ticketsRepositoryProvider.overrideWithValue(_FakeTickets()),
          metaRepositoryProvider.overrideWithValue(_NoMeta()),
        ],
        child: const MaterialApp(home: TicketsListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('40 total'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Certificate');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('1 total'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('40 total'), findsOneWidget);
  });
}
