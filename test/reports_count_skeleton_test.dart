import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/meta_repository.dart';
import 'package:zebu_helpdesk/data/reports_repository.dart';
import 'package:zebu_helpdesk/features/reports/reports_screen.dart';
import 'package:zebu_helpdesk/models/meta.dart';
import 'package:zebu_helpdesk/models/reports.dart';
import 'package:zebu_helpdesk/providers.dart';
import 'package:zebu_helpdesk/widgets/skeleton.dart';

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

ApiClient _api() => ApiClient(tokenStorage: _NoTokens(), dio: Dio());

/// Column labels are deliberately unlike the filter labels ("Department",
/// "Help Topic"), so a filter row can be asserted on without a column of the
/// same name matching too.
ReportFieldSet _fields(String type, List<String> filters) => ReportFieldSet(
  type: type,
  label: type,
  count: 1,
  filters: filters.toSet(),
  columns: [
    const ReportColumn(key: 'number', label: 'Number', defaultOn: true),
    const ReportColumn(key: 'created', label: 'Created', defaultOn: false),
  ],
);

/// The catalog is held open by [typesGate] so the loading frame can be
/// inspected; the field sets resolve immediately.
class _Reports extends ReportsRepository {
  _Reports() : super(_api());

  final typesGate = Completer<List<ReportTypeInfo>>();

  @override
  Future<List<ReportTypeInfo>> exportTypes() => typesGate.future;

  @override
  Future<ReportFieldSet> exportFields(String type) async => switch (type) {
    'tickets' => _fields(type, [
      'date_range',
      'status',
      'department',
      'topic',
      'agent',
    ]),
    'tasks' => _fields(type, ['date_range', 'status', 'department', 'agent']),
    _ => _fields(type, ['date_range']),
  };
}

class _Meta extends MetaRepository {
  _Meta() : super(_api());

  @override
  Future<List<MetaItem>> get(String kind, {bool refresh = false}) async =>
      switch (kind) {
        MetaKind.statuses => const [
          MetaItem(id: 1, name: 'Open', state: 'open'),
          MetaItem(id: 3, name: 'Closed', state: 'closed'),
        ],
        MetaKind.departments => const [MetaItem(id: 2, name: 'Support')],
        MetaKind.topics => const [MetaItem(id: 5, name: 'General')],
        MetaKind.agents => const [MetaItem(id: 8, name: 'Asha Rao')],
        _ => const [],
      };
}

const _catalog = [
  ReportTypeInfo(key: 'tickets', label: 'Tickets', count: 42),
  ReportTypeInfo(key: 'tasks', label: 'Tasks', count: 7),
  ReportTypeInfo(key: 'users', label: 'Users', count: 9),
  ReportTypeInfo(key: 'orgs', label: 'Organizations', count: 3),
];

Widget _app(_Reports reports) => ProviderScope(
  overrides: [
    reportsRepositoryProvider.overrideWithValue(reports),
    metaRepositoryProvider.overrideWithValue(_Meta()),
  ],
  child: const MaterialApp(home: ReportsScreen()),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The record counts drive both the tab strip and the access banner. They come
/// from one catalog call now — unfiltered, exactly like the web's "you
/// currently have access to N" line — so they are fetched once and their
/// loading state shows shimmering placeholders rather than spinners.
void main() {
  testWidgets('the catalog shimmers, then fills the tabs and the banner', (
    tester,
  ) async {
    _phone(tester);
    final reports = _Reports();
    await tester.pumpWidget(_app(reports));
    await tester.pump(); // meta resolves; the catalog is still held open

    // Loading: placeholders, never a spinner.
    expect(find.byType(SkeletonBox), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('You currently have access to 42 tickets.'), findsNothing);

    reports.typesGate.complete(_catalog);
    await tester.pumpAndSettle();

    // Loaded: every tab carries its own count, like the web's tab strip.
    expect(find.byType(SkeletonBox), findsNothing);
    expect(find.text('(42)'), findsOneWidget); // Tickets
    expect(find.text('(7)'), findsOneWidget); // Tasks
    expect(find.text('(9)'), findsOneWidget); // Users
    expect(find.text('(3)'), findsOneWidget); // Organizations
    expect(
      find.text('You currently have access to 42 tickets.'),
      findsOneWidget,
    );
  });

  testWidgets('the filter set is whatever the server advertises', (
    tester,
  ) async {
    _phone(tester);
    final reports = _Reports()..typesGate.complete(_catalog);
    await tester.pumpWidget(_app(reports));
    await tester.pumpAndSettle();

    // Tickets: the full filter set, help topic included. Status is the live
    // page's multi-select, not the old All/Open/Closed dropdown.
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Department'), findsOneWidget);
    expect(find.text('Help Topic'), findsOneWidget);
    expect(find.text('Agent'), findsOneWidget);
    expect(find.text('Start date'), findsOneWidget);

    // Tasks: no help topic — matching `filters` for that type — and status
    // collapses to the three values the endpoint reads.
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Department'), findsOneWidget);
    expect(find.text('Help Topic'), findsNothing);
    expect(find.text('Agent'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Open'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Closed'), findsOneWidget);

    // Users: created-date range only.
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    expect(find.text('Status'), findsNothing);
    expect(find.text('Department'), findsNothing);
    expect(find.text('Help Topic'), findsNothing);
    expect(find.text('Agent'), findsNothing);
    expect(find.text('Start date'), findsOneWidget);
  });

  testWidgets('the page is reports.php and nothing else', (tester) async {
    _phone(tester);
    final reports = _Reports()..typesGate.complete(_catalog);
    await tester.pumpWidget(_app(reports));
    await tester.pumpAndSettle();

    // No second tab: the web's Reports page carries only the record exports,
    // and the dashboard's statistics table stays on the dashboard.
    expect(find.text('Statistics'), findsNothing);
    expect(find.byType(TabBar), findsNothing);

    // And one download, not a choice of formats — `scp/reports.php` submits to
    // a single green Download CSV.
    expect(find.text('Download CSV'), findsOneWidget);
    expect(find.text('PDF'), findsNothing);
    expect(find.text('Excel'), findsNothing);
  });
}
