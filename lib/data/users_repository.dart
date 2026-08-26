import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/user.dart';

/// The `/users` endpoints the app still needs: the requester picker's search
/// and its inline "create a new requester" form.
class UsersRepository {
  UsersRepository(this._api);
  final ApiClient _api;

  AppUser _user(dynamic body) => AppUser.fromJson(J.map(J.map(body)['data']));

  Future<Paginated<AppUser>> list({
    String? q,
    int page = 1,
    int limit = 25,
  }) async {
    final body = await _api.get(
      '/users',
      query: {'q': q, 'page': page, 'limit': limit},
    );
    return Paginated.fromEnvelope(J.map(body), AppUser.fromJson);
  }

  /// Create or de-dupe by email.
  Future<AppUser> create({
    required String name,
    required String email,
    String? phone,
  }) async => _user(
    await _api.post(
      '/users',
      body: {
        'name': name,
        'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
    ),
  );
}
