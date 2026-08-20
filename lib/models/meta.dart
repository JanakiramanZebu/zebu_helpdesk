import '../core/api/json.dart';

/// A generic reference/dropdown item from `GET /meta/{kind}`. Different kinds
/// carry slightly different fields (state for statuses; color for tags/
/// task-priorities); all are optional here.
class MetaItem {
  const MetaItem({
    required this.id,
    required this.name,
    this.state,
    this.color,
    this.active,
  });

  final int id;
  final String name;
  final String? state; // statuses: open | closed
  final String? color; // tags, task-priorities

  /// SLA plans only: whether the plan is enabled. osTicket lists **disabled**
  /// plans alongside active ones (`SLA::getSLAs()` filters nothing) and only an
  /// active plan computes a due date, so the difference decides whether the
  /// due-date field is locked. Null when the server doesn't say.

  final bool? active;

  factory MetaItem.fromJson(Map<String, dynamic> j) {
    final name = J.strOr(j['name']);
    // Whichever way the server states it: an explicit flag, osTicket's flag
    // bits (FLAG_ACTIVE = 0x1), or the label itself.
    bool? active;
    final rawActive =
        j['active'] ?? j['isactive'] ?? j['is_active'] ?? j['enabled'];
    if (rawActive != null) {
      active = J.boolOr(rawActive);
    } else if (j['flags'] != null) {
      active = (J.intOr(j['flags']) & 0x1) != 0;
    } else {
      active = activeFromLabel(name);
    }
    return MetaItem(
      id: J.intOr(j['id']),
      name: name,
      state: J.str(j['state']),
      color: J.str(j['color']),
      active: active,
    );
  }

  /// osTicket renders an SLA plan as `"<name> (<n> hours - Active|Disabled)"`
  /// (`SLA::getSLAs()`), which is exactly what the web's dropdown shows. Read
  /// the state back off that label; null when the label isn't in that shape.
  static bool? activeFromLabel(String label) {
    final m = _slaLabel.firstMatch(label);
    if (m == null) return null;
    return m.group(1)!.toLowerCase() == 'active';
  }

  static final _slaLabel = RegExp(
    r'-\s*(active|disabled)\s*\)\s*$',
    caseSensitive: false,
  );
}

/// Known `kind` values for `GET /meta/{kind}`.
class MetaKind {
  static const queues = 'queues';
  static const statuses = 'statuses';
  static const departments = 'departments';
  static const teams = 'teams';
  static const priorities = 'priorities';
  static const agents = 'agents';
  static const topics = 'topics';
  static const tags = 'tags';
  static const taskPriorities = 'task-priorities';

  /// SLA plans. Singular on the wire (`GET /meta/sla`), unlike the rest.
  static const slaPlans = 'sla';
}
