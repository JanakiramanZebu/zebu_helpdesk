import 'package:flutter_web_plugins/url_strategy.dart';

/// Switches the browser to clean path URLs (no `#`).
///
/// With this, go_router produces `/tickets/42`; without it, `/#/tickets/42`.
/// Requires the web server (or `flutter run -d chrome`) to serve `index.html`
/// for unknown paths — Flutter's dev server already does this.
void usePathStrategy() => usePathUrlStrategy();
