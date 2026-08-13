import 'package:characters/characters.dart';
import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Shared display formatting helpers.
class Fmt {
  Fmt._();

  static final _date = DateFormat('d MMM yyyy');
  static final _dateTime = DateFormat('d MMM yyyy, h:mm a');
  static final _time = DateFormat('h:mm a');
  static final _dayLabel = DateFormat('d MMMM yyyy');
  static final _dayTime = DateFormat('d MMM, h:mm a');
  static final _apiDate = DateFormat('yyyy-MM-dd');
  static final _apiDateTime = DateFormat('yyyy-MM-dd HH:mm:ss');
  static final _compact = NumberFormat.compact(locale: 'en_US');

  /// Compact count for stat tiles / badges: raw below 1,000, otherwise
  /// abbreviated (1.2K, 12K, 1M, 1.5M). Negative values keep their sign.
  static String count(int n) => n.abs() < 1000 ? '$n' : _compact.format(n);

  static String date(DateTime? d) => d == null ? '—' : _date.format(d);

  /// Day heading for a thread's date divider — `Today`, `Yesterday`, or
  /// `1 July 2026`. Render it uppercased; the words stay cased here so the
  /// string is reusable anywhere a heading isn't wanted.
  static String dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return _dayLabel.format(d);
  }

  /// Clock time with the day but no year — `10 Aug, 4:02 PM`. For entries
  /// that already sit under a date divider, which supplies the rest.
  static String dayTime(DateTime? d) => d == null ? '—' : _dayTime.format(d);
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
    // Roll over at 1000 rather than 1024. "1008.0 KB" is arithmetically
    // correct and completely unreadable — nobody thinks in four-digit
    // kilobytes, and the reader has to divide in their head to know it's
    // about a megabyte.
    while (size >= 1000 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    // A decimal only earns its place while there are few enough significant
    // digits for it to mean something: "1.0 MB" is useful, "720.3 KB" is not.
    final decimals = i == 0 || size >= 100 ? 0 : 1;
    return '${size.toStringAsFixed(decimals)} ${units[i]}';
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
        // A closing `</p>` is a *paragraph* break, so it is worth a blank
        // line. What separates the tags in the source cannot be relied on to
        // supply one: osTicket returns `<p>A</p> <p>B</p>` with a single
        // space between them, so keying off the source's own whitespace gave
        // paragraphs that ran together on consecutive lines.
        .replaceAll(
          RegExp(r'</(p|h[1-6]|blockquote)\s*>', caseSensitive: false),
          '\n\n',
        )
        // The rest are line breaks, not paragraph breaks. Editors emit `<div>`
        // per line and `<li>` per step just as readily, and those used to lose
        // their break entirely — stripped to nothing, so the next line was
        // pasted onto the end of the previous one.
        .replaceAll(
          RegExp(r'</(div|li|ul|ol|tr|table|pre)\s*>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '');
    final decoded = noTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#160;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&rarr;', '→');

    // Trim each line, not just the whole string.
    //
    // The editors these bodies come from pad line starts with `&nbsp;`, which
    // is still an entity while the tags are being stripped and only becomes a
    // space here — so a body that looked clean as HTML arrives with every line
    // after the first indented by one, and a canned response pasted into the
    // composer sits visibly crooked.
    final lines = decoded.split('\n').map((l) => l.trim());

    // At most one blank line in a row. `</p>` emits its own break above, and
    // a source that *also* puts a newline between the tags would otherwise
    // stack them into a widening gap.
    final out = <String>[];
    for (final l in lines) {
      if (l.isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
      out.add(l);
    }
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    return out.join('\n');
  }
}
