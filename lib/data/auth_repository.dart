import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/auth/token_storage.dart';

/// Result of a successful `/auth/login`.
class LoginResult {
  const LoginResult({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.agent,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final Map<String, dynamic> agent; // { id, name, email, isadmin }
}

/// Authentication endpoints (`/auth/*`). These are public — no bearer required.
class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStorage _tokens;

  /// Exchange credentials for an access+refresh pair and persist them.
  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    final body = await _api.post(
      '/auth/login',
      body: {'username': username, 'passwd': password},
      auth: false,
    );
    final data = J.map(J.map(body)['data']);
    final result = LoginResult(
      accessToken: J.strOr(data['access_token']),
      refreshToken: J.strOr(data['refresh_token']),
      expiresIn: J.intOr(data['expires_in'], 1800),
      agent: J.map(data['agent']),
    );
    await _tokens.saveTokens(
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
    );
    await _tokens.saveAgentSnapshot(result.agent);
    return result;
  }

  /// Clears the local session (the API has no logout endpoint).
  Future<void> logout() => _tokens.clear();
}
