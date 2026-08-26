import '../core/api/json.dart';

/// One agent a manager is responsible for, from
/// `GET /agents/team-availability` (the port of `scp/team-availability.php`).
class TeamMember {
  const TeamMember({
    required this.id,
    required this.name,
    this.department,
    this.available = false,
    this.active = true,
    this.onVacation = false,
    this.eligible = false,
  });

  final int id;
  final String name;
  final String? department;

  /// The switch the manager owns: whether this agent is opted in to
  /// round-robin auto-assignment.
  final bool available;

  final bool active;
  final bool onVacation;

  /// Whether the agent can actually receive an assignment right now — active,
  /// not on vacation, **and** available. The outcome to show as status, next
  /// to [available] as the control.
  final bool eligible;

  /// Why an available agent still isn't eligible, for the row's status line.
  /// Null when [eligible] already explains itself.
  String? get blockedReason {
    if (eligible) return null;
    if (!active) return 'Inactive';
    if (onVacation) return 'On vacation';
    return available ? null : 'Not available';
  }

  TeamMember copyWith({bool? available, bool? eligible}) => TeamMember(
    id: id,
    name: name,
    department: department,
    available: available ?? this.available,
    active: active,
    onVacation: onVacation,
    eligible: eligible ?? this.eligible,
  );

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
    id: J.intOr(j['id']),
    name: J.strOr(j['name']),
    department: J.strNonBlank(j['department']),
    available: J.boolOr(j['available']),
    active: J.boolOr(j['active'], true),
    onVacation: J.boolOr(j['onvacation']),
    eligible: J.boolOr(j['eligible']),
  );
}
