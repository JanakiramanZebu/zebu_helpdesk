import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/app_notification.dart';

/// Per-staff notifications (`/notifications`).
///
/// The endpoint returns one entry per ticket/task with its events nested, the
/// same object set and order as the staff web inbox — so `page`/`limit` and
/// every total below are counted in **cards**, not notification rows.
class NotificationsRepository {
  NotificationsRepository(this._api);
  final ApiClient _api;

  /// List the inbox. All three filters apply to *groups*: [read] narrows to
  /// objects with at least one unread activity (`false`) or fully-read ones
  /// (`true`), [type] to `ticket` / `task`, and [q] to a match in title / body /
  /// actor. `pagination.total` reflects them, so the caller can stop paging.
  Future<Paginated<NotificationGroup>> list({
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
    return Paginated.fromEnvelope(J.map(body), NotificationGroup.fromJson);
  }

  /// Totals for the badges. Object-based server-side, so `unread` matches the
  /// number of cards the Unread view lists and `total` matches an unfiltered
  /// `pagination.total` — no client-side scan of the feed to derive it.
  Future<NotificationCounts> counts() async {
    final data = J.map(J.map(await _api.get('/notifications/count'))['data']);
    return NotificationCounts.fromJson(data);
  }

  Future<int> readAll() async {
    final body = await _api.post('/notifications/read-all');
    return J.intOr(J.map(J.map(body)['data'])['updated']);
  }

  /// Mark every activity on one object read in one request — what a card tap
  /// wants, instead of one [read] call per unread activity.
  Future<int> readObject(String type, int objectId) async {
    final body = await _api.post(
      '/notifications/read-object',
      body: {'type': type, 'object_id': objectId},
    );
    return J.intOr(J.map(J.map(body)['data'])['updated']);
  }

  /// Mark a single activity read. Prefer [readObject] per card.
  Future<void> read(int id) => _api.post('/notifications/$id/read');

  Future<int> deleteAll() async {
    final body = await _api.delete('/notifications');
    return J.intOr(J.map(J.map(body)['data'])['deleted']);
  }

  Future<void> deleteOne(int id) => _api.delete('/notifications/$id');
}
