import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Triggers a browser download of [bytes] as a file named [filename].
///
/// Pipeline: bytes → `Blob` → `URL.createObjectURL` → synthetic anchor click
/// → `URL.revokeObjectURL`. Works in every modern browser; no `data:` URL
/// size limits, no popups, no extension needed.
Future<void> saveAndReveal({
  required Uint8List bytes,
  required String filename,
  required String mime,
}) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
