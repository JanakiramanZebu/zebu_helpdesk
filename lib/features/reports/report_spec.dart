import '../../models/meta.dart';

/// The vocabulary of the Reports & Exports screen: the four record types, the
/// filter names the server advertises, and the two status vocabularies the
/// export endpoints accept.
///
/// Kept apart from the screen so the payload shapes are testable without
/// pumping a widget. Everything *else* the screen needs — which filters a type
/// supports, which columns exist, what is preselected — is now served by
/// `GET /reports/exports/{type}/fields` and lives in `ReportFieldSet`.

/// The record types `GET /reports/exports` returns, in the fixed order it
/// returns them. Held locally as well so the tab strip can render before the
/// catalog lands, and so a type survives as a value the screen can switch on.
enum ReportType {
  tickets('tickets', 'Tickets'),
  tasks('tasks', 'Tasks'),
  users('users', 'Users'),
  orgs('orgs', 'Organizations');

  const ReportType(this.key, this.label);

  /// The path segment used by `/reports/exports/{type}/fields` and `/link`.
  final String key;
  final String label;

  static ReportType? fromKey(String key) {
    for (final t in values) {
      if (t.key == key) return t;
    }
    return null;
  }
}

/// The filter controls a type can ask for, as named in a `ReportFieldSet`.
abstract final class ReportFilter {
  static const dateRange = 'date_range';
  static const status = 'status';
  static const department = 'department';
  static const topic = 'topic';
  static const agent = 'agent';
}

// ---------------------------------------------------------------------------
// Ticket status
// ---------------------------------------------------------------------------

/// Pseudo-ids for the two state shortcuts osTicket's own Reports page lists
/// above the individual statuses — "— Any open status —" and "— Any closed
/// status —". Negative so they can never collide with a real status id, which
/// lets both live in one `Set<int>` behind the shared multi-select sheet.
const anyOpenStatusId = -1;
const anyClosedStatusId = -2;

/// The ticket status picker's options, in the web's order: both state
/// shortcuts first, then every status from `GET /meta/statuses`.
List<MetaItem> ticketStatusOptions(List<MetaItem> statuses) => [
  const MetaItem(id: anyOpenStatusId, name: 'Any open status'),
  const MetaItem(id: anyClosedStatusId, name: 'Any closed status'),
  ...statuses,
];

/// The selection as `POST /reports/exports/tickets/link` wants it: numeric
/// status ids as strings mixed freely with `state:` tokens, all OR-ed together.
///
/// The shortcuts lead, then the ids in ascending order, so the same selection
/// always mints the same payload.
List<String> ticketStatusPayload(Set<int> selected) => [
  if (selected.contains(anyOpenStatusId)) 'state:open',
  if (selected.contains(anyClosedStatusId)) 'state:closed',
  for (final id in selected.where((id) => id > 0).toList()..sort()) '$id',
];

/// "All", one name, or "N selected" — what a multi-select filter row shows.
String selectionSummary(Set<int> ids, List<MetaItem> items) {
  if (ids.isEmpty) return 'All';
  if (ids.length == 1) {
    for (final i in items) {
      if (i.id == ids.first) return i.name;
    }
  }
  return '${ids.length} selected';
}

// ---------------------------------------------------------------------------
// Task status
// ---------------------------------------------------------------------------

/// The three values `POST /reports/exports/tasks/link` accepts. Unlike the
/// ticket filter this one is single-valued — the endpoint reads only the first
/// element of the array — so the screen renders it as chips, not a sheet.
enum TaskStatusMode {
  all('all', 'All'),
  open('open', 'Open'),
  closed('closed', 'Closed');

  const TaskStatusMode(this.value, this.label);
  final String value;
  final String label;
}

/// `status` for a task export. [TaskStatusMode.all] is sent as an absent key
/// rather than `["all"]`: the endpoint treats them identically and an omitted
/// filter reads more plainly.
List<String>? taskStatusPayload(TaskStatusMode mode) =>
    mode == TaskStatusMode.all ? null : [mode.value];
