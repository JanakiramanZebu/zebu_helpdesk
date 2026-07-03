import '../core/api/api_client.dart';
import '../core/api/json.dart';

/// Agent self-service "forgot password" endpoints (`/auth/*`). Public — no
/// bearer token required (mirrors [AuthRepository]).
///
/// Two steps:
///   1. [requestReset] emails the agent a reset link containing a single-use
///      token. Always succeeds (same response whether or not the account
///      exists), so it can't be used to probe for valid agents.
///   2. [completeReset] sets a new password using that token.
class PasswordResetRepository {
  PasswordResetRepository(this._api);

  final ApiClient _api;

  /// Request a reset email for [login] (username OR email). Returns the neutral
  /// server message to show the user. Never reveals whether the account exists.
  Future<String> requestReset(String login) async {
    final body = await _api.post(
      '/auth/forgot-password',
      body: {'login': login},
      auth: false,
    );
    final data = J.map(J.map(body)['data']);
    return J.strOr(
      data['message'],
      'If an account matches, a password reset email has been sent.',
    );
  }

  /// Complete the reset: set [newPassword] using the [token] from the email.
  ///
  /// Throws an [ApiException] on failure — notably `invalid_token` (bad/expired
  /// link) or `validation` (weak password; the reason is in `fields.new_password`).
  Future<void> completeReset({
    required String token,
    required String newPassword,
  }) async {
    await _api.post(
      '/auth/reset-password',
      body: {'token': token, 'new_password': newPassword},
      auth: false,
    );
  }
}
