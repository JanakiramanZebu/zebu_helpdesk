import 'package:flutter/foundation.dart';

/// Latest published **native** version, as advertised by the shared Strapi CMS.
///
/// Reads the same entry Mynt Plus uses — `sess.mynt.in/strapi/appversion` — but
/// its own field (`Helpdeskversion`), so both apps are versioned from one CMS
/// without either overwriting the other. The house shape is:
///
/// ```json
/// { "data": { "attributes": { "Helpdeskversion": {
///     "and": "1.0.1", "ios": "1.0.1", "mandate": "no" } } } }
/// ```
///
/// This is about native builds only. Dart-only changes ship as Shorebird
/// patches and land silently — staff never see a prompt for those. The sheet
/// exists for what a patch can't cover, where a fresh APK must be installed.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.force = false,
  });

  /// Remote version name for the running platform, e.g. `1.0.1`.
  final String version;

  /// Where "Update now" sends the user.
  final String downloadUrl;

  /// From `mandate`: `"yes"` blocks the app until the update is installed.
  /// Anything else — including a missing or unreadable value — is optional.
  final bool force;

  /// Extracts [field] from a Strapi payload.
  ///
  /// Tolerates the envelope variations Strapi realistically produces so a CMS
  /// restructure can't silently kill the prompt: v4 `data.attributes`, v5's
  /// flattened `data`, a collection's list, or a bare object.
  ///
  /// Returns null when the field is absent, null, or carries no version string
  /// for this platform — all of which the caller treats as "no update" rather
  /// than an error. The field is `null` until someone fills it in, so this is
  /// the normal state, not a failure.
  static UpdateInfo? parse(
    Object? body, {
    required String field,
    required String fallbackUrl,
  }) {
    final attrs = _attributes(body);
    if (attrs == null) return null;

    final entry = attrs[field];
    if (entry is! Map) return null;
    final map = entry.cast<String, dynamic>();

    // iOS and Android ship independently, so each carries its own version.
    final version = _str(
      map,
      defaultTargetPlatform == TargetPlatform.iOS
          ? const ['ios', 'IOS']
          : const ['and', 'android'],
    );
    if (version == null) return null;

    final url = _str(map, const ['url', 'downloadUrl', 'apk']);

    return UpdateInfo(
      version: version,
      downloadUrl: (url == null || url.isEmpty) ? fallbackUrl : url,
      force: _isYes(_str(map, const ['mandate', 'force'])),
    );
  }

  /// Digs the attribute-bearing map out of whatever envelope Strapi used.
  static Map<String, dynamic>? _attributes(Object? body) {
    var node = body;

    if (node is Map && node['data'] != null) node = node['data'];
    if (node is List) {
      node = node.cast<Object?>().firstWhere(
        (e) => e is Map,
        orElse: () => null,
      );
    }
    if (node is! Map) return null;

    final map = node.cast<String, dynamic>();
    final attrs = map['attributes'];
    return attrs is Map ? attrs.cast<String, dynamic>() : map;
  }

  static String? _str(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  /// Only an explicit yes forces. A missing, misspelled or unexpected value
  /// must never lock staff out of the helpdesk.
  static bool _isYes(String? v) {
    final s = v?.trim().toLowerCase();
    return s == 'yes' || s == 'true' || s == '1';
  }

  /// True when [remote] is a later version than [current].
  ///
  /// Compares dot-separated segments numerically, left to right, padding the
  /// shorter side with zeros — so `1.1.0` correctly beats `1.0.84`, and `1.0.9`
  /// correctly loses to `1.0.84`.
  ///
  /// Deliberately *not* the `replaceAll('.', '')` trick used elsewhere in the
  /// codebase: that turns `1.1.0` into 110 and `1.0.84` into 1084, so the first
  /// minor bump silently stops prompting anyone.
  ///
  /// Non-numeric noise (`v1.0.1`, `1.0.1-beta`) is reduced to its leading
  /// digits; a segment with no digits counts as 0.
  static bool isNewer(String remote, String current) {
    final a = _segments(remote);
    final b = _segments(current);
    final len = a.length > b.length ? a.length : b.length;

    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _segments(String v) {
    return v.trim().split('.').map((part) {
      final digits = RegExp(r'^\D*(\d+)').firstMatch(part)?.group(1);
      return digits == null ? 0 : int.tryParse(digits) ?? 0;
    }).toList();
  }
}
