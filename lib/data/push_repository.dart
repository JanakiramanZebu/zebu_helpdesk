import '../core/api/api_client.dart';
import '../core/api/json.dart';

/// FCM push device registry + admin config/test (`/push/*`).
class PushRepository {
  PushRepository(this._api);
  final ApiClient _api;

  Future<bool> registerDevice({
    required String token,
    String platform = 'android',
  }) async {
    final body = await _api.post('/push/devices',
        body: {'token': token, 'platform': platform});
    return J.boolOr(J.map(J.map(body)['data'])['registered']);
  }

  Future<bool> removeDevice(String token) async {
    final body = await _api.delete('/push/devices', body: {'token': token});
    return J.boolOr(J.map(J.map(body)['data'])['removed']);
  }

  // --- Admin ----------------------------------------------------------------

  Future<Map<String, dynamic>> saveConfig({
    required String projectId,
    required String serviceAccountPath,
  }) async {
    final body = await _api.post('/push/config', body: {
      'project_id': projectId,
      'service_account_path': serviceAccountPath,
    });
    return J.map(J.map(body)['data']);
  }

  Future<Map<String, dynamic>> test({String? token}) async {
    final body = await _api.post('/push/test',
        body: {if (token != null) 'token': token});
    return J.map(J.map(body)['data']);
  }
}
