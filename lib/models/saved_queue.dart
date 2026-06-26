import '../core/api/json.dart';

/// A saved queue / view. Personal API-authored queues are editable; public,
/// system, and web-SCP queues are read-only here.
///
/// [criteria] uses the **same parameter names `GET /tickets` accepts**, so it
/// can be fed straight back as the list query.
class SavedQueue {
  const SavedQueue({
    required this.id,
    required this.name,
    required this.fullName,
    required this.type, // ticket | task
    this.parentId = 0,
    this.public = false,
    this.personal = false,
    this.editable = false,
    this.criteria = const {},
    this.sort,
    this.columns,
  });

  final int id;
  final String name;
  final String fullName;
  final String type;
  final int parentId;
  final bool public;
  final bool personal;
  final bool editable;
  final Map<String, dynamic> criteria;
  final String? sort;
  final List<String>? columns;

  factory SavedQueue.fromJson(Map<String, dynamic> j) => SavedQueue(
        id: J.intOr(j['id']),
        name: J.strOr(j['name']),
        fullName: J.strOr(j['full_name'], J.strOr(j['name'])),
        type: J.strOr(j['type'], 'ticket'),
        parentId: J.intOr(j['parent_id']),
        public: J.boolOr(j['public']),
        personal: J.boolOr(j['personal']),
        editable: J.boolOr(j['editable']),
        criteria: j['criteria'] is Map ? J.map(j['criteria']) : const {},
        sort: J.str(j['sort']),
        columns: j['columns'] is List
            ? J.list(j['columns']).map((e) => e.toString()).toList()
            : null,
      );

  /// Flatten [criteria] into query params usable by `GET /tickets`/`/tasks`.
  Map<String, dynamic> toQuery() {
    final q = <String, dynamic>{};
    criteria.forEach((k, v) {
      if (v == null) return;
      if (k == 'cf' && v is Map) {
        v.forEach((cfId, cfVal) => q['cf[$cfId]'] = cfVal);
      } else if (v is List) {
        q[k] = v.join(',');
      } else {
        q[k] = v;
      }
    });
    if (sort != null) q['sort'] = sort;
    return q;
  }
}
