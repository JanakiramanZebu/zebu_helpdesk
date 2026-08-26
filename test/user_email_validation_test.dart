import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/validators.dart';

void main() {
  group('Validators.email', () {
    test('accepts ordinary addresses', () {
      for (final v in [
        'a@b.co',
        'first.last+tag@sub.domain.com',
        'user_name%x@example.org',
      ]) {
        expect(Validators.email(v), isNull, reason: v);
      }
    });

    test('rejects malformed addresses', () {
      for (final v in [
        'plainstring',
        'no-at.example.com',
        'a@b',
        'a@b.',
        'a@.com',
        'a@-b.com',
        'a..b@c.com',
        '.a@b.com',
        'a.@b.com',
        'a b@c.com',
        '@b.com',
        'a@@b.com',
      ]) {
        expect(Validators.email(v), 'Enter a valid email address', reason: v);
      }
    });

    test('requires a value by default and trims', () {
      expect(Validators.email(''), 'Email is required');
      expect(Validators.email('   '), 'Email is required');
      expect(Validators.email(null), 'Email is required');
      expect(Validators.email('  a@b.co  '), isNull);
      expect(Validators.email('', required: false), isNull);
    });
  });

  testWidgets('form blocks submit until the email is valid', (tester) async {
    final key = GlobalKey<FormState>();
    final email = TextEditingController(text: 'not-an-email');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: key,
            child: TextFormField(
              controller: email,
              validator: Validators.email,
            ),
          ),
        ),
      ),
    );

    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);

    email.text = 'someone@example.com';
    expect(key.currentState!.validate(), isTrue);
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsNothing);
  });
}
