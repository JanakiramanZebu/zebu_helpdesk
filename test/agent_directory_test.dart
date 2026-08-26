import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/agent_directory.dart';
import 'package:zebu_helpdesk/data/meta_repository.dart';
import 'package:zebu_helpdesk/models/me.dart';
import 'package:zebu_helpdesk/models/meta.dart';

/// `/meta/{kind}` without the network. [byDept] is what
/// `GET /meta/agents?dept_id=` answers — the server's own `Dept::getAssignees()`
/// result — and every call is recorded so the tests can prove the roster is
/// narrowed server-side rather than guessed here.
class _FakeMeta extends MetaRepository {
  _FakeMeta({
    required this.agentList,
    this.depts = const [],
    this.byDept = const {},
    this.deptCallFails = false,
  }) : super(ApiClient(tokenStorage: TokenStorage()));

  final List<MetaItem> agentList;
  final List<MetaItem> depts;
  final Map<int, List<MetaItem>> byDept;
  final bool deptCallFails;
  final List<int> scopedCalls = [];

  @override
  Future<List<MetaItem>> get(String kind, {bool refresh = false}) async =>
      kind == MetaKind.agents ? agentList : depts;

  @override
  Future<List<MetaItem>> departments() => get(MetaKind.departments);

  @override
  Future<List<MetaItem>> agentsInDepartment(
    int deptId, {
    bool refresh = false,
  }) async {
    scopedCalls.add(deptId);
    if (deptCallFails) throw StateError('forbidden');
    return byDept[deptId] ?? const [];
  }
}

const _agents = [
  MetaItem(id: 1, name: 'Asha Rao', deptId: 3, deptName: 'Support'),
  MetaItem(id: 2, name: 'Bala Krishnan', deptId: 4, deptName: 'Billing'),
  MetaItem(id: 3, name: 'Chitra Devi', deptId: 3, deptName: 'Support'),
];

const _support = [MetaItem(id: 1, name: 'Asha Rao'), MetaItem(id: 3, name: 'Chitra Devi')];

/// Agent 7 holding [perms] in department 3.
Me _me({Map<String, int> global = const {}, List<int> depts = const [3]}) =>
    Me.fromJson({
      'id': 7,
      'name': 'Agent Seven',
      'global_permissions': global,
      'permissions_by_department': {for (final d in depts) '$d': {'ticket.edit': 1}},
    });

void main() {
  group('AgentDirectory.assignable', () {
    test('takes the department roster from the server', () async {
      final meta = _FakeMeta(
        agentList: _agents,
        depts: const [MetaItem(id: 3, name: 'Support')],
        byDept: const {3: _support},
      );
      final list = await AgentDirectory(meta).assignable(departmentId: 3);

      expect(meta.scopedCalls, [3]);
      expect(list.scoped, isTrue);
      expect(list.agents.map((a) => a.id), [1, 3]);
      expect(list.all.length, 3, reason: 'full roster stays available');
      expect(list.departmentName, 'Support');
    });

    // Callers that only know the department by name (a list row, a bulk
    // action) must still reach the id-based endpoint.
    test('resolves a department name to its id first', () async {
      final meta = _FakeMeta(
        agentList: _agents,
        depts: const [MetaItem(id: 3, name: 'SUPPORT')],
        byDept: const {3: _support},
      );
      final list = await AgentDirectory(meta).assignable(
        departmentName: ' support ',
      );

      expect(meta.scopedCalls, [3]);
      expect(list.agents.map((a) => a.id), [1, 3]);
    });

    test('stays unscoped without a department', () async {
      final meta = _FakeMeta(agentList: _agents);
      final list = await AgentDirectory(meta).assignable();

      expect(meta.scopedCalls, isEmpty);
      expect(list.scoped, isFalse);
      expect(list.agents.length, 3);
    });

    test('stays unscoped when the name matches no department', () async {
      final meta = _FakeMeta(
        agentList: _agents,
        depts: const [MetaItem(id: 4, name: 'Billing')],
      );
      final list = await AgentDirectory(meta).assignable(
        departmentName: 'Support',
      );

      expect(meta.scopedCalls, isEmpty);
      expect(list.scoped, isFalse);
      expect(list.agents.length, 3);
    });

    // Offering a list we can't vouch for is worse than offering all of them:
    // the server re-checks the pick anyway.
    test('falls back to the full roster when the scoped call fails', () async {
      final meta = _FakeMeta(
        agentList: _agents,
        depts: const [MetaItem(id: 3, name: 'Support')],
        deptCallFails: true,
      );
      final list = await AgentDirectory(meta).assignable(departmentId: 3);

      expect(list.scoped, isFalse);
      expect(list.agents.length, 3);
      expect(list.departmentName, 'Support');
    });

    // An install that ignores ?dept_id= answers with everyone; a department
    // note over an unnarrowed list would be a lie.
    test('reports unscoped when the filter narrowed nothing', () async {
      final meta = _FakeMeta(
        agentList: _agents,
        depts: const [MetaItem(id: 3, name: 'Support')],
        byDept: const {3: _agents},
      );
      final list = await AgentDirectory(meta).assignable(departmentId: 3);

      expect(list.scoped, isFalse);
      expect(list.agents.length, 3);
    });
  });

  group('AgentDirectory.isAssignable', () {
    test('rejects an agent the department does not allow', () async {
      final dir = AgentDirectory(
        _FakeMeta(
          agentList: _agents,
          depts: const [MetaItem(id: 3, name: 'Support')],
          byDept: const {3: _support},
        ),
      );

      expect(await dir.isAssignable(2, departmentId: 3), isFalse);
      expect(await dir.isAssignable(1, departmentId: 3), isTrue);
    });

    test('accepts anyone when the scope could not be applied', () async {
      final dir = AgentDirectory(_FakeMeta(agentList: _agents));

      expect(await dir.isAssignable(2), isTrue);
    });
  });

  group('AgentDirectory.visible', () {
    test('narrows the directory to the departments I can access', () async {
      final list = await AgentDirectory(
        _FakeMeta(agentList: _agents),
      ).visible(_me(depts: const [3]));

      expect(list.scoped, isTrue);
      expect(list.agents.map((a) => a.id), [1, 3]);
    });

    test('visibility.agents sees the whole roster', () async {
      final list = await AgentDirectory(_FakeMeta(agentList: _agents)).visible(
        _me(global: const {'visibility.agents': 1}, depts: const [3]),
      );

      expect(list.scoped, isFalse);
      expect(list.agents.length, 3);
    });

    // A row that names no department proves nothing, so it stays in.
    test('keeps an agent whose department the payload omits', () async {
      const roster = [
        MetaItem(id: 1, name: 'Asha Rao', deptId: 3),
        MetaItem(id: 2, name: 'Bala Krishnan', deptId: 4),
        MetaItem(id: 3, name: 'Chitra Devi'),
      ];
      final list = await AgentDirectory(
        _FakeMeta(agentList: roster),
      ).visible(_me(depts: const [3]));

      expect(list.agents.map((a) => a.id), [1, 3]);
    });
  });
}
