import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/common.dart';
import '../models/organization.dart';
import '../models/ticket.dart';
import '../models/user.dart';

/// All `/organizations` endpoints.
class OrgsRepository {
  OrgsRepository(this._api);
  final ApiClient _api;

  Organization _org(dynamic body) =>
      Organization.fromJson(J.map(J.map(body)['data']));

  Future<Paginated<Organization>> list({
    String? q,
    int page = 1,
    int limit = 25,
  }) async {
    final body = await _api.get(
      '/organizations',
      query: {'q': q, 'page': page, 'limit': limit},
    );
    return Paginated.fromEnvelope(J.map(body), Organization.fromJson);
  }

  Future<Organization> get(int id) async =>
      _org(await _api.get('/organizations/$id'));

  Future<Organization> create(Map<String, dynamic> payload) async =>
      _org(await _api.post('/organizations', body: payload));

  Future<Organization> update(int id, Map<String, dynamic> changes) async =>
      _org(await _api.post('/organizations/$id', body: changes));

  Future<void> delete(int id) => _api.delete('/organizations/$id');

  Future<Paginated<AppUser>> users(
    int id, {
    int page = 1,
    int limit = 25,
  }) async {
    final body = await _api.get(
      '/organizations/$id/users',
      query: {'page': page, 'limit': limit},
    );
    return Paginated.fromEnvelope(J.map(body), AppUser.fromJson);
  }

  Future<void> addUser(int id, int userId) =>
      _api.post('/organizations/$id/users', body: {'user_id': userId});

  Future<void> removeUser(int id, int uid) =>
      _api.delete('/organizations/$id/users/$uid');

  Future<Paginated<Ticket>> tickets(
    int id, {
    int page = 1,
    int limit = 25,
  }) async {
    final body = await _api.get(
      '/organizations/$id/tickets',
      query: {'page': page, 'limit': limit},
    );
    return Paginated.fromEnvelope(J.map(body), Ticket.fromJson);
  }

  Future<List<StaffNote>> notes(int id) async {
    final body = await _api.get('/organizations/$id/notes');
    return J.mapList(J.map(body)['data']).map(StaffNote.fromJson).toList();
  }

  Future<StaffNote> addNote(int id, String note) async {
    final body = await _api.post(
      '/organizations/$id/notes',
      body: {'note': note},
    );
    return StaffNote.fromJson(J.map(J.map(body)['data']));
  }

  Future<void> deleteNote(int id, int noteId) =>
      _api.delete('/organizations/$id/notes/$noteId');
}
