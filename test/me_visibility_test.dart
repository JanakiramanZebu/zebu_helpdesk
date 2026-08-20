import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/models/me.dart';

/// This install tightened `Ticket::checkStaffPerm()`: plain department
/// membership grants nothing and neither does having created the ticket, so an
/// agent can file a ticket and immediately lose it (`404 No such ticket` from
/// `GET /tickets/{id}`). `Me.canSeeTicket` is the client-side port that lets
/// the create screen warn before that happens.
///
/// Agent 7: manages dept 3 only, member of team 9.
Me _agent({
  bool isAdmin = false,
  List<int> visibility = const [3],
  List<int> teams = const [9],
}) => Me.fromJson({
  'id': 7,
  'username': 'agent7',
  'name': 'Agent Seven',
  'email': 'a7@example.com',
  'isadmin': isAdmin,
  'computed_capabilities': {
    'visibility_departments': visibility,
    'managed_departments': visibility,
    'team_ids': teams,
  },
});

void main() {
  group('Me.canSeeTicket', () {
    test('a managed department is visible', () {
      expect(_agent().canSeeTicket(departmentId: 3), isTrue);
    });

    test('an unmanaged department is not — creating it changes nothing', () {
      expect(_agent().canSeeTicket(departmentId: 4), isFalse);
    });

    test('being the assignee wins over the department', () {
      expect(
        _agent().canSeeTicket(departmentId: 4, assigneeId: 7),
        isTrue,
      );
      expect(
        _agent().canSeeTicket(departmentId: 4, assigneeId: 8),
        isFalse,
      );
    });

    test('so does the assigned team, but only one of ours', () {
      expect(_agent().canSeeTicket(departmentId: 4, teamId: 9), isTrue);
      expect(_agent().canSeeTicket(departmentId: 4, teamId: 10), isFalse);
    });

    test('an unknown department can only be saved by an assignment', () {
      expect(_agent().canSeeTicket(), isFalse);
      expect(_agent().canSeeTicket(assigneeId: 7), isTrue);
    });

    test('admins see everything', () {
      final admin = _agent(isAdmin: true, visibility: const [], teams: const []);
      expect(admin.canSeeTicket(departmentId: 4), isTrue);
      expect(admin.canSeeTicket(), isTrue);
    });

    test('an access-limited agent sees only their own assignments', () {
      final limited = _agent(visibility: const [], teams: const []);
      expect(limited.canSeeTicket(departmentId: 3), isFalse);
      expect(limited.canSeeTicket(departmentId: 3, assigneeId: 7), isTrue);
    });
  });
}
