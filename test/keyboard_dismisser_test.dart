import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/keyboard_dismisser.dart';

Widget _app({required FocusNode node, VoidCallback? onButton}) => MaterialApp(
  home: KeyboardDismisser(
    child: Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(focusNode: node),
          ),
          ElevatedButton(
            onPressed: onButton ?? () {},
            child: const Text('Tap me'),
          ),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < 20; i++) ListTile(title: Text('Row $i')),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);

void main() {
  group('KeyboardDismisser', () {
    testWidgets('drops focus when a button handles the tap', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(_app(node: node));

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(node.hasFocus, isTrue);

      // A GestureDetector would lose this tap to the button and leave the
      // keyboard up — the whole reason this widget listens for the pointer.
      await tester.tap(find.text('Tap me'));
      await tester.pump();
      expect(node.hasFocus, isFalse);
    });

    testWidgets('drops focus when a list row handles the tap', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(_app(node: node));

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(node.hasFocus, isTrue);

      await tester.tap(find.text('Row 2'));
      await tester.pump();
      expect(node.hasFocus, isFalse);
    });

    testWidgets('moves focus to another field instead of closing the keyboard',
        (tester) async {
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardDismisser(
            child: Scaffold(
              body: Column(
                children: [
                  TextField(focusNode: first),
                  TextField(focusNode: second),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.tap(find.byType(TextField).last);
      await tester.pump();

      expect(first.hasFocus, isFalse);
      expect(second.hasFocus, isTrue);
    });

    testWidgets('keeps focus when the field itself is tapped', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(_app(node: node));

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(node.hasFocus, isTrue);
    });

    testWidgets('keeps focus for a tap just outside the field, where the '
        'inline clear button sits', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(_app(node: node));

      await tester.tap(find.byType(TextField));
      await tester.pump();

      final field = tester.getRect(find.byType(EditableText));
      await tester.tapAt(Offset(field.right + 12, field.center.dy));
      await tester.pump();

      expect(node.hasFocus, isTrue);
    });
  });

  group('KeyboardDismissObserver', () {
    testWidgets('drops focus when a page is pushed and popped', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final navKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: [KeyboardDismissObserver()],
          home: KeyboardDismisser(
            child: Scaffold(body: TextField(focusNode: node)),
          ),
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(node.hasFocus, isTrue);

      // Navigation the user didn't tap for — a notification tap or a redirect.
      unawaited(
        navKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Next page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(node.hasFocus, isFalse);
    });
  });
}
