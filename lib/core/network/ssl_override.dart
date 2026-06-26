import 'dart:io';

import '../config.dart';

/// Accepts the helpdesk server's TLS certificate even though it serves an
/// **incomplete chain** (the leaf's issuing intermediate isn't sent, so Android
/// can't build a trust path and aborts the handshake — desktop/Postman tolerate
/// it via AIA fetching, Android does not).
///
/// To limit the blast radius, the override only trusts certs for the configured
/// helpdesk host — every other host still goes through normal validation.
///
/// This is a stop-gap. The real fix is to install the correct intermediate
/// bundle on `ticket.mynt.in` so the chain validates without this.
class MyHttpOverrides extends HttpOverrides {
  MyHttpOverrides() : _allowedHost = Uri.parse(AppConfig.baseUrl).host;

  final String _allowedHost;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => host == _allowedHost;
    return client;
  }
}
