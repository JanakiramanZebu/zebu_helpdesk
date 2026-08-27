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

  /// Trailing extension osTicket appends to a phone number ("x123").
  static final _phoneExt = RegExp(r'\s*(?:x|ext\.?)\s*(\d+)$', caseSensitive: false);
  static final _nonDigits = RegExp(r'[^0-9]');

  /// Indian display form for a stored phone / mobile number.
  ///
  /// osTicket runs every number through its own US formatter, so the API hands
  /// back `(555) 123-4567` for what the agent saved as `9876543210`. Display
  /// therefore works off the **digits**, never the punctuation they arrived
  /// with: a 10-digit subscriber number renders `+91 98765 43210`, and a
  /// national/international prefix (`0`, `91`, `+91`) is folded into it first.
  ///
  /// Anything that isn't a recognisable Indian number — a 7-digit local
  /// landline, a genuinely foreign number — is returned untouched rather than
  /// forced into a shape it doesn't have. Nothing here changes what is stored;
  /// [Validators.normalizePhone] still governs what is sent to the server.
  static String phone(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return '';
    var rest = value;
    var ext = '';
    final match = _phoneExt.firstMatch(rest);
    if (match != null) {
      ext = ' ext. ${match.group(1)}';
      rest = rest.substring(0, match.start);
    }
    var digits = rest.replaceAll(_nonDigits, '');
    // Peel the country / trunk prefix down to the 10-digit subscriber number.
    if (digits.length == 13 && digits.startsWith('091')) {
      digits = digits.substring(3);
    } else if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length != 10) return value;
    // Mobile numbers start 6-9 and read as 5+5; a 10-digit landline (STD code
    // of unknown length) would only be mis-grouped, so it stays unsplit.
    final grouped = RegExp(r'^[6-9]').hasMatch(digits)
        ? '${digits.substring(0, 5)} ${digits.substring(5)}'
        : digits;
    return '+91 $grouped$ext';
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
