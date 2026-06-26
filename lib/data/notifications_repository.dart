import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/app_notification.dart';

/// Per-staff notifications (`/notifications`).
class NotificationsRepository {
  NotificationsRepository(this._api);
  final ApiClient _api;

  Future<Paginated<AppNotification>> list({int page = 1, int limit = 25}) async {
    final body =
        await _api.get('/notifications', query: {'page': page, 'limit': limit});
    return Paginated.fromEnvelope(J.map(body), AppNotification.fromJson);
  }

  Future<int> count() async {
    final body = await _api.get('/notifications/count');
    return J.intOr(J.map(J.map(body)['data'])['unread']);
  }

  Future<int> readAll() async {
    final body = await _api.post('/notifications/read-all');
    return J.intOr(J.map(J.map(body)['data'])['updated']);
  }

  Future<int> readObject(String type, int objectId) async {
    final body = await _api.post('/notifications/read-object',
        body: {'type': type, 'object_id': objectId});
    return J.intOr(J.map(J.map(body)['data'])['updated']);
  }

  Future<void> read(int id) => _api.post('/notifications/$id/read');

  Future<int> deleteAll() async {
    final body = await _api.delete('/notifications');
    return J.intOr(J.map(J.map(body)['data'])['deleted']);
  }

  Future<void> deleteOne(int id) => _api.delete('/notifications/$id');
}
