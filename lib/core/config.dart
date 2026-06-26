/// Global configuration for the Zebu Helpdesk app.
///
/// The osTicket `/api/v2` staff API lives under a single dispatcher script:
///   `{baseUrl}/scp/api.php/<path>`
/// e.g. `POST {baseUrl}/scp/api.php/auth/login`
class AppConfig {
  AppConfig._();

  /// osTicket helpdesk base URL (cfg->getBaseUrl()).
  static const String baseUrl = String.fromEnvironment(
    'ZEBU_BASE_URL',
    defaultValue: 'https://ticket.mynt.in',
  );

  /// Single dispatcher script that routes the whole v2 API by PATH_INFO.
  static const String apiRoot = '$baseUrl/scp/api.php';

  /// Default page size used by paginated list endpoints (server clamps 1..100).
  static const int defaultPageSize = 25;

  /// Connect/receive timeouts.
  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
