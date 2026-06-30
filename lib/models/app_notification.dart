import '../core/api/json.dart';

/// A per-staff notification (`GET /notifications`). Collaborator events are
/// excluded server-side.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type, // ticket | task
    required this.objectId,
    required this.event, // assigned | message | note | transferred | overdue
    required this.title,
    this.label, // non-null only for "assigned" events
    this.body,
    this.actor,
    this.created,
    this.read = false,
  });

  final int id;
  final String type;
  final int objectId;
  final String event;
  final String title;
  final String? label;
  final String? body;
  final String? actor;
  final DateTime? created;
  final bool read;

  /// Client falls back to [title] when [label] is null.
  String get displayLabel => label ?? title;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
    id: J.intOr(j['id']),
    type: J.strOr(j['type'], 'ticket'),
    objectId: J.intOr(j['object_id']),
    event: J.strOr(j['event']),
    title: J.strOr(j['title']),
    label: J.str(j['label']),
    body: J.str(j['body']),
    actor: J.str(j['actor']),
    created: J.dateTime(j['created']),
    read: J.boolOr(j['read']),
  );

  AppNotification copyWith({bool? read}) => AppNotification(
    id: id,
    type: type,
    objectId: objectId,
    event: event,
    title: title,
    label: label,
    body: body,
    actor: actor,
    created: created,
    read: read ?? this.read,
  );
}
