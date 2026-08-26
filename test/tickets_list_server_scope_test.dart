import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/paginated.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/meta_repository.dart';
import 'package:zebu_helpdesk/data/tickets_repository.dart';
import 'package:zebu_helpdesk/features/tickets/tickets_list_screen.dart';
import 'package:zebu_helpdesk/models/meta.dart';
import 'package:zebu_helpdesk/models/ticket.dart';
import 'package:zebu_helpdesk/providers.dart';

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

ApiClient _api() => ApiClient(tokenStorage: _NoTokens(), dio: Dio());

/// Records every query the screen sends, so the test can assert what the
/// server was actually asked for.
class _RecordingTickets extends TicketsRepository {
  _RecordingTickets() : super(_api());

  final List<TicketQuery> queries = [];

  @override
  Future<Paginated<Ticket>> list(TicketQuery query) async {
    queries.add(query);
    return Paginated(
      items: [
        Ticket(
          id: 1,
          number: '100001',
          subject: 'Payout not received',
          statusName: 'Open',
          departmentName: 'Support',
          created: DateTime(2026, 8, 1),
        ),
      ],
      page: query.page,
      limit: query.limit,
      total: 7,
    );
  }

  @override
  Future<int> count({String view = 'open', TicketQuery? query}) async {
    if (query != null) queries.add(query);
    return 7;
  }
}

class _NoMeta extends MetaRepository {
  _NoMeta() : super(_api());

  @override
  Future<List<MetaItem>> get(String kind, {bool refresh = false}) async =>
      const [];
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
  });

  // `view=mine` is the web's My Tickets queue server-side now — assigned to me
  // OR to one of my teams, open only. The screen used to pin assignee_id to the
  // signed-in agent because a filter param made the server drop `view`; that
  // pin would now hide every ticket assigned to one of the agent's teams.
  testWidgets('My Tickets asks the server for view=mine with no assignee pin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _RecordingTickets();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ticketsRepositoryProvider.overrideWithValue(repo),
          metaRepositoryProvider.overrideWithValue(_NoMeta()),
        ],
        child: const MaterialApp(home: TicketsListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Tickets').first);
    await tester.pumpAndSettle();

    final mine = repo.queries.where((q) => q.view == 'mine').toList();
    expect(mine, isNotEmpty);
    for (final q in mine) {
      expect(q.assigneeId, isNull);
    }
  });

  // The count for a tab with no search and no date window comes straight from
  // the server: `view` composes with the filter params, so paging every row to
  // recount is wasted work.
  testWidgets('an unfiltered tab is counted by the server, not by paging', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _RecordingTickets();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ticketsRepositoryProvider.overrideWithValue(repo),
          metaRepositoryProvider.overrideWithValue(_NoMeta()),
        ],
        child: const MaterialApp(home: TicketsListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // _gatherAll pages at limit 100; the badge path must never do that here.
    expect(repo.queries.where((q) => q.limit == 100), isEmpty);
    expect(find.text('7 total'), findsOneWidget);
  });
}
