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

  /// Exactly what `Validator::is_phone()` strips — parentheses, hyphen, dot,
  /// plus and the **literal space**. Its character class is two space bytes,
  /// not `\s`: a tab or a non-breaking space survives the strip server-side
  /// and fails the numeric test, so this must not be more generous or the app
  /// would pass a number the server then rejects.
  static final _phonePunctuation = RegExp(r'[()\-.+ ]');

  static final _digitsOnly = RegExp(r'^[0-9]+$');

  /// Characters a *pasted* phone number tends to carry that no one typed on
  /// purpose: non-breaking and narrow-no-break spaces, other unicode spaces,
  /// tabs, and the zero-width/bidi marks that ride along with a copied number.
  /// Copying "+91 98765 43210" out of a web page or a chat app almost always
  /// yields U+00A0 rather than a plain space.
  static final _pastedWhitespace = RegExp(
    r'[\u00A0\u1680\u2000-\u200A\u202F\u205F\u3000\t]',
  );
  static final _zeroWidth = RegExp(r'[\u200B-\u200D\u2060\uFEFF\u200E\u200F]');

  /// Normalises a typed or pasted phone number to what osTicket can read:
  /// exotic spaces become plain spaces and invisible marks are dropped.
  ///
  /// The web has no such step — it simply rejects a pasted number — so this is
  /// the one place the app is deliberately kinder than the form it mirrors.
  /// It never reorders or reformats digits; the agent's number is stored as
  /// they wrote it.
  static String normalizePhone(String value) => value
      .replaceAll(_zeroWidth, '')
      .replaceAll(_pastedWhitespace, ' ')
      .trim();

  /// Ports `Validator::is_phone()` (`include/class.validator.php:209`), the
  /// rule behind the web profile's "Valid phone number is required": strip the
  /// punctuation above, then require what is left to be numeric and **7 to 16
  /// characters**. Deliberately not a real phone-number parser — osTicket's
  /// own comment says so — so it takes `+91 98765 43210` as readily as
  /// `(555) 123-4567`.
  ///
  /// Pass a [normalizePhone]d value; an empty one is *not* checked by the web
  /// (`if ($vars['mobile'] && ...)`), so use [phone] for an optional field.
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
    final value = normalizePhone(v ?? '');
    if (value.isEmpty) return null;
    return isPhone(value) ? null : 'Valid phone number is required';
  }
}
