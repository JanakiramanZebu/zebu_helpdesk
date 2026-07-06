// Barrel that re-exports the platform-specific `usePathStrategy()` entry.
//
// Mobile: no-op (no URL bar).
// Web:    calls `usePathUrlStrategy()` from flutter_web_plugins so go_router
//   produces clean URLs (`/tickets/42`) instead of hash URLs (`/#/tickets/42`).
//
// Call before `runApp`. Safe to call unconditionally.
export 'url_strategy_io.dart'
    if (dart.library.js_interop) 'url_strategy_web.dart';
