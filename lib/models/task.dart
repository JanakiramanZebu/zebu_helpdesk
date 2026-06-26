import '../core/api/json.dart';

/// A task. Like tickets, the summary (list) and full (detail/action) shapes
/// differ slightly; this absorbs both. Priority/parent/progress are an optional
/// install layer — fields may be null/0 where not present.
class Task {
  const Task({
    required this.id,
    required this.number,
    required this.title,
    required this.statusName,
    this.departmentName,
    this.departmentId,
    this.assignee,
    this.priority,
    this.parentId,
    this.progress = 0,
    this.subtaskCount = 0,
    this.blocked = false,
    this.duedate,
    this.overdue = false,
    this.created,
    this.updated,
    this.isOpen = true,
    this.customFields = const {},
  });

  final int id;
  final String number;
  final String title;
  final String statusName; // "Open" | "Completed"
  final String? departmentName;
  final int? departmentId;
  final String? assignee;
  final TaskPriority? priority;
  final int? parentId;
  final int progress; // 0..100
  final int subtaskCount;
  final bool blocked;
  final DateTime? duedate;
  final bool overdue;
  final DateTime? created;
  final DateTime? updated;
  final bool isOpen;

  /// `{ label: value }`.
  final Map<String, String> customFields;

  factory Task.fromJson(Map<String, dynamic> j) {
    String? deptName;
    int? deptId;
    final deptRaw = j['department'];
    if (deptRaw is Map) {
      deptName = J.str(deptRaw['name']);
      deptId = J.intOrNull(deptRaw['id']);
    } else {
      deptName = J.str(deptRaw);
    }

    final cf = <String, String>{};
    if (j['custom_fields'] is Map) {
      J.map(j['custom_fields']).forEach((k, v) => cf[k] = J.strOr(v));
    }

    return Task(
      id: J.intOr(j['id']),
      number: J.strOr(j['number']),
      title: J.strOr(j['title']),
      statusName: J.strOr(j['status'], 'Open'),
      departmentName: deptName,
      departmentId: deptId,
      assignee: J.str(j['assignee']),
      priority: j['priority'] is Map
          ? TaskPriority.fromJson(J.map(j['priority']))
          : null,
      parentId: J.intOrNull(j['parent_id']),
      progress: J.intOr(j['progress']),
      subtaskCount: J.intOr(j['subtask_count']),
      blocked: J.boolOr(j['blocked']),
      duedate: J.dateTime(j['duedate']),
      overdue: J.boolOr(j['overdue']),
      created: J.dateTime(j['created']),
      updated: J.dateTime(j['updated']),
      isOpen: j.containsKey('isopen')
          ? J.boolOr(j['isopen'], true)
          : J.strOr(j['status'], 'Open').toLowerCase() == 'open',
      customFields: cf,
    );
  }
}

class TaskPriority {
  const TaskPriority({required this.id, required this.name, this.color});
  final int id;
  final String name;
  final String? color;

  factory TaskPriority.fromJson(Map<String, dynamic> j) => TaskPriority(
        id: J.intOr(j['id']),
        name: J.strOr(j['name']),
        color: J.str(j['color']),
      );
}

/// A dependency edge (`GET /tasks/{id}/dependencies`).
class TaskDependency {
  const TaskDependency({
    required this.id,
    required this.required,
    this.blocker,
    this.created,
  });

  final int id;

  /// Must be closed before this task can close.
  final bool required;
  final DependencyBlocker? blocker;
  final DateTime? created;

  factory TaskDependency.fromJson(Map<String, dynamic> j) => TaskDependency(
        id: J.intOr(j['id']),
        required: J.boolOr(j['required']),
        blocker: j['blocker'] is Map
            ? DependencyBlocker.fromJson(J.map(j['blocker']))
            : null,
        created: J.dateTime(j['created']),
      );
}

class DependencyBlocker {
  const DependencyBlocker({
    required this.id,
    required this.number,
    required this.title,
    this.open = true,
  });
  final int id;
  final String number;
  final String title;
  final bool open;

  factory DependencyBlocker.fromJson(Map<String, dynamic> j) =>
      DependencyBlocker(
        id: J.intOr(j['id']),
        number: J.strOr(j['number']),
        title: J.strOr(j['title']),
        open: J.boolOr(j['open'], true),
      );
}
