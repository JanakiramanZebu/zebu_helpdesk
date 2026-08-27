import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/validators.dart';

/// Parity table for `Validator::is_phone()` (`include/class.validator.php:209`):
///
/// ```php
/// $stripped = preg_replace("(\(|\)|\-|\.|\+|[  ]+)", "", $phone);
/// return (!is_numeric($stripped)
///         || strlen($stripped) < 7 || strlen($stripped) > 16) ? false : true;
/// ```
///
/// The character class is two **literal space** bytes — not `\s` — so a tab or
/// a non-breaking space survives the strip and fails `is_numeric`. That detail
/// is why pasted numbers were being rejected server-side, and why the client
/// normalises before it checks.
void main() {
  group('is_phone parity', () {
    const valid = <String, String>{
      '9876543210': 'a plain 10-digit Indian mobile',
      '+91 98765 43210': 'international, spaces and a plus',
      '+919876543210': 'international, no spaces',
      '(555) 123-4567': 'the US format osTicket formats into',
      '044-1234567': 'an Indian landline with STD code',
      '0441234': 'exactly 7 digits — the lower bound',
      '1234567890123456': 'exactly 16 digits — the upper bound',
      '+91 (98765) 43210': 'every punctuation the strip removes',
    };

    valid.forEach((input, why) {
      test('accepts "$input" — $why', () {
        expect(Validators.phone(input), isNull);
      });
    });

    const invalid = <String, String>{
      '123456': 'only 6 digits — under the minimum',
      '12345678901234567': '17 digits — over the maximum',
      '98765 call me': 'letters are not stripped, so not numeric',
      '9876-54321/0': 'a slash is not in the strip set',
      '++++++++': 'punctuation only, nothing numeric left',
      'abcdefgh': 'no digits at all',
    };

    invalid.forEach((input, why) {
      test('rejects "$input" — $why', () {
        expect(Validators.phone(input), 'Valid phone number is required');
      });
    });

    test('blank passes — the web only checks a value that was typed', () {
      expect(Validators.phone(''), isNull);
      expect(Validators.phone('   '), isNull);
      expect(Validators.phone(null), isNull);
    });
  });

  group('pasted numbers', () {
    // Copying a number out of a web page or a chat app yields U+00A0, not a
    // plain space. osTicket's strip leaves it in place, is_numeric fails, and
    // the agent is told their perfectly good number is invalid.
    const nbsp = ' ';
    const narrowNbsp = ' ';
    const zeroWidth = '​';

    test('a number pasted with non-breaking spaces is accepted', () {
      expect(Validators.phone('+91${nbsp}98765${nbsp}43210'), isNull);
    });

    test('narrow no-break spaces and zero-width marks are handled too', () {
      expect(
        Validators.phone('+91$narrowNbsp$zeroWidth 98765 43210'),
        isNull,
      );
    });

    test('normalising leaves the digits and their order untouched', () {
      expect(
        Validators.normalizePhone('+91${nbsp}98765${nbsp}43210'),
        '+91 98765 43210',
      );
    });

    test('a tab becomes a space rather than failing server-side', () {
      expect(Validators.normalizePhone('044\t1234567'), '044 1234567');
      expect(Validators.phone('044\t1234567'), isNull);
    });

    // The stripping rule itself stays exactly as strict as the server's, so
    // the app never green-lights something the server will refuse.
    test('isPhone itself does not strip a raw non-breaking space', () {
      expect(Validators.isPhone('+91${nbsp}98765${nbsp}43210'), isFalse);
    });
  });
}
