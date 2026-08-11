// Barrel that re-exports the platform-specific `saveAndReveal()` entry.
//
// Mobile: writes the bytes to a temp file and hands the path to the OS via
//   `launchUrl` so the system "Open with…" handler appears.
// Web:    creates a Blob, an object URL, and a synthetic anchor click to
//   trigger a browser download.
export 'file_save_io.dart' if (dart.library.js_interop) 'file_save_web.dart';
