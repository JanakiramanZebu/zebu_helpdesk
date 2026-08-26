import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/app_notification.dart';

/// Per-staff notifications (`/notifications`).
class NotificationsRepository {
  NotificationsRepository(this._api);
  final ApiClient _api;

  /// List the inbox. [read] narrows to read (`true`) or unread (`false`) rows
  /// server-side, [type] to `ticket` / `task`, and [q] to a text match — all
  /// three are applied in the query, so `pagination.total` reflects them and
  /// the caller stops paging to fill a screen.
  Future<Paginated<AppNotification>> list({
    int page = 1,
    int limit = 25,
    String? type,
    bool? read,
    String? q,
  }) async {
    final body = await _api.get(
      '/notifications',
      query: {
        'page': page,
        'limit': limit,
        if (type != null) 'type': type,
        if (read != null) 'read': read ? 1 : 0,
        if (q != null && q.isNotEmpty) 'q': q,
      },
    );
    return Paginated.fromEnvelope(J.map(body), AppNotification.fromJson);
  }

  /// Unread totals for the badges. `data.unread` is a count of unread **rows**;
  /// the inbox lists one card per ticket/task, so the badge needs the number of
  /// unread *objects*. We take it from the payload when the server sends one
  /// (gap 16's per-view breakdown) and otherwise derive it by grouping the
  /// unread rows themselves — `read=0` narrows server-side, so that is a small,
  /// bounded read.
  Future<NotificationCounts> counts() async {
    final data = J.map(J.map(await _api.get('/notifications/count'))['data']);
    final rows = J.intOr(data['unread']);
    final objects = _objectCount(data);
    if (objects != null) {
      return NotificationCounts(rows: rows, conversations: objects);
    }
    if (rows == 0) return NotificationCounts.empty;
    return NotificationCounts(
      rows: rows,
      conversations: await _unreadConversations(),
    );
  }

  /// An object-level unread total from the count payload, under any of the
  /// names the breakdown may carry it as. Null when the server only sends the
  /// row count.
  static int? _objectCount(Map<String, dynamic> data) {
    const keys = [
      'unread_objects',
      'unread_conversations',
      'unread_cards',
      'unread_threads',
      'objects',
      'conversations',
    ];
    for (final k in keys) {
      final v = J.intOrNull(data[k]);
      if (v != null) return v;
    }
    return null;
  }

  /// Number of distinct ticket/task cards with unread activity, read straight
  /// off the unread feed. Capped at [_countScanPages] pages so a runaway inbox
  /// can never turn a badge fetch into a long scan; past that the badge
  /// under-reports rather than over-reports, which is the safer direction.
  static const _countScanPages = 3;

  Future<int> _unreadConversations() async {
    final seen = <String>{};
    for (var page = 1; page <= _countScanPages; page++) {
      final p = await list(page: page, limit: 100, read: false);
      for (final n in p.items) {
        seen.add('${n.type}:${n.objectId}');
      }
      if (p.items.isEmpty || !p.hasMore) break;
    }
    return seen.length;
  }

  Future<int> readAll() async {
    final body = await _api.post('/notifications/read-all');
    return J.intOr(J.map(J.map(body)['data'])['updated']);
  }

  Future<int> readObject(String type, int objectId) async {
    final body = await _api.post(
      '/notifications/read-object',
      body: {'type': type, 'object_id': objectId},
    );
    return J.intOr(J.map(J.map(body)['data'])['updated']);
  }

  Future<void> read(int id) => _api.post('/notifications/$id/read');

  Future<int> deleteAll() async {
    final body = await _api.delete('/notifications');
    return J.intOr(J.map(J.map(body)['data'])['deleted']);
  }

  Future<void> deleteOne(int id) => _api.delete('/notifications/$id');
}
