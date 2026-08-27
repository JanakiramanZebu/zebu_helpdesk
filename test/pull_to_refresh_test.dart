import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/core/theme/app_theme.dart';
import 'package:zebu_helpdesk/data/agent_directory.dart';
import 'package:zebu_helpdesk/data/meta_repository.dart';
import 'package:zebu_helpdesk/data/team_repository.dart';
import 'package:zebu_helpdesk/features/agents/agents_directory_screen.dart';
import 'package:zebu_helpdesk/features/team/team_availability_screen.dart';
import 'package:zebu_helpdesk/models/me.dart';
import 'package:zebu_helpdesk/models/meta.dart';
import 'package:zebu_helpdesk/models/team_member.dart';
import 'package:zebu_helpdesk/providers.dart';

/// TC_984 — pull-to-refresh reloads the agent list.
///
/// The gesture only reaches a `RefreshIndicator` through an **overscroll**, and
/// Android's default `ClampingScrollPhysics` produces none when the content
/// fits the viewport. A helpdesk roster — narrowed to the agent's own
/// departments, and narrower again once they search — nearly always fits, so
/// the drag was being swallowed. These tests drag on a *short* list, which is
/// the case that used to fail.

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

ApiClient _client() => ApiClient(tokenStorage: _NoTokens(), dio: Dio());

Me _me() => Me.fromJson({
  'id': 7,
  'name': 'Agent Seven',
  'computed_capabilities': {
    'managed_departments': [3],
  },
});

/// Two agents — far short of a screenful, which is the whole point.
class _FakeDirectory extends AgentDirectory {
  _FakeDirectory({this.agents = const [
    MetaItem(id: 1, name: 'Asha Rao'),
    MetaItem(id: 2, name: 'Bala Krishnan'),
  ]}) : super(MetaRepository(_client()));

  final List<MetaItem> agents;
  int loads = 0;

  @override
  Future<AgentPickList> visible(Me me) async {
    loads++;
    return AgentPickList(agents: agents, all: agents, scoped: false);
  }
}

class _FakeTeam extends TeamRepository {
  _FakeTeam() : super(_client());

  int loads = 0;

  @override
  Future<List<TeamMember>> list() async {
    loads++;
    return const [];
  }
}

/// The drag the tester performs: start inside the list and pull down far
/// enough to arm the indicator.
Future<void> _pullDown(WidgetTester t, Finder target) async {
  await t.fling(target, const Offset(0, 320), 1200);
  await t.pumpAndSettle();
}

void main() {
  Future<void> pumpAgents(WidgetTester t, AgentDirectory dir) async {
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          meProvider.overrideWith((ref) async => _me()),
          agentDirectoryProvider.overrideWithValue(dir),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const AgentsDirectoryScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('TC_984 — pulling a short agent list reloads it', (t) async {
    final dir = _FakeDirectory();
    await pumpAgents(t, dir);

    expect(find.text('Asha Rao'), findsOneWidget);
    expect(dir.loads, 1);

    await _pullDown(t, find.text('Asha Rao'));

    expect(dir.loads, 2, reason: 'the pull must reach the refresh indicator');
  });

  testWidgets('the rows stay put while a pull-refresh runs', (t) async {
    final dir = _FakeDirectory();
    await pumpAgents(t, dir);

    // Drag without releasing: the list must still be on screen rather than
    // swapped for a full-screen spinner under the finger.
    final gesture = await t.startGesture(t.getCenter(find.text('Asha Rao')));
    // Past the indicator's arm threshold, in steps, so the drag is a real
    // overscroll rather than one teleporting jump.
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(0, 90));
      await t.pump();
    }
    expect(
      find.text('Asha Rao'),
      findsOneWidget,
      reason: 'the roster must not be replaced by a spinner mid-pull',
    );

    await gesture.up();
    await t.pumpAndSettle();
    expect(dir.loads, 2);
    expect(find.text('Asha Rao'), findsOneWidget);
  });

  testWidgets('an empty roster can still be pulled to retry', (t) async {
    final dir = _FakeDirectory(agents: const []);
    await pumpAgents(t, dir);

    expect(find.text('No agents found'), findsOneWidget);
    expect(dir.loads, 1);

    await _pullDown(t, find.text('No agents found'));

    expect(dir.loads, 2, reason: 'the empty state must be pullable too');
  });

  testWidgets('My Team is pullable with nobody to manage', (t) async {
    final repo = _FakeTeam();
    await t.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          meProvider.overrideWith((ref) async => _me()),
          teamRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const TeamAvailabilityScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('No team members'), findsOneWidget);
    expect(repo.loads, 1);

    await _pullDown(t, find.text('No team members'));

    expect(repo.loads, 2);
  });
}
