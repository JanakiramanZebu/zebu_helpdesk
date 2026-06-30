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
  final Map<String, int> globalPermissions;
  final FileLimits limits;

  bool can(String permission) => (globalPermissions[permission] ?? 0) == 1;

  factory Me.fromJson(Map<String, dynamic> j) {
    final avatar = J.map(j['avatar']);
    final perms = <String, int>{};
    J.map(j['global_permissions']).forEach((k, v) => perms[k] = J.intOr(v));
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
