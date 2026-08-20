/// Defensive JSON readers — the API mixes ints/strings/nulls in places
/// (e.g. phone numbers normalized to strings, ids sometimes string-keyed).
class J {
  J._();

  static Map<String, dynamic> map(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  static List<dynamic> list(dynamic v) => v is List ? v : const [];

  static List<Map<String, dynamic>> mapList(dynamic v) =>
      list(v).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();

  static String? str(dynamic v) => v?.toString();

  /// Like [str], but treats a blank value (`""` / whitespace) as absent.
  /// The API returns an empty string rather than `null` for some cleared
  /// fields, which silently defeats a `??` fallback chain and leaves the UI
  /// rendering nothing where it meant to render a placeholder.
  static String? strNonBlank(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  static String strOr(dynamic v, [String fallback = '']) =>
      v == null ? fallback : v.toString();

  static int? intOrNull(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static int intOr(dynamic v, [int fallback = 0]) => intOrNull(v) ?? fallback;

  static double? doubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static bool boolOr(dynamic v, [bool fallback = false]) {
    if (v == null) return fallback;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase();
    return s == '1' || s == 'true' || s == 'yes' || s == 'on';
  }

  /// Parse the API's timestamps and return them in **device-local** time.
  ///
  /// The backend emits GMT/UTC values as `"YYYY-MM-DD HH:MM:SS"` with no
  /// timezone marker. `DateTime.tryParse` treats a marker-less string as local,
  /// which skewed every displayed time by the device's UTC offset (e.g. +5:30 in
  /// IST — a "just now" message read as "6 hours ago"). So when a value carries
  /// a time but no explicit zone, parse it as UTC, then convert to local. Values
  /// that already carry a zone (`Z` or `±HH:MM`) are honored as-is; bare dates
  /// have no time-of-day to skew.
  static final _zoneSuffix = RegExp(r'[+-]\d{2}:?\d{2}$');
  static DateTime? dateTime(dynamic v) {
    final s = str(v);
    if (s == null || s.isEmpty) return null;
    final iso = s.contains('T') ? s : s.replaceFirst(' ', 'T');
    final hasTime = iso.contains(':');
    final hasZone = iso.endsWith('Z') || _zoneSuffix.hasMatch(iso);
    final normalized = (hasTime && !hasZone) ? '${iso}Z' : iso;
    return DateTime.tryParse(normalized)?.toLocal();
  }
}
