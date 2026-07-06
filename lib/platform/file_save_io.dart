import 'dart:io';
import 'dart:typed_data';

import 'package:url_launcher/url_launcher.dart';

/// Writes [bytes] to a temp file named [filename] and asks the OS to open it
/// with the registered handler (PDF viewer, spreadsheet app, etc.).
///
/// [mime] is accepted for API symmetry with the web implementation but is
/// unused on mobile — the filename extension drives handler selection.
Future<void> saveAndReveal({
  required Uint8List bytes,
  required String filename,
  required String mime,
}) async {
  final file = File('${Directory.systemTemp.path}/$filename');
  await file.writeAsBytes(bytes);
  await launchUrl(Uri.file(file.path));
}
