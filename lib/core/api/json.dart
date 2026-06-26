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

  /// Parse the API's `"YYYY-MM-DD HH:MM:SS"` (and ISO) timestamps as local-ish.
  static DateTime? dateTime(dynamic v) {
    final s = str(v);
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s.contains('T') ? s : s.replaceFirst(' ', 'T'));
  }
}
