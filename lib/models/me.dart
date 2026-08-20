import '../core/api/json.dart';

/// The authenticated agent (`GET /me`) — identity, profile, roles, permissions,
/// computed visibility, and file limits.
class Me {
  const Me({
    required this.id,
    required this.username,
    required this.name,
    required this.email,
    required this.isAdmin,
    required this.isActive,
    required this.available,
    required this.assignedOnly,
    required this.avatarUrl,
    required this.avatarChangeable,
    required this.profile,
    required this.primaryDepartment,
    required this.globalPermissions,
    required this.permissionsByDepartment,
    required this.visibilityDepartments,
    required this.managedDepartments,
    required this.teamIds,
    required this.limits,
  });

  final int id;
  final String username;
  final String name;
  final String email;
  final bool isAdmin;
  final bool isActive;
  final bool available;
  final bool assignedOnly;
  final String? avatarUrl;
  final bool avatarChangeable;
  final MeProfile profile;
  final NamedDeptRole? primaryDepartment;

  /// Primary-role permission map (`code -> 0|1`). Serves as the collaborator
  /// fallback in [canOn] — same role osTicket falls back to when the agent
  /// holds no role in an object's own department.
  final Map<String, int> globalPermissions;

  /// Per-department role permission maps: `deptId -> { code: 0|1, ... }`. The
  /// source of truth for a role's abilities in a given department. Non-permission
  /// keys the API includes here (`role_id`, `role_name`, `department_name`) are
  /// harmless — [canOn] only ever queries permission codes.
  final Map<int, Map<String, int>> permissionsByDepartment;

  /// Departments whose objects this agent can see (manager/admin visibility).
  final List<int> visibilityDepartments;

  /// Departments this agent manages.
  final List<int> managedDepartments;

  /// Teams this agent belongs to.
  final List<int> teamIds;

  final FileLimits limits;

  /// Global (primary-role) permission test.
  bool can(String permission) => (globalPermissions[permission] ?? 0) == 1;

  /// Whether this agent may perform [permission] on an object owned by
  /// [departmentId]. Ports osTicket's `checkStaffPerm()` permission phase
  /// (`include/class.ticket.php` / `class.task.php`): admins always pass; then
  /// the agent's role in the object's own department; then the primary/global
  /// role as the collaborator fallback. Object *visibility* is assumed already
  /// granted — the backend only returns detail for objects the agent can see,
  /// so a successfully loaded task/ticket has cleared the visibility gate.
  bool canOn(String permission, int? departmentId) {
    if (isAdmin) return true;
    if (departmentId != null) {
      final byDept = permissionsByDepartment[departmentId];
      if (byDept != null && (byDept[permission] ?? 0) == 1) return true;
    }
    return can(permission);
  }

  /// Whether this agent could open a ticket that sits in [departmentId] and is
  /// assigned to [assigneeId] / [teamId].
  ///
  /// Ports the *visibility* phase of osTicket's `Ticket::checkStaffPerm()`
  /// (`include/class.ticket.php`), which this install tightened: admins see
  /// everything, otherwise it takes a department the agent **manages**
  /// (`Staff::getVisibilityDepts()`, published here as
  /// [visibilityDepartments]), being the assignee, or being on the assigned
  /// team. Plain department membership is deliberately not honored, and
  /// **opening a ticket grants its creator nothing** — so a ticket filed into a
  /// department the agent merely belongs to, and left unassigned, is invisible
  /// to them the moment it exists (`GET /tickets/{id}` → `404 No such ticket`).
  ///
  /// Staff-collaborator and referral access also grant visibility server-side,
  /// but neither can be set while a ticket is being created, so this is exact
  /// for the create form. A null [departmentId] means "not known yet": only an
  /// assignment can promise visibility then.
  bool canSeeTicket({int? departmentId, int? assigneeId, int? teamId}) {
    if (isAdmin) return true;
    if (assigneeId != null && assigneeId == id) return true;
    if (teamId != null && teamIds.contains(teamId)) return true;
    return departmentId != null &&
        visibilityDepartments.contains(departmentId);
  }

