import 'package:flutter/services.dart';

/// Shared rules for the "email or username" identifier fields on the auth
/// screens (sign-in and forgot-password). Single source of truth so the two
/// fields can never drift apart.
///
/// The identifier is either an employee ID (letters+digits, shown uppercase)
/// or an email address (shown lowercase). Junk characters are swallowed at
/// typing time; structure is enforced by [validate] at submit time; the value
/// is sent to the API in canonical trimmed-lowercase form (identifiers are
/// case-insensitive server-side).
class AuthIdentifier {
  AuthIdentifier._();

  /// Characters that can occur in an employee ID or email. Used with
  /// [FilteringTextInputFormatter.allow] so anything else — spaces, symbols,
  /// emoji — cannot even be typed or pasted.
  static final allowedChars = RegExp(r'[A-Za-z0-9._%+@-]');

  /// Standard practical email charset: letters/digits and `._%+-` before a
  /// single '@', letters/digits/dots/hyphens after, alphabetic TLD.
  static final _emailRe = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  /// Usernames are employee IDs: letters and digits only. Accounts with other
  /// name styles can always sign in with their email instead.
  static final _usernameRe = RegExp(r'^[A-Za-z0-9]+$');

  /// Structural email rules the charset regex can't express: no consecutive
  /// dots, and no dot/hyphen hugging the '@' or the edges.
  static bool _validEmailShape(String value) {
    if (!_emailRe.hasMatch(value)) return false;
    if (value.contains('..')) return false;
    final at = value.indexOf('@');
    final local = value.substring(0, at);
    final domain = value.substring(at + 1);
    if (local.startsWith('.') || local.endsWith('.')) return false;
    if (domain.startsWith('.') || domain.startsWith('-')) return false;
    return true;
  }

  /// Form validator shared by both auth screens.
  static String? validate(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Email/Username is required';
    if (value.contains('@')) {
      if (!_validEmailShape(value)) return 'Enter a valid email address';
    } else if (!_usernameRe.hasMatch(value)) {
      return 'Username can contain only letters and numbers';
    }
    return null;
  }

  /// Canonical form submitted to the API (identifiers are case-insensitive).
  static String canonical(String raw) => raw.trim().toLowerCase();

  /// Display casing for a stored identifier (e.g. the remembered username):
  /// employee IDs uppercase, emails lowercase — matching the typing formatter.
  static String display(String raw) {
    final value = raw.trim();
    return value.contains('@') ? value.toLowerCase() : value.toUpperCase();
  }
}

/// Case-follows-content formatter for identifier fields: staff codes show
/// uppercase, but as soon as the text contains an '@' (an email) the whole
/// value flips to lowercase — and back, if the '@' is deleted. Purely visual;
/// the value is lowercased at submit time either way.
class UsernameCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    return TextEditingValue(
      text: text.contains('@') ? text.toLowerCase() : text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
