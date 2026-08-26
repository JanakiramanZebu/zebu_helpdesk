import '../core/api/json.dart';

/// `GET /reports/summary`.
class ReportSummary {
  const ReportSummary({
    required this.totals,
    this.tasks,
    this.byPriority = const [],
    this.byDepartment = const [],
    this.byAgent = const [],
  });

  final ReportTotals totals;

  /// Task counts, visibility-scoped exactly like `GET /tasks`. Null on an
  /// install that doesn't publish the block — the dashboard then hides its
  /// Tasks section rather than showing zeros.
  final TaskTotals? tasks;

  final List<PriorityBucket> byPriority;
  final List<DepartmentBucket> byDepartment;
  final List<AgentBucket> byAgent; // admins only; [] otherwise

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
    totals: ReportTotals.fromJson(J.map(j['totals'])),
    tasks: j['tasks'] is Map ? TaskTotals.fromJson(J.map(j['tasks'])) : null,
    byPriority: J
        .mapList(j['by_priority'])
        .map(PriorityBucket.fromJson)
        .toList(),
    byDepartment: J
        .mapList(j['by_department'])
        .map(DepartmentBucket.fromJson)
        .toList(),
    byAgent: J.mapList(j['by_agent']).map(AgentBucket.fromJson).toList(),
  );
}

class ReportTotals {
  const ReportTotals({
    this.open = 0,
    this.closed = 0,
    this.overdue = 0,
    this.unassigned = 0,
    this.mineOpen = 0,
    this.answered = 0,
    this.total = 0,
  });

  final int open;
  final int closed;
  final int overdue;
  final int unassigned;
  final int mineOpen;
  final int answered;
  final int total;

  factory ReportTotals.fromJson(Map<String, dynamic> j) => ReportTotals(
    open: J.intOr(j['open']),
    closed: J.intOr(j['closed']),
    overdue: J.intOr(j['overdue']),
    unassigned: J.intOr(j['unassigned']),
    mineOpen: J.intOr(j['mine_open']),
    answered: J.intOr(j['answered']),
    total: J.intOr(j['total']),
  );
}

/// The `tasks` block on `GET /reports/summary` — the same four numbers four
/// separate `/tasks?view=…&limit=1` calls used to be read for.
class TaskTotals {
  const TaskTotals({
    this.open = 0,
    this.overdue = 0,
    this.closed = 0,
    this.all = 0,
  });

  final int open;
  final int overdue;
  final int closed;
  final int all;

  factory TaskTotals.fromJson(Map<String, dynamic> j) => TaskTotals(
    open: J.intOr(j['open']),
    overdue: J.intOr(j['overdue']),
    closed: J.intOr(j['closed']),
    all: J.intOr(j['all']),
  );
}

class PriorityBucket {
  const PriorityBucket({
    required this.id,
    required this.priority,
    this.open = 0,
  });
  final int id;
  final String priority;
  final int open;

  factory PriorityBucket.fromJson(Map<String, dynamic> j) => PriorityBucket(
    id: J.intOr(j['priority_id']),
    priority: J.strOr(j['priority']),
    open: J.intOr(j['open']),
  );
}

class DepartmentBucket {
  const DepartmentBucket({
    required this.id,
    required this.dept,
    this.open = 0,
    this.overdue = 0,
  });
  final int id;
  final String dept;
  final int open;
  final int overdue;

  factory DepartmentBucket.fromJson(Map<String, dynamic> j) => DepartmentBucket(
    id: J.intOr(j['dept_id']),
    dept: J.strOr(j['dept']),
    open: J.intOr(j['open']),
    overdue: J.intOr(j['overdue']),
  );
}

class AgentBucket {
  const AgentBucket({
    required this.id,
    required this.name,
    this.open = 0,
    this.overdue = 0,
  });
  final int id;
  final String name;
  final int open;
  final int overdue;

  factory AgentBucket.fromJson(Map<String, dynamic> j) => AgentBucket(
    id: J.intOr(j['staff_id']),
    name: J.strOr(j['name']),
    open: J.intOr(j['open']),
    overdue: J.intOr(j['overdue']),
  );
}

/// `GET /reports/volume`.
class VolumeReport {
  const VolumeReport({
    required this.days,
    this.series = const [],
    this.openedTotal = 0,
    this.closedTotal = 0,
    this.net = 0,
  });

  final int days;
  final List<VolumePoint> series;
  final int openedTotal;
  final int closedTotal;
  final int net;

