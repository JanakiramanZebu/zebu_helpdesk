import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// The active helpdesk base URL, persisted so it survives restarts. Kept out of
/// [AppConfig] (which is compile-time const) so the server can be re-pointed
/// from the in-app Server Settings screen without a rebuild.
///
/// The value is loaded synchronously at startup (see `main`) and the initial
/// state is injected via a provider override, so the API client never has to
/// wait on async storage before its first request.
class ServerConfig extends Notifier<String> {
  /// Overridden in `main` with the value read from [SharedPreferences]. The
  /// fallback keeps the app functional if the override is ever forgotten.
  @override
  String build() => AppConfig.defaultBaseUrl;

  static const _kBaseUrl = 'server_base_url';

  /// The dispatcher script root for the current base URL.
  String get apiRoot => AppConfig.apiRootFor(state);

  /// Load the saved base URL (or the compile-time default). Call once in `main`
  /// and feed the result into [serverConfigProvider]'s override.
  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kBaseUrl);
    return (saved == null || saved.trim().isEmpty)
        ? AppConfig.defaultBaseUrl
        : saved.trim();
  }

  /// Persist and apply a new base URL. Invalidating the API client is the
  /// caller's job (so in-flight screens rebind to the new host).
  Future<void> save(String baseUrl) async {
    final normalized = baseUrl.trim();
    if (normalized.isEmpty || normalized == state) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, normalized);
    state = normalized;
  }

  /// Restore the compile-time default and clear the saved override.
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBaseUrl);
    state = AppConfig.defaultBaseUrl;
  }
}

/// The active base URL. Overridden in `main` with the persisted value so the
/// first build already reflects the saved server.
final serverConfigProvider = NotifierProvider<ServerConfig, String>(
  ServerConfig.new,
);
