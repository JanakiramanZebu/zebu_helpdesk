/// Global configuration for the Zebu Helpdesk app.
///
/// The osTicket `/api/v2` staff API lives under a single dispatcher script:
///   `{baseUrl}/scp/api.php/<path>`
/// e.g. `POST {baseUrl}/scp/api.php/auth/login`
///
/// The base URL is **runtime-configurable** (see `ServerConfig`) so the app can
/// point at different backends without a rebuild. [defaultBaseUrl] is only the
/// seed value used the first time the app runs, before anything is saved.
class AppConfig {
  AppConfig._();

  /// Seed osTicket base URL, overridable at build time with
  /// `--dart-define=ZEBU_BASE_URL=...`. At runtime the saved value from
  /// `ServerConfig` takes precedence.
  static const String defaultBaseUrl = String.fromEnvironment(
    'ZEBU_BASE_URL',
    defaultValue: 'https://ticket.mynt.in',
  );

  /// The single dispatcher script that routes the whole v2 API by PATH_INFO,
  /// derived from any [baseUrl]. Trailing slashes are normalized away so we
  /// never emit `//scp/api.php`.
  static String apiRootFor(String baseUrl) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$trimmed/scp/api.php';
  }

  /// Dispatcher script for the seed base URL. Prefer `ServerConfig` at runtime.
  static String get apiRoot => apiRootFor(defaultBaseUrl);

  /// Default page size used by paginated list endpoints (server clamps 1..100).
  static const int defaultPageSize = 25;

  /// Connect/receive timeouts.
  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
