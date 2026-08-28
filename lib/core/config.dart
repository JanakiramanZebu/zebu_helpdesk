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

  /// Hard end-to-end deadline for a single JSON API call.
  ///
  /// Dio's own timeouts leave a gap: [connectTimeout] only covers opening the
  /// socket, and [receiveTimeout] measures the pause *between* two response
  /// chunks. A server that accepts the connection and then spends minutes
  /// building the response trips neither, which left a ticket whose thread the
  /// backend renders slowly (a bounce/NDR email, typically) spinning forever.
  /// Every call is capped by this.
  static const Duration requestDeadline = Duration(seconds: 45);

  /// Deadline for calls that move real bytes (attachment upload / file
  /// download). Those legitimately run long on a mobile link, so they get a
  /// looser cap than the JSON calls - but they are still bounded.
  static const Duration transferDeadline = Duration(minutes: 5);

  /// Shared Strapi entry carrying the published version of both Zebu apps.
  /// Mynt Plus reads its `version` field; the helpdesk reads [updateField].
  /// Public — no token required.
  static const String updateUrl = String.fromEnvironment(
    'ZEBU_UPDATE_URL',
    defaultValue: 'https://sess.mynt.in/strapi/appversion?fields=Helpdeskversion',
  );

  /// The attribute this app reads, so the two apps never overwrite each
  /// other's version. Shape: `{"and": "1.0.1", "ios": "1.0.1", "mandate": "no"}`.
  ///
  /// While the field is null (nobody has filled it in yet) the check simply
  /// finds no version and never prompts.
  static const String updateField = String.fromEnvironment(
    'ZEBU_UPDATE_FIELD',
    defaultValue: 'Helpdeskversion',
  );

  /// Optional bearer token, if the collection is ever made non-public.
  static const String updateToken = String.fromEnvironment(
    'ZEBU_UPDATE_TOKEN',
    defaultValue: '',
  );

  /// Where "Update now" sends staff to fetch a fresh APK — our own server.
  /// The CMS entry can override this per release with a `url` key.
  static const String downloadPageUrl = String.fromEnvironment(
    'ZEBU_DOWNLOAD_URL',
    defaultValue: '',
  );

  /// The update check is a background nicety, not a blocking call — keep it
  /// short so a slow CMS never delays the first screen.
  static const Duration updateTimeout = Duration(seconds: 8);
}
