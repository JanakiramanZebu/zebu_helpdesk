import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'platform/ssl_override.dart';
import 'platform/url_strategy.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Web: drop the `#` from URLs. No-op on mobile.
  usePathStrategy();
  // Mobile: trust the helpdesk host's incomplete TLS chain (scoped to that
  // host only). No-op on web — browsers own TLS validation.
  installSslOverride();
  runApp(const ProviderScope(child: ZebuHelpdeskApp()));
}
