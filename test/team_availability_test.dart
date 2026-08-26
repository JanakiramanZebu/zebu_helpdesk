import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/api_exception.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/team_repository.dart';
import 'package:zebu_helpdesk/features/team/team_availability_screen.dart';
import 'package:zebu_helpdesk/models/team_member.dart';
import 'package:zebu_helpdesk/providers.dart';

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

class _FakeTeam extends TeamRepository {
  _FakeTeam({this.rows = const [], this.notFound = false})
    : super(ApiClient(tokenStorage: _NoTokens(), dio: Dio()));

  final List<TeamMember> rows;
  final bool notFound;
  final calls = <String>[];

  @override
  Future<List<TeamMember>> list() async => rows;

  @override
  Future<TeamMember> setAvailable(int agentId, bool available) async {
    calls.add('$agentId=$available');
    if (notFound) {
      throw ApiException(
        statusCode: 404,
        code: 'not_found',
        message: 'No such agent',
      );
    }
    final m = rows.firstWhere((r) => r.id == agentId);
    return m.copyWith(available: available, eligible: available && m.active);
  }
}

const _ashok = TeamMember(
  id: 61,
  name: 'Ashok Kumar P',
  department: 'IT',
  available: false,
  eligible: false,
);

void main() {
  Widget host(_FakeTeam repo) => ProviderScope(
    overrides: [teamRepositoryProvider.overrideWithValue(repo)],
    child: const MaterialApp(home: TeamAvailabilityScreen()),
  );

  // A non-manager gets `{"data": []}` — a normal state, not a failure.
  testWidgets('managing nobody reads as an empty state, not an error', (
    tester,
  ) async {
    await tester.pumpWidget(host(_FakeTeam()));
    await tester.pumpAndSettle();

    expect(find.text('No team members'), findsOneWidget);
    expect(find.textContaining('Retry'), findsNothing);
  });

  testWidgets('toggling opts an employee into auto-assignment', (tester) async {
    final repo = _FakeTeam(rows: const [_ashok]);
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not available'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(repo.calls, ['61=true']);
    // `eligible` is the server's outcome, and it drives the status line.
    expect(find.textContaining('Receiving assignments'), findsOneWidget);
  });

  // 404 here means "not yours to change" — the API will not confirm that an
  // agent outside your departments exists. It must never read as "deleted".
  testWidgets('a 404 says the agent is not yours, not that they are gone', (
    tester,
  ) async {
    final repo = _FakeTeam(rows: const [_ashok], notFound: true);
    await tester.pumpWidget(host(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('no longer in a department you manage'),
      findsOneWidget,
    );
    // The row keeps the server's last known value rather than the failed one.
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });
}
