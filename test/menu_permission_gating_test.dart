import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/models/me.dart';

/// The web decides which entries an agent sees from permissions, not from
/// being an admin — `RolePermission::has()` is a plain map lookup, so
/// `include/class.nav.php` hides Reports and Canned Responses from an admin
/// who lacks the grant too. These are the ports of those two rules:
///
///  * Canned Responses -> `hasPerm(Canned::PERM_MANAGE, false)`, the roles-only
///    arm (primary department role, or any extended dept-access role).
///  * Reports -> `hasPerm(ReportModel::PERM_EXPORT)` OR the roles arm, so the
///    per-agent grant alone is enough.
Me _agent({
  Map<String, dynamic> own = const {},
  Map<String, dynamic> byDept = const {},
  bool isAdmin = false,
  Map<String, dynamic>? config,
}) => Me.fromJson({
  'id': 7,
  'name': 'Agent Seven',
  'isadmin': isAdmin,
  'global_permissions': own,
  'permissions_by_department': byDept,
  if (config != null) 'config': config,
});

void main() {
  group('Me.canManageCanned — roles only', () {
    test('a role in any department grants it', () {
      expect(
        _agent(byDept: {
          '3': {'canned.manage': 1},
        }).canManageCanned,
        isTrue,
      );
    });

    test('an extended dept-access role counts, not just the primary one', () {
      expect(
        _agent(byDept: {
          '3': {'canned.manage': 0},
          '4': {'canned.manage': 1},
        }).canManageCanned,
        isTrue,
      );
    });

    test('the per-agent grant alone does NOT — the web passes false here', () {
      expect(
        _agent(
          own: {'canned.manage': 1},
          byDept: {
            '3': {'canned.manage': 0},
          },
        ).canManageCanned,
        isFalse,
      );
    });

    test('no role grants it', () {
      expect(
        _agent(byDept: {
          '3': {'canned.manage': 0},
        }).canManageCanned,
        isFalse,
      );
    });

    test('being an admin is not a bypass', () {
      // A real payload states the code explicitly, so this is a denial rather
      // than an install that never published it.
      expect(
        _agent(
          isAdmin: true,
          own: {'canned.manage': 0},
          byDept: {
            '3': {'canned.manage': 0},
          },
        ).canManageCanned,
        isFalse,
      );
    });
  });

  group('Me.canViewReports — per-agent grant OR any role', () {
    test('the per-agent grant is enough on its own', () {
      expect(
        _agent(
          own: {'reports.export': 1},
          byDept: {
            '3': {'reports.export': 0},
          },
        ).canViewReports,
        isTrue,
      );
    });

    test('so is a role in any department', () {
      expect(
        _agent(byDept: {
          '4': {'reports.export': 1},
        }).canViewReports,
        isTrue,
      );
    });

    test('neither -> hidden', () {
      expect(
        _agent(
          own: {'reports.export': 0},
          byDept: {
            '3': {'reports.export': 0},
          },
        ).canViewReports,
        isFalse,
      );
    });

    test('being an admin is not a bypass', () {
      expect(
        _agent(
          isAdmin: true,
          own: {'reports.export': 0},
          byDept: {
            '3': {'reports.export': 0},
          },
        ).canViewReports,
        isFalse,
      );
    });
  });

  group('Me.canInAnyRole', () {
    test('an absent code reads as denied, not as an error', () {
      expect(_agent().canInAnyRole('anything.at.all'), isFalse);
    });

    test('the non-permission keys /me mixes in are never mistaken for one', () {
      // `permissions_by_department` also carries role_id / role_name /
      // department_name; Me parses those to ints, so only real codes can match.
      final me = _agent(byDept: {
        '3': {
          'role_id': 4,
          'role_name': 'Manager',
          'department_name': 'Ops',
          'canned.manage': 0,
        },
      });
      expect(me.canInAnyRole('role_name'), isFalse);
      expect(me.canManageCanned, isFalse);
    });
  });

  group('an unpublished permission falls open', () {
    // scp/api.php's bearer-token bootstrap never loads include/class.report.php
    // (only class.nav.php does, and only staff.inc.php requires that), so
    // `reports.export` is absent from the app's /me entirely. Gating on a code
    // the server never sends would hide Reports from everyone forever.
    test('reports.export missing from the payload -> Reports still shows', () {
      final me = _agent(
        own: {'canned.manage': 0},
        byDept: {
          '3': {'canned.manage': 0},
        },
      );
      expect(me.publishes('reports.export'), isFalse);
      expect(me.canViewReports, isTrue);
    });

    test('once published, the real rule takes over — 0 means denied', () {
      final denied = _agent(
        own: {'reports.export': 0},
        byDept: {
          '3': {'reports.export': 0},
        },
      );
      expect(denied.publishes('reports.export'), isTrue);
      expect(denied.canViewReports, isFalse);

      expect(_agent(own: {'reports.export': 1}).canViewReports, isTrue);
    });

    test('an explicit 0 anywhere counts as published', () {
      // Only the per-dept map carries it; that is still the server saying
      // "I know this code and you do not have it".
      final me = _agent(byDept: {
        '3': {'canned.manage': 0},
      });
      expect(me.publishes('canned.manage'), isTrue);
      expect(me.canManageCanned, isFalse);
    });

    test('canned.manage falls open too when unpublished', () {
      final me = _agent(own: {'reports.export': 1});
      expect(me.publishes('canned.manage'), isFalse);
      expect(me.canManageCanned, isTrue);
    });
  });

  // `scp/canned.php` needs the permission AND `$cfg->isCannedResponseEnabled()`.
  // /me publishes that switch as `config.canned_enabled`.
  group('Me.canManageCanned — the install-wide switch', () {
    test('a disabled install hides the entry from everyone', () {
      expect(
        _agent(
          byDept: {
            '3': {'canned.manage': 1},
          },
          config: {'canned_enabled': false},
        ).canManageCanned,
        isFalse,
      );
    });

    test('an enabled install still needs the role', () {
      expect(
        _agent(
          byDept: {
            '3': {'canned.manage': 1},
          },
          config: {'canned_enabled': true},
        ).canManageCanned,
        isTrue,
      );
      expect(
        _agent(
          byDept: {
            '3': {'canned.manage': 0},
          },
          config: {'canned_enabled': true},
        ).canManageCanned,
        isFalse,
      );
    });

    test('an install that publishes no config block falls open', () {
      expect(
        _agent(byDept: {
          '3': {'canned.manage': 1},
        }).canManageCanned,
        isTrue,
      );
    });
  });

  group('Me.permViewAgents', () {
    test('names the grant that unscopes the agent directory', () {
      expect(Me.permViewAgents, 'visibility.agents');
      expect(
        _agent(own: {'visibility.agents': 1}).can(Me.permViewAgents),
        isTrue,
      );
      expect(_agent().can(Me.permViewAgents), isFalse);
    });
  });
}
