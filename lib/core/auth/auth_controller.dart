import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../data/auth_repository.dart';
import 'token_storage.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.agent = const {},
  });

  final AuthStatus status;

  /// Cached agent snapshot ({ id, name, email, isadmin }) for instant UI.
  final Map<String, dynamic> agent;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isKnown => status != AuthStatus.unknown;

  AuthState copyWith({AuthStatus? status, Map<String, dynamic>? agent}) =>
      AuthState(status: status ?? this.status, agent: agent ?? this.agent);
}

/// Owns the session lifecycle and exposes a [Listenable]-friendly state used by
/// the router's redirect guard.
class AuthController extends Notifier<AuthState> {
  late final TokenStorage _tokens;
  late final AuthRepository _auth;

  @override
  AuthState build() {
    _tokens = ref.read(tokenStorageProvider);
    _auth = ref.read(authRepositoryProvider);
    // Kick off async bootstrap; state starts as `unknown` (splash).
    Future.microtask(_bootstrap);
    return const AuthState();
  }

  Future<void> _bootstrap() async {
    final hasSession = await _tokens.hasSession();
    final snapshot = await _tokens.readAgentSnapshot();
    state = AuthState(
      status: hasSession
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated,
      agent: snapshot ?? const {},
    );
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    final result =
        await _auth.login(username: username, password: password);
    state = AuthState(status: AuthStatus.authenticated, agent: result.agent);
  }

  Future<void> logout() async {
    await _auth.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// Called by the API client when a refresh is impossible.
  Future<void> onSessionExpired() async {
    await _tokens.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}
