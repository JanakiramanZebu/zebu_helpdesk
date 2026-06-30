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
  });

  final int id;
  final String name;
  final String? state; // statuses: open | closed
  final String? color; // tags, task-priorities

  factory MetaItem.fromJson(Map<String, dynamic> j) => MetaItem(
    id: J.intOr(j['id']),
    name: J.strOr(j['name']),
    state: J.str(j['state']),
    color: J.str(j['color']),
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
}