  factory Me.fromJson(Map<String, dynamic> j) {
    final avatar = J.map(j['avatar']);
    final perms = <String, int>{};
    J.map(j['global_permissions']).forEach((k, v) => perms[k] = J.intOr(v));

    final byDept = <int, Map<String, int>>{};
    if (j['permissions_by_department'] is Map) {
      J.map(j['permissions_by_department']).forEach((k, v) {
        final deptId = int.tryParse(k.toString());
        if (deptId == null || v is! Map) return;
        final m = <String, int>{};
        J.map(v).forEach((pk, pv) => m[pk] = J.intOr(pv));
        byDept[deptId] = m;
      });
    }

    final caps = J.map(j['computed_capabilities']);
    List<int> intList(dynamic x) =>
        J.list(x).map((e) => J.intOr(e)).toList();

    return Me(
      id: J.intOr(j['id']),
      username: J.strOr(j['username']),
      name: J.strOr(j['name']),
      email: J.strOr(j['email']),
      isAdmin: J.boolOr(j['isadmin']),
      isActive: J.boolOr(j['isactive'], true),
      available: J.boolOr(j['available'], true),
      assignedOnly: J.boolOr(j['assigned_only']),
      avatarUrl: J.str(avatar['url']),
      avatarChangeable: J.boolOr(avatar['changeable']),
      profile: MeProfile.fromJson(J.map(j['profile'])),
      primaryDepartment: j['primary_department'] is Map
          ? NamedDeptRole.fromJson(J.map(j['primary_department']))
          : null,
      globalPermissions: perms,
      permissionsByDepartment: byDept,
      visibilityDepartments: intList(caps['visibility_departments']),
      managedDepartments: intList(caps['managed_departments']),
      teamIds: intList(caps['team_ids']),
      limits: FileLimits.fromJson(J.map(j['limits'])),
    );
  }
}

class MeProfile {
  const MeProfile({
    this.firstname,
    this.lastname,
    this.phone,
    this.mobile,
    this.signature,
    this.timezone,
    this.locale,
    this.lang,
    this.maxPageSize = 25,
    this.autoRefreshRate = 0,
    this.onVacation = false,
  });

  final String? firstname;
  final String? lastname;
  final String? phone;
  final String? mobile;
  final String? signature;
  final String? timezone;
  final String? locale;
  final String? lang;
  final int maxPageSize;
  final int autoRefreshRate;
  final bool onVacation;

  factory MeProfile.fromJson(Map<String, dynamic> j) => MeProfile(
    firstname: J.str(j['firstname']),
    lastname: J.str(j['lastname']),
    phone: J.str(j['phone']),
    mobile: J.str(j['mobile']),
    signature: J.str(j['signature']),
    timezone: J.str(j['timezone']),
    locale: J.str(j['locale']),
    lang: J.str(j['lang']),
    maxPageSize: J.intOr(j['max_page_size'], 25),
    autoRefreshRate: J.intOr(j['auto_refresh_rate']),
    onVacation: J.boolOr(j['onvacation']),
  );
}

class NamedDeptRole {
  const NamedDeptRole({
    required this.id,
    required this.name,
    this.roleId,
    this.roleName,
  });
  final int id;
  final String name;
  final int? roleId;
  final String? roleName;

  factory NamedDeptRole.fromJson(Map<String, dynamic> j) => NamedDeptRole(
    id: J.intOr(j['id']),
    name: J.strOr(j['name']),
    roleId: J.intOrNull(j['role_id']),
    roleName: J.str(j['role_name']),
  );
}

class FileLimits {
  const FileLimits({
    this.maxFileSize = 0,
    this.allowedFileTypes = const [],
    this.attachmentsEnabled = false,
  });

  final int maxFileSize;
  final List<String> allowedFileTypes;
  final bool attachmentsEnabled;

  bool get unrestricted => allowedFileTypes.isEmpty;

  factory FileLimits.fromJson(Map<String, dynamic> j) => FileLimits(
    maxFileSize: J.intOr(j['max_file_size']),
    allowedFileTypes: J
        .list(j['allowed_file_types'])
        .map((e) => e.toString())
        .toList(),
    attachmentsEnabled: J.boolOr(j['attachments_enabled']),
  );
}

/// Colleague directory profile (`GET /agents/{id}`).
class AgentProfile {
  const AgentProfile({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.department,
    this.role,
    this.available = true,
    this.openTickets = 0,
  });

  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? department;
  final String? role;
  final bool available;
  final int openTickets;

  factory AgentProfile.fromJson(Map<String, dynamic> j) => AgentProfile(
    id: J.intOr(j['id']),
    name: J.strOr(j['name']),
    email: J.str(j['email']),
    phone: J.str(j['phone']),
    department: J.str(j['department']),
    role: J.str(j['role']),
    available: J.boolOr(j['available'], true),
    openTickets: J.intOr(j['open_tickets']),
  );
}
