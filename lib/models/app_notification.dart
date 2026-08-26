import '../core/api/json.dart';

/// A per-staff notification (`GET /notifications`). Collaborator events are
/// excluded server-side.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type, // ticket | task
    required this.objectId,
    required this.event, // message|note|assigned|transfer|status|mention|overdue|new_unassigned
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

/// All of an agent's notifications for a single ticket/task, collapsed into one
/// inbox card — mirrors osTicket's `include/staff/inbox.inc.php`, which groups
/// `GROUP BY type, object_id` and orders by the latest activity so a new update
/// bumps the object to the top. [activities] are newest-first with consecutive
/// identical events (same event+actor+body) collapsed, exactly like the SCP
/// inbox's dedup.
class NotificationGroup {
  const NotificationGroup({
    required this.type,
    required this.objectId,
    required this.activities,
  });

  final String type; // ticket | task
  final int objectId;

  /// Newest-first, consecutive-duplicate-collapsed activities for this object.
  final List<AppNotification> activities;

  String get key => '$type:$objectId';
  AppNotification get latest => activities.first;
  bool get hasUnread => activities.any((a) => !a.read);
  int get unreadCount => activities.where((a) => !a.read).length;
  int get count => activities.length;
  DateTime? get lastActivity => latest.created;

  /// Collapse a flat, mixed notification list into per-object cards ordered by
  /// latest activity (newest first). Mirrors inbox.inc.php:
  ///   GROUP BY type, object_id ORDER BY MAX(created) DESC, object_id DESC
  static List<NotificationGroup> from(Iterable<AppNotification> items) {
    final byKey = <String, List<AppNotification>>{};
    for (final n in items) {
      (byKey['${n.type}:${n.objectId}'] ??= <AppNotification>[]).add(n);
    }
    final groups = <NotificationGroup>[];
    for (final acts in byKey.values) {
      acts.sort(_newestFirst);
      final deduped = _collapseConsecutive(acts);
      groups.add(NotificationGroup(
        type: deduped.first.type,
        objectId: deduped.first.objectId,
        activities: deduped,
      ));
    }
    groups.sort((a, b) {
      final at = a.lastActivity, bt = b.lastActivity;
      if (at != null && bt != null) {
        final c = bt.compareTo(at);
        if (c != 0) return c;
      } else if (at == null && bt != null) {
        return 1;
      } else if (at != null && bt == null) {
        return -1;
      }
      return b.objectId.compareTo(a.objectId); // stable tie-break
    });
    return groups;
  }

  /// Newest-first: by `created` desc, then `id` desc (mirrors the SCP window
  /// `ORDER BY created DESC, id DESC`).
  static int _newestFirst(AppNotification a, AppNotification b) {
    final at = a.created, bt = b.created;
    if (at != null && bt != null) {
      final c = bt.compareTo(at);
      if (c != 0) return c;
    } else if (at == null && bt != null) {
      return 1;
    } else if (at != null && bt == null) {
      return -1;
    }
    return b.id.compareTo(a.id);
  }

  /// Drop consecutive identical activities (same event+actor+body) keeping the
  /// newest of each run — the input must already be newest-first.
  static List<AppNotification> _collapseConsecutive(List<AppNotification> acts) {
    final out = <AppNotification>[];
    String? prev;
    for (final r in acts) {
      final k = '${r.event}|${r.actor ?? ''}|${r.body ?? ''}';
      if (k == prev) continue;
      out.add(r);
      prev = k;
    }
    return out;
  }
}

/// The inbox's unread totals (`GET /notifications/count`).
///
/// The server counts unread **rows**, but both the web inbox and this app list
/// one card per ticket/task (`GROUP BY type, object_id`), so a ticket with six
/// unread events is *one* unread conversation. [conversations] is the number
/// the badges show, so the bell, the More row and the Unread chip all agree
/// with the list — and with the web's `Unread (n)`.
class NotificationCounts {
  const NotificationCounts({required this.rows, required this.conversations});

  /// Unread notification rows (`data.unread`).
  final int rows;

  /// Unread ticket/task cards — what the inbox actually lists.
  final int conversations;

  static const empty = NotificationCounts(rows: 0, conversations: 0);
}
