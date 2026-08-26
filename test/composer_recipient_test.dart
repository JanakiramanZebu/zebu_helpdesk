import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/message_composer.dart';

/// The two choices the ticket screen offers, mirroring the web reply form.
const _options = [
  ComposerRecipient(
    value: 'all',
    label: 'All recipients (3)',
    detail: 'Ticket owner + 2 collaborators',
  ),
  ComposerRecipient(
    value: 'user',
    label: 'Ticket owner',
    detail: 'sowmiya@example.com',
  ),
];

Future<void> pump(
  WidgetTester tester, {
  List<ComposerRecipient> recipients = _options,
  String? initial,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageComposer(
              recipients: recipients,
              initialRecipient: initial,
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
  testWidgets('the chip opens on the requested recipient', (tester) async {
    await pump(tester, initial: 'user');
    expect(find.text('To: Ticket owner'), findsOneWidget);
  });

  testWidgets('an unknown initial value falls back to the first option', (
    tester,
  ) async {
    await pump(tester, initial: 'cid:9');
    expect(find.text('To: All recipients (3)'), findsOneWidget);
  });

  testWidgets('picking from the sheet re-labels the chip', (tester) async {
    await pump(tester, initial: 'all');
    await tester.tap(find.text('To: All recipients (3)'));
    await tester.pumpAndSettle();

    // Both choices are offered, each with its recipient detail.
    expect(find.text('Reply to'), findsOneWidget);
    expect(find.text('sowmiya@example.com'), findsOneWidget);

    await tester.tap(find.text('Ticket owner'));
    await tester.pumpAndSettle();
    expect(find.text('To: Ticket owner'), findsOneWidget);
    expect(find.text('To: All recipients (3)'), findsNothing);
  });

  testWidgets('an internal note has no recipient row', (tester) async {
    await pump(tester, initial: 'user');
    await tester.tap(find.byType(InlineModeToggle));
    await tester.pumpAndSettle();
    expect(find.text('To: Ticket owner'), findsNothing);
  });

  testWidgets('tasks pass no options, so no chip is drawn', (tester) async {
    await pump(tester, recipients: const []);
    expect(find.textContaining('To: '), findsNothing);
  });
}
