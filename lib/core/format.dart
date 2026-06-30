import 'package:characters/characters.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Shared display formatting helpers.
class Fmt {
  Fmt._();

  static final _date = DateFormat('d MMM yyyy');
  static final _dateTime = DateFormat('d MMM yyyy, h:mm a');
  static final _time = DateFormat('h:mm a');
  static final _apiDate = DateFormat('yyyy-MM-dd');
  static final _apiDateTime = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final _compact = NumberFormat.compact(locale: 'en_US');

  /// Compact count for stat tiles / badges: raw below 1,000, otherwise
  /// abbreviated (1.2K, 12K, 1M, 1.5M). Negative values keep their sign.
  static String count(int n) => n.abs() < 1000 ? '$n' : _compact.format(n);

  static String date(DateTime? d) => d == null ? '—' : _date.format(d);
  static String dateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d);
  static String time(DateTime? d) => d == null ? '—' : _time.format(d);

  /// `YYYY-MM-DD HH:MM:SS` for sending datetimes back to the API
  /// (e.g. ticket due date / task due date).
  static String apiDateTime(DateTime d) => _apiDateTime.format(d);

  /// `YYYY-MM-DD` for date-only API params (e.g. `created_from`/`created_to`).
  static String apiDate(DateTime d) => _apiDate.format(d);

  /// "3 hours ago" style relative time.
  static String ago(DateTime? d) =>
      d == null ? '' : timeago.format(d, allowFromNow: true);

  /// Human file size.
  static String fileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
  }

  /// First/last initials from a display name.
  static String initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  /// Strip HTML tags / collapse entities to plain text (lightweight preview).
  static String stripHtml(String? html) {
    if (html == null || html.isEmpty) return '';
    final noTags = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    return noTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&rarr;', '→')
        .trim();
  }
}