  factory VolumeReport.fromJson(Map<String, dynamic> j) {
    final totals = J.map(j['totals']);
    return VolumeReport(
      days: J.intOr(j['days']),
      series: J.mapList(j['series']).map(VolumePoint.fromJson).toList(),
      openedTotal: J.intOr(totals['opened']),
      closedTotal: J.intOr(totals['closed']),
      net: J.intOr(totals['net']),
    );
  }
}

class VolumePoint {
  const VolumePoint({required this.date, this.opened = 0, this.closed = 0});
  final String date; // YYYY-MM-DD
  final int opened;
  final int closed;

  factory VolumePoint.fromJson(Map<String, dynamic> j) => VolumePoint(
    date: J.strOr(j['date']),
    opened: J.intOr(j['opened']),
    closed: J.intOr(j['closed']),
  );
}

// ---------------------------------------------------------------------------
// Reports & Exports — `scp/reports.php`
// ---------------------------------------------------------------------------

/// One row of the record-type catalog from `GET /reports/exports` — the tab
/// labels on the web's Reports page, each with the count the caller can see.
class ReportTypeInfo {
  const ReportTypeInfo({
    required this.key,
    required this.label,
    this.count = 0,
  });

  /// `tickets` | `tasks` | `users` | `orgs`.
  final String key;
  final String label;

  /// Visibility-scoped for tickets/tasks; the install total for users/orgs.
  /// Unfiltered either way — it is the web's "you currently have access to N"
  /// number, not a preview of what the current filters would export.
  final int count;

  factory ReportTypeInfo.fromJson(Map<String, dynamic> j) => ReportTypeInfo(
    key: J.strOr(j['key']),
    label: J.strOr(j['label']),
    count: J.intOr(j['count']),
  );
}

/// One exportable column from `GET /reports/exports/{type}/fields`.
class ReportColumn {
  const ReportColumn({
    required this.key,
    required this.label,
    this.defaultOn = false,
  });

  /// The literal ORM path to send back when minting a link — dotted relation
  /// traversal (`cdata.subject`, `user.name`) or a model method call
  /// (`dept::getLocalName`). Not the `__` filter syntax used elsewhere.
  final String key;
  final String label;

  /// What the web's own picker preselects. A UI hint only: omitting `columns`
  /// when minting exports **all** columns, not just these.
  final bool defaultOn;

  /// Custom form fields, appended after the fixed set. Worth flagging in the
  /// picker because they are what differs between installs.
  bool get isCustomField => key.startsWith('cdata.');

  factory ReportColumn.fromJson(Map<String, dynamic> j) => ReportColumn(
    key: J.strOr(j['key']),
    label: J.strOr(j['label']),
    defaultOn: J.boolOr(j['default']),
  );
}

/// `GET /reports/exports/{type}/fields` — one record type's column catalog and
/// the filter controls the app should render for it.
class ReportFieldSet {
  const ReportFieldSet({
    required this.type,
    required this.label,
    this.count = 0,
    this.filters = const {},
    this.columns = const [],
  });

  final String type;
  final String label;
  final int count;

  /// `date_range` | `status` | `department` | `topic` | `agent` — see
  /// [ReportFilter].
  final Set<String> filters;

  /// Every exportable column, in catalog order. Exports follow the order the
  /// keys are sent in, so this order is what the picker preserves.
  final List<ReportColumn> columns;

  Set<String> get defaultColumnKeys => {
    for (final c in columns)
      if (c.defaultOn) c.key,
  };

  factory ReportFieldSet.fromJson(Map<String, dynamic> j) => ReportFieldSet(
    type: J.strOr(j['type']),
    label: J.strOr(j['label']),
    count: J.intOr(j['count']),
    filters: {for (final f in J.list(j['filters'])) '$f'},
    columns: J.mapList(j['columns']).map(ReportColumn.fromJson).toList(),
  );
}

/// A minted, signed download link — the response of
/// `POST /reports/exports/{type}/link`.
///
/// The URL is fully formed and carries its own HMAC credential; the download
/// route takes no bearer token. It stops working 300 seconds after minting, so
/// it is fetched immediately rather than stored.
class ReportLink {
  const ReportLink({
    required this.url,
    required this.filename,
    this.expiresAt,
  });

  final String url;

  /// The server's own name for the file — `tickets-20260624-090154.csv`.
  /// Reused verbatim so a mobile download matches what the web produced.
  final String filename;
  final DateTime? expiresAt;

  factory ReportLink.fromJson(Map<String, dynamic> j) => ReportLink(
    url: J.strOr(j['url']),
    filename: J.strOr(j['filename']),
    expiresAt: J.dateTime(j['expires_at']),
  );
}
