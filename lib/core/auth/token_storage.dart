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
  static const _kSavedUser = 'remembered_username';
  static const _kSavedPass = 'remembered_password';

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

  /// Store the credentials behind "Remember me". Kept in the same encrypted
  /// store as the tokens, and deliberately *outside* [clear] so signing out
  /// (or a session expiring) still leaves them available to sign back in.
  Future<void> saveCredentials({
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _kSavedUser, value: username);
    await _storage.write(key: _kSavedPass, value: password);
  }

  /// The remembered credentials, or null when nothing usable is stored.
  Future<({String username, String password})?> readCredentials() async {
    final username = await _storage.read(key: _kSavedUser);
    final password = await _storage.read(key: _kSavedPass);
    if (username == null || username.trim().isEmpty) return null;
    if (password == null || password.isEmpty) return null;
    return (username: username, password: password);
  }

  Future<void> clearCredentials() async {
    await _storage.delete(key: _kSavedUser);
    await _storage.delete(key: _kSavedPass);
  }

  Future<void> clear() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kAgent);
  }
}
