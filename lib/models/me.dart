import '../core/api/json.dart';
import 'common.dart';

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
    this.cannedEnabled,
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

  /// The agent's **own** permission map (`code -> 0|1`) — `/me` builds it from
  /// `Staff::getPermission()`, i.e. the per-agent grants set in Admin Panel →
  /// Agents → Permissions. Equivalent to osTicket's `hasPerm($code)` (the
  /// `$global = true` arm). Also serves as the collaborator fallback in [canOn].
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

  /// `config.canned_enabled` — the install-wide switch behind osTicket's
  /// `$cfg->isCannedResponseEnabled()`. Null when the install doesn't publish
  /// the `config` block, in which case the flag falls open the same way an
  /// unpublished permission does (see [publishes]).
  final bool? cannedEnabled;

  /// `Staff::PERM_STAFF` — the grant that lets an agent see every colleague
  /// rather than just those in their own departments.
  static const permViewAgents = 'visibility.agents';

  /// Per-agent permission test — osTicket's `hasPerm($permission)`.
  bool can(String permission) => (globalPermissions[permission] ?? 0) == 1;

  /// Whether **any** role this agent holds grants [permission] — their primary
  /// department's role or any extended dept-access role. Ports osTicket's
  /// `Staff::hasPerm($permission, false)` (`include/class.staff.php`), which
  /// walks `getRole()` then every `dept_access` role; `/me` publishes exactly
  /// that role set as [permissionsByDepartment].
  ///
  /// Note there is no admin bypass: `RolePermission::has()` is a plain map
  /// lookup, so the web hides these entries from an admin who lacks the grant
  /// too.
  bool canInAnyRole(String permission) =>
      permissionsByDepartment.values.any((m) => (m[permission] ?? 0) == 1);

  /// Whether this install's `/me` publishes [permission] at all.
  ///
  /// `MeV2Controller::allPermissionCodes()` walks `RolePermission::allPermissions()`
  /// and writes an explicit `1`/`0` for **every** code it knows, so a code that
  /// is simply *absent* was never registered — not denied.
  ///
  /// That distinction matters because osTicket registers each permission from
  /// the bottom of the class file that owns it, and `scp/api.php`'s **bearer
  /// token** bootstrap (the one the app uses) loads far fewer of those files
  /// than the session bootstrap does. `reports.export` is the live example:
  /// `include/class.report.php` is pulled in only via `class.nav.php`, which
  /// only `staff.inc.php` (the cookie path) requires — so the app's `/me` never
  /// carries it, while the same endpoint opened in a logged-in browser does.
  bool publishes(String permission) =>
      globalPermissions.containsKey(permission) ||
      permissionsByDepartment.values.any((m) => m.containsKey(permission));

  /// [test] applied to [permission], but only when this install actually
  /// publishes it — an unpublished permission falls open.
  ///
  /// Gating a menu entry on a code the server never sends would hide it from
  /// **everyone**, forever, which is strictly worse than showing an entry the
  /// backend will refuse anyway (it re-checks server-side). The moment the
  /// install starts publishing the code, the real rule takes over with no app
  /// change needed.
  bool _gate(String permission, bool Function() test) =>
      publishes(permission) ? test() : true;

  /// Whether the Canned Responses **management** screen is available.
  ///
  /// Mirrors `scp/canned.php` + the `kbase` sub-nav in `include/class.nav.php`:
  /// the entry needs `canned.manage` on one of the agent's roles (the
  /// `hasPerm(Canned::PERM_MANAGE, false)` arm). Using a canned response while
  /// replying is a separate, ungated path — this only gates authoring them.
  ///
  /// The page also requires `$cfg->isCannedResponseEnabled()`, published as
  /// [cannedEnabled]; with the feature switched off install-wide the web hides
  /// the entry from everyone, admins included.
  bool get canManageCanned =>
      (cannedEnabled ?? true) &&
      _gate('canned.manage', () => canInAnyRole('canned.manage'));

  /// Whether this agent manages any department — the gate osTicket puts on
  /// its manager-only pages (`Dept::objects()->filter(manager_id = me)`).
  bool get managesAnyDepartment => managedDepartments.isNotEmpty;

  /// Whether the **tag catalogue** is manageable: rename, recolor, enable /
  /// disable, merge, delete. Ports `Tag::canManage()` — an admin, or the
  /// manager of any department.
  ///
  /// (The web shows its Tags *tab* to non-admin managers only, because admins
  /// curate tags from the Admin Panel; mobile has no admin panel, so an admin
  /// gets the same screen rather than no route at all.)
  bool get canManageTags => isAdmin || managesAnyDepartment;

  /// Whether new tags may be created. `Tag::canCreate()` is a separate
  /// permission from managing — it resolves to the same set on this install,
  /// but the destructive controls are gated on [canManageTags] independently
  /// so the two can diverge server-side without the app offering a control
  /// that 403s.
  bool get canCreateTags => isAdmin || managesAnyDepartment;

  /// Whether the agent may author knowledgebase content — currently only the
  /// "Add New Category" action on the Knowledgebase screen.
  ///
  /// Mirrors `scp/categories.php`, which guards its create/update/delete
  /// actions with `hasPerm(FAQ::PERM_MANAGE)` (`faq.manage`). Browsing the KB
  /// is ungated, exactly as the web's `kbase` tab is.
  bool get canManageFaq =>
      _gate('faq.manage', () => can('faq.manage') || canInAnyRole('faq.manage'));

  /// Whether the Reports & Exports screen is available.
  ///
  /// Mirrors the `reports` tab in `include/class.nav.php` and the guard at the
  /// top of `scp/reports.php`, which both read
  /// `hasPerm(ReportModel::PERM_EXPORT) || hasPerm(ReportModel::PERM_EXPORT,
  /// false)` — the agent's own grant OR any of their roles. No admin bypass,
  /// same as the web.
  ///
  /// Note this currently falls open in practice: the app authenticates with a
  /// bearer token, and that bootstrap never registers `reports.export` (see
  /// [publishes]). Until the backend loads `class.report.php` on the API path
  /// the entry shows for every agent, exactly as it did before it was gated.
  bool get canViewReports => _gate(
    'reports.export',
    () => can('reports.export') || canInAnyRole('reports.export'),
  );

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

  /// Whether this agent may rewrite thread entry [entry] on an object in
  /// [departmentId].
  ///
  /// Ports `TEA_EditThreadEntry` (`include/class.thread_actions.php`), the same
  /// action that draws the web's pencil: system posts (no poster) and agent
  /// **responses** are never editable, and beyond that it takes authoring the
  /// post, managing the department, or a role holding `thread.edit`.
  ///
  /// One approximation: the thread payload carries the poster's *name*, not
  /// their staff id, so "I wrote this" is a name match. It only ever widens the
  /// menu — the endpoint runs the real check and 403s a mismatch.
  bool canEditThreadEntry(ThreadEntry entry, int? departmentId) {
    if (entry.isResponse || entry.poster.trim().isEmpty) return false;
    if (entry.poster.trim().toLowerCase() == name.trim().toLowerCase()) {
      return true;
    }
    if (departmentId != null && managedDepartments.contains(departmentId)) {
      return true;
    }
    return canOn('thread.edit', departmentId);
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
      cannedEnabled: j['config'] is Map
          ? (J.map(j['config'])['canned_enabled'] == null
                ? null
                : J.boolOr(J.map(j['config'])['canned_enabled']))
          : null,
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
