import '../core/api/json.dart';

/// One activity inside a notification group — a single event on a ticket/task
/// (`activities[]` of `GET /notifications`). Collaborator events are excluded
/// server-side.
///
/// The server groups the inbox by object now, so this model no longer stands on
/// its own in a list: [NotificationGroup] is the list row and this is a line
/// inside it. [id] is still the notification row id, which is what
/// `POST /notifications/{id}/read` and `DELETE /notifications/{id}` take — it is
/// **not** a navigation target; route on the group's `objectId`.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.event, // message|note|assigned|transfer|status|mention|overdue|new_unassigned
    required this.title,
    this.label, // non-null only for "assigned" events
    this.body,
    this.actor,
    this.created,
    this.read = false,
  });

  final int id;
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
    event: J.strOr(j['event']),
    title: J.strOr(j['title']),
    label: J.strNonBlank(j['label']),
    body: J.str(j['body']),
    actor: J.strNonBlank(j['actor']),
    created: J.dateTime(j['created']),
    read: J.boolOr(j['read']),
  );

  AppNotification copyWith({bool? read}) => AppNotification(
    id: id,
    event: event,
    title: title,
    label: label,
    body: body,
    actor: actor,
    created: created,
    read: read ?? this.read,
  );
}

/// One inbox card = every notification an agent has for a single ticket/task,
/// as the server now returns it (`GET /notifications` yields one entry per
/// object, `activities` nested newest-first).
///
/// The grouping used to be done here, over the flat feed, which meant a page of
/// 10 rows could cover only 3 tickets where the web's page covered 10 — seven
/// tickets simply never appeared. The server does the `GROUP BY type,
/// object_id` now, exactly as `include/staff/inbox.inc.php` does, so pagination
/// is counted in cards and objects that no longer exist are dropped before they
/// reach us.
class NotificationGroup {
  const NotificationGroup({
    required this.type,
    required this.objectId,
    this.number,
    this.subject,
    required this.unreadCount,
    required this.totalCount,
    this.lastActivity,
    required this.activities,
  });

  /// `ticket` | `task` — with [objectId], the tap target.
  final String type;
  final int objectId;

  /// The object's display number (`"009893"`); null when the server could not
  /// resolve one.
  final String? number;
  final String? subject;

  /// Unread / total activities on this object, counted server-side — the badge
  /// is not limited to what [activities] happens to carry.
  final int unreadCount;
  final int totalCount;

  final DateTime? lastActivity;

  /// Newest-first activities for this object.
  final List<AppNotification> activities;

  factory NotificationGroup.fromJson(Map<String, dynamic> j) {
    final activities = J
        .mapList(j['activities'])
        .map(AppNotification.fromJson)
        .toList(growable: false);
    return NotificationGroup(
      type: J.strOr(j['type'], 'ticket'),
      objectId: J.intOr(j['object_id']),
      number: J.strNonBlank(j['number']),
      subject: J.strNonBlank(j['subject']),
      unreadCount: J.intOr(j['unread_count']),
      totalCount: J.intOr(j['total_count'], activities.length),
      lastActivity: J.dateTime(j['last_activity']) ?? _latestOf(activities),
      activities: activities,
    );
  }

  static DateTime? _latestOf(List<AppNotification> acts) {
    DateTime? best;
    for (final a in acts) {
      final c = a.created;
      if (c != null && (best == null || c.isAfter(best))) best = c;
    }
    return best;
  }

  String get key => '$type:$objectId';
  bool get isTask => type == 'task';

  /// A group exists only because it has events, so this is non-null in
  /// practice; it stays nullable so a malformed payload can't crash the list.
  AppNotification? get latest => activities.isEmpty ? null : activities.first;

  bool get hasUnread => unreadCount > 0;

  /// How many activities the object has in total — which can exceed
  /// `activities.length`, since the payload windows the recent ones.
  int get count => totalCount;

  /// `#009893` when the server resolved a number, else the raw object id.
  String get displayRef => '#${number ?? objectId}';

  /// `number` and `subject` may both be null if the object was resolvable when
  /// the notification was written but not now; `activities.first.title` always
  /// carries a usable string.
  String get displaySubject {
    final s = subject?.trim();
    if (s != null && s.isNotEmpty) return s;
    for (final a in activities) {
      final t = a.title.trim();
      if (t.isNotEmpty) return t;
    }
    return '(no subject)';
  }
}

/// The inbox's totals (`GET /notifications/count`), now counted in **objects**
/// rather than notification rows — so the badge can no longer contradict the
/// list. [total] always equals an unfiltered `pagination.total` and [unread]
/// equals the `read=0` total.
class NotificationCounts {
  const NotificationCounts({
    required this.unread,
    required this.total,
    this.byType = const {},
  });

  /// Objects with at least one unread activity.
  final int unread;

  /// Objects in the inbox.
  final int total;

  /// Per-type breakdown keyed by `ticket` / `task`.
  final Map<String, ({int total, int unread})> byType;

  int unreadOf(String type) => byType[type]?.unread ?? 0;
  int totalOf(String type) => byType[type]?.total ?? 0;

  factory NotificationCounts.fromJson(Map<String, dynamic> data) {
    final by = <String, ({int total, int unread})>{};
    J.map(data['by_type']).forEach((k, v) {
      final m = J.map(v);
      by[k] = (total: J.intOr(m['total']), unread: J.intOr(m['unread']));
    });
    return NotificationCounts(
      unread: J.intOr(data['unread']),
      total: J.intOr(data['total']),
      byType: by,
    );
  }

  static const empty = NotificationCounts(unread: 0, total: 0);
}
