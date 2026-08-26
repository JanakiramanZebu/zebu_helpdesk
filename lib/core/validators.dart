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
}
