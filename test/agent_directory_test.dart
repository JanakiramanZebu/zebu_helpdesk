import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/agent_directory.dart';
import 'package:zebu_helpdesk/data/me_repository.dart';
import 'package:zebu_helpdesk/data/meta_repository.dart';
import 'package:zebu_helpdesk/models/me.dart';
import 'package:zebu_helpdesk/models/meta.dart';

/// `/meta/{kind}` without the network — the lists the pickers would load.
class _FakeMeta extends MetaRepository {
  _FakeMeta({required this.agentList, this.depts = const []})
    : super(ApiClient(tokenStorage: TokenStorage()));

  final List<MetaItem> agentList;
  final List<MetaItem> depts;

  @override
  Future<List<MetaItem>> get(String kind, {bool refresh = false}) async =>
      kind == MetaKind.agents ? agentList : depts;

  @override
  Future<List<MetaItem>> departments() => get(MetaKind.departments);
}

/// `GET /agents/{id}`, counting lookups so the session cache can be checked.
class _FakeMe extends MeRepository {
  _FakeMe(this.profiles) : super(ApiClient(tokenStorage: TokenStorage()));

  final Map<int, AgentProfile> profiles;
  final List<int> lookups = [];

  @override
  Future<AgentProfile> getAgent(int id) async {
    lookups.add(id);
    final p = profiles[id];
    if (p == null) throw StateError('no profile for $id');
    return p;
  }
}

AgentProfile _profile(
  int id,
  String name, {
  String? department,
  bool available = true,
}) => AgentProfile(
  id: id,
  name: name,
  department: department,
  available: available,
);

const _agents = [
  MetaItem(id: 1, name: 'Asha Rao'),
  MetaItem(id: 2, name: 'Bala Krishnan'),
  MetaItem(id: 3, name: 'Chitra Devi'),
];

void main() {
  group('AgentDirectory.assignable', () {
    test('keeps only the department\'s agents', () async {
      final me = _FakeMe({
        1: _profile(1, 'Asha Rao', department: 'Support'),
        2: _profile(2, 'Bala Krishnan', department: 'Billing'),
        3: _profile(3, 'Chitra Devi', department: 'Support'),
      });
      final dir = AgentDirectory(_FakeMeta(agentList: _agents), me);

      final list = await dir.assignable(departmentName: 'Support');

      expect(list.scoped, isTrue);
      expect(list.agents.map((a) => a.id), [1, 3]);
      expect(list.all.length, 3, reason: 'full roster stays available');
      expect(list.departmentName, 'Support');
    });

    test('matches the department case-insensitively and resolves it by id',
        () async {
      final me = _FakeMe({
        1: _profile(1, 'Asha Rao', department: 'Support'),
        2: _profile(2, 'Bala Krishnan', department: 'Billing'),
        3: _profile(3, 'Chitra Devi', department: ' support '),
      });
      final dir = AgentDirectory(
        _FakeMeta(
          agentList: _agents,
          depts: const [MetaItem(id: 7, name: 'SUPPORT')],
        ),
        me,
      );

      final list = await dir.assignable(departmentId: 7);

      expect(list.agents.map((a) => a.id), [1, 3]);
    });

    test('drops agents who are unavailable', () async {
      final me = _FakeMe({
        1: _profile(1, 'Asha Rao', department: 'Support'),
        2: _profile(2, 'Bala Krishnan', department: 'Support', available: false),
        3: _profile(3, 'Chitra Devi', department: 'Billing'),
      });
      final dir = AgentDirectory(_FakeMeta(agentList: _agents), me);

      final list = await dir.assignable(departmentName: 'Support');

      expect(list.agents.map((a) => a.id), [1]);
    });

    test('keeps agents whose profile lookup failed', () async {
      final me = _FakeMe({
        1: _profile(1, 'Asha Rao', department: 'Support'),
        3: _profile(3, 'Chitra Devi', department: 'Billing'),
      }); // id 2 throws
      final dir = AgentDirectory(_FakeMeta(agentList: _agents), me);

      final list = await dir.assignable(departmentName: 'Support');

      expect(list.agents.map((a) => a.id), [1, 2]);
    });

    test('falls back to the full roster when nothing matches', () async {
      final me = _FakeMe({
        1: _profile(1, 'Asha Rao', department: 'Billing'),
        2: _profile(2, 'Bala Krishnan', department: 'Billing'),
        3: _profile(3, 'Chitra Devi', department: 'Billing'),
      });
      final dir = AgentDirectory(_FakeMeta(agentList: _agents), me);

      final list = await dir.assignable(departmentName: 'Support');

      expect(list.scoped, isFalse);
      expect(list.agents.length, 3);
    });

    test('stays unscoped without a department', () async {
      final me = _FakeMe({});
      final dir = AgentDirectory(_FakeMeta(agentList: _agents), me);

      final list = await dir.assignable();

      expect(list.scoped, isFalse);
      expect(list.agents.length, 3);
      expect(me.lookups, isEmpty, reason: 'no department, no hydration');
    });

    test('looks each agent up once per session', () async {
      final me = _FakeMe({
        1: _profile(1, 'Asha Rao', department: 'Support'),
        2: _profile(2, 'Bala Krishnan', department: 'Billing'),
        3: _profile(3, 'Chitra Devi', department: 'Support'),
      });
      final dir = AgentDirectory(_FakeMeta(agentList: _agents), me);

      await dir.assignable(departmentName: 'Support');
      await dir.assignable(departmentName: 'Billing');

      expect(me.lookups..sort(), [1, 2, 3]);
    });

    test('concurrent opens share one hydration pass', () async {
      final me = _FakeMe({
        1: _profile(1, 'Asha Rao', department: 'Support'),
        2: _profile(2, 'Bala Krishnan', department: 'Billing'),
        3: _profile(3, 'Chitra Devi', department: 'Support'),
      });
      final dir = AgentDirectory(_FakeMeta(agentList: _agents), me);

      await Future.wait([
        dir.assignable(departmentName: 'Support'),
        dir.assignable(departmentName: 'Support'),
      ]);

      expect(me.lookups..sort(), [1, 2, 3]);
    });
  });

  group('AgentDirectory.isAssignable', () {
    test('rejects an agent outside the department', () async {
      final me = _FakeMe({
        1: _profile(1, 'Asha Rao', department: 'Support'),
        2: _profile(2, 'Bala Krishnan', department: 'Billing'),
        3: _profile(3, 'Chitra Devi', department: 'Support'),
      });
      final dir = AgentDirectory(_FakeMeta(agentList: _agents), me);

      expect(await dir.isAssignable(2, departmentName: 'Support'), isFalse);
      expect(await dir.isAssignable(1, departmentName: 'Support'), isTrue);
    });

    test('accepts anyone when the scope could not be applied', () async {
      final me = _FakeMe({
        1: _profile(1, 'Asha Rao', department: 'Billing'),
        2: _profile(2, 'Bala Krishnan', department: 'Billing'),
        3: _profile(3, 'Chitra Devi', department: 'Billing'),
      });
      final dir = AgentDirectory(_FakeMeta(agentList: _agents), me);

      expect(await dir.isAssignable(2, departmentName: 'Support'), isTrue);
    });
  });
}
