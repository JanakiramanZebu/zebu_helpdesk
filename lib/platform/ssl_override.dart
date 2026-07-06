// Barrel that re-exports the platform-specific `installSslOverride()` entry.
//
// Mobile (`dart:io`): trusts the helpdesk server's incomplete TLS chain so
// Android can connect — see ssl_override_io.dart for details.
// Web: browsers own TLS validation; the web implementation is a no-op.
//
// Call `installSslOverride()` from `main()` before `runApp`. Safe to call
// unconditionally — the web build resolves to the no-op variant.
export 'ssl_override_io.dart'
    if (dart.library.js_interop) 'ssl_override_web.dart';
