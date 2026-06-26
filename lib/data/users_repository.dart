import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/common.dart';
import '../models/ticket.dart';
import '../models/user.dart';

/// All `/users` endpoints.
class UsersRepository {
  UsersRepository(this._api);
  final ApiClient _api;

  AppUser _user(dynamic body) => AppUser.fromJson(J.map(J.map(body)['data']));

  Future<Paginated<AppUser>> list({String? q, int page = 1, int limit = 25}) async {
    final body = await _api.get('/users', query: {'q': q, 'page': page, 'limit': limit});
    return Paginated.fromEnvelope(J.map(body), AppUser.fromJson);
  }

  Future<AppUser> get(int id) async => _user(await _api.get('/users/$id'));

  /// Create or de-dupe by email.
  Future<AppUser> create({
    required String name,
    required String email,
    String? phone,
  }) async =>
      _user(await _api.post('/users', body: {
        'name': name,
        'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      }));

  Future<AppUser> update(int id, Map<String, dynamic> changes) async =>
      _user(await _api.post('/users/$id', body: changes));

  Future<void> delete(int id) => _api.delete('/users/$id');

  Future<Paginated<Ticket>> tickets(int id, {int page = 1, int limit = 25}) async {
    final body =
        await _api.get('/users/$id/tickets', query: {'page': page, 'limit': limit});
    return Paginated.fromEnvelope(J.map(body), Ticket.fromJson);
  }

  // --- Notes ----------------------------------------------------------------

  Future<List<StaffNote>> notes(int id) async {
    final body = await _api.get('/users/$id/notes');
    return J.mapList(J.map(body)['data']).map(StaffNote.fromJson).toList();
  }

  Future<StaffNote> addNote(int id, String note) async {
    final body = await _api.post('/users/$id/notes', body: {'note': note});
    return StaffNote.fromJson(J.map(J.map(body)['data']));
  }

  Future<void> deleteNote(int id, int noteId) =>
      _api.delete('/users/$id/notes/$noteId');

  // --- Org / account --------------------------------------------------------

  Future<AppUser> setOrg(int id, int? orgId) async =>
      _user(await _api.post('/users/$id/org', body: {'org_id': orgId}));

  /// action: register | lock | unlock | reset-password.
  Future<Map<String, dynamic>> account(int id, String action) async {
    final body = await _api.post('/users/$id/account', body: {'action': action});
    return J.map(J.map(body)['data']);
  }
}
