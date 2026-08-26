/// Shared form validators. Single source of truth so the same rule can never
/// drift between the screens that use it.
class Validators {
  Validators._();

  /// Standard practical email charset: letters/digits and `._%+-` before a
  /// single '@', letters/digits/dots/hyphens after, alphabetic TLD.
  static final _emailRe = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  /// Structural email rules the charset regex can't express: no consecutive
  /// dots, and no dot/hyphen hugging the '@' or the edges.
  static bool isEmail(String value) {
    if (!_emailRe.hasMatch(value)) return false;
    if (value.contains('..')) return false;
    final at = value.indexOf('@');
    final local = value.substring(0, at);
    final domain = value.substring(at + 1);
    if (local.startsWith('.') || local.endsWith('.')) return false;
    if (domain.startsWith('.') || domain.startsWith('-')) return false;
    return true;
  }

  /// Form validator for an email field. [label] names the field in the
  /// "required" message; pass [required] false to allow an empty value.
  static String? email(String? v, {String label = 'Email', bool required = true}) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return required ? '$label is required' : null;
    return isEmail(value) ? null : 'Enter a valid email address';
  }

  /// Form validator for a plain non-empty field.
  static String? notEmpty(String? v, {required String label}) =>
      (v ?? '').trim().isEmpty ? '$label is required' : null;

  /// The punctuation osTicket allows inside a phone number and strips before
  /// checking it: parentheses, hyphen, dot, plus and whitespace.
  static final _phonePunctuation = RegExp(r'[()\-.+\s]');

  static final _digitsOnly = RegExp(r'^[0-9]+$');

  /// Ports `Validator::is_phone()` (`include/class.validator.php:209`), which
  /// is the rule behind the web profile's "Valid phone number is required":
  /// strip the punctuation above, then require what's left to be numeric and
  /// **7 to 16 characters**. Deliberately not a real phone-number parser —
  /// osTicket's own comment says so — so it accepts international formats like
  /// `+91 98765 43210` as readily as `(555) 123-4567`.
  ///
  /// An empty value is *not* checked by the web (`if ($vars['mobile'] && ...)`),
  /// so use [phone] rather than this for an optional field.
  static bool isPhone(String value) {
    final stripped = value.replaceAll(_phonePunctuation, '');
    if (!_digitsOnly.hasMatch(stripped)) return false;
    return stripped.length >= 7 && stripped.length <= 16;
  }

  /// Form validator for osTicket's phone / mobile fields. Blank passes: both
  /// are optional on the web profile, which only validates a value that was
  /// actually typed. The message is the server's own, so a client-side
  /// rejection and a server-side one read identically.
  static String? phone(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return null;
    return isPhone(value) ? null : 'Valid phone number is required';
  }
}
