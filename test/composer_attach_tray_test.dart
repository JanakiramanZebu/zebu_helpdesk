import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/message_composer.dart';

/// The "+" tray is inline rather than a modal sheet precisely so the composer
/// stays on screen while an attachment is chosen — a sheet used to cover the
/// field, the reply banner and Send. These tests pin that behaviour down.
Future<void> pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageComposer(
              onSend:
                  ({
                    required note,
                    required html,
                    required files,
                    recipient,
                  }) async => true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the + tray opens under the input, leaving the field on screen', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Camera'), findsNothing);

    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();

    // Every attach/insert action is reachable...
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('FAQ'), findsOneWidget);

    // ...and the composer itself is still there, above the tray — which is the
    // whole point of the inline layout.
    final field = tester.getRect(find.byType(ChatInputField));
    final tray = tester.getRect(find.text('Camera'));
    expect(find.byType(SendButton), findsOneWidget);
    expect(field.bottom, lessThanOrEqualTo(tray.top));
  });

  testWidgets('tapping + again closes the tray', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsNothing);
  });
}
