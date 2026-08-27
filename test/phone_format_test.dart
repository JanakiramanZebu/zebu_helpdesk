import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/format.dart';
import 'package:zebu_helpdesk/core/validators.dart';

/// osTicket pushes every stored number through its own US formatter, so the
/// API hands back `(98765) 43-210`-shaped strings for numbers that were saved
/// as plain Indian ones. [Fmt.phone] is the display-side undo.
void main() {
  group('Fmt.phone renders Indian form', () {
    const cases = <String, String>{
      '9876543210': '+91 98765 43210',
      '(987) 654-3210': '+91 98765 43210',
      '+91 9876543210': '+91 98765 43210',
      '919876543210': '+91 98765 43210',
      '09876543210': '+91 98765 43210',
      '+919876543210': '+91 98765 43210',
      '0919876543210': '+91 98765 43210',
      // 10-digit landline: the STD code length is unknowable, so the digits
      // stay unsplit rather than being grouped wrongly.
      '4412345678': '+91 4412345678',
    };

    cases.forEach((input, expected) {
      test('"$input" -> "$expected"', () {
        expect(Fmt.phone(input), expected);
      });
    });

    test('keeps an extension', () {
      expect(Fmt.phone('9876543210 x123'), '+91 98765 43210 ext. 123');
      expect(Fmt.phone('(987) 654-3210 ext. 45'), '+91 98765 43210 ext. 45');
    });
  });

  group('left alone', () {
    test('blank stays blank', () {
      expect(Fmt.phone(null), '');
      expect(Fmt.phone('   '), '');
    });

    test('anything not a 10-digit Indian number is returned as stored', () {
      expect(Fmt.phone('0441234'), '0441234');
      expect(Fmt.phone('+1 202 555 0143'), '+1 202 555 0143');
      expect(Fmt.phone('not a number'), 'not a number');
    });
  });

  test('what it renders is still what the server accepts', () {
    for (final raw in ['9876543210', '(987) 654-3210', '919876543210']) {
      expect(Validators.phone(Fmt.phone(raw)), isNull);
    }
  });
}
