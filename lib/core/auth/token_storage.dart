import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the JWT access/refresh token pair (and a cached agent snapshot)
/// in the platform's encrypted secure storage.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kAgent = 'agent_snapshot';

  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _storage.write(key: _kAccess, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _kRefresh, value: refreshToken);
    }
  }

  Future<String?> readAccessToken() => _storage.read(key: _kAccess);
  Future<String?> readRefreshToken() => _storage.read(key: _kRefresh);

  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _kAccess, value: token);

  /// Cache a small agent snapshot from /auth/login so the UI can render
  /// instantly on cold start before /me resolves.
  Future<void> saveAgentSnapshot(Map<String, dynamic> agent) =>
      _storage.write(key: _kAgent, value: jsonEncode(agent));

  Future<Map<String, dynamic>?> readAgentSnapshot() async {
    final raw = await _storage.read(key: _kAgent);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasSession() async => (await readAccessToken()) != null;

  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kAgent);
  }
}
