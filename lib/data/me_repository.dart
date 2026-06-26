import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../models/me.dart';

/// `/me/*`, `/ping`, and `/agents/{id}`.
class MeRepository {
  MeRepository(this._api);
  final ApiClient _api;

  Future<int> ping() async {
    final body = await _api.get('/ping');
    return J.intOr(J.map(J.map(body)['data'])['staff']);
  }

  Future<Me> getMe() async {
    final body = await _api.get('/me');
    return Me.fromJson(J.map(J.map(body)['data']));
  }

  /// Update own profile/preferences; returns the refreshed [Me].
  Future<Me> updateMe(Map<String, dynamic> changes) async {
    final body = await _api.post('/me', body: changes);
    return Me.fromJson(J.map(J.map(body)['data']));
  }

  /// Toggle availability. Supply exactly one of [available]/[onVacation].
  Future<({bool available, bool onVacation})> setAvailability({
    bool? available,
    bool? onVacation,
  }) async {
    final body = await _api.post('/me/availability', body: {
      if (available != null) 'available': available,
      if (onVacation != null) 'onvacation': onVacation,
    });
    final data = J.map(J.map(body)['data']);
    return (
      available: J.boolOr(data['available']),
      onVacation: J.boolOr(data['onvacation']),
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _api.post('/me/password', body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      });

  /// Re-roll the local avatar; returns the new avatar URL.
  Future<String?> rerollAvatar() async {
    final body = await _api.post('/me/avatar');
    final avatar = J.map(J.map(J.map(body)['data'])['avatar']);
    return J.str(avatar['url']);
  }

  Future<AgentProfile> getAgent(int id) async {
    final body = await _api.get('/agents/$id');
    return AgentProfile.fromJson(J.map(J.map(body)['data']));
  }
}
