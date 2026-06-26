import '../core/api/json.dart';

/// `GET /reports/summary`.
class ReportSummary {
  const ReportSummary({
    required this.totals,
    this.byPriority = const [],
    this.byDepartment = const [],
    this.byAgent = const [],
  });

  final ReportTotals totals;
  final List<PriorityBucket> byPriority;
  final List<DepartmentBucket> byDepartment;
  final List<AgentBucket> byAgent; // admins only; [] otherwise

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
        totals: ReportTotals.fromJson(J.map(j['totals'])),
        byPriority:
            J.mapList(j['by_priority']).map(PriorityBucket.fromJson).toList(),
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

class PriorityBucket {
  const PriorityBucket({required this.id, required this.priority, this.open = 0});
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
