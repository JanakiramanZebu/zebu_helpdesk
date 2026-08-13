import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/web/preview_picker.dart';

const _items = [
  ZebuPreviewItem<int>(
    value: 1,
    title: 'Account closure',
    body: 'As per your request, the Account closure link has been attached.',
  ),
  ZebuPreviewItem<int>(
    value: 2,
    title: 'Date wise P&L',
    body: 'Kindly follow the links and steps to download your P&L.',
  ),
];

Future<int?> _open(WidgetTester tester) async {
  int? picked;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showZebuPreviewPicker<int>(
                  context,
                  items: _items,
                  // footnote: 'Appends to your message',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  _noTooltipTest();
  testWidgets('opens previewing the first row, not a blank pane', (
    tester,
  ) async {
    await _open(tester);
    // Title appears twice: once in the list, once heading the preview.
    expect(find.text('Account closure'), findsNWidgets(2));
    expect(find.textContaining('Account closure link'), findsWidgets);
  });

  testWidgets('highlighting previews without choosing', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Date wise P&L').first);
    await tester.pumpAndSettle();

    // Preview swapped, menu still open — moving down a list is reading, not
    // deciding.
    expect(find.textContaining('download your P&L'), findsWidgets);
    expect(find.text('Insert'), findsOneWidget);
  });

  testWidgets('search matches bodies, not just titles', (tester) async {
    await _open(tester);
    // "steps" appears only in the second body — you often remember a phrase
    // without remembering what it was filed under.
    await tester.enterText(find.byType(TextField), 'steps');
    await tester.pumpAndSettle();
    expect(find.text('Date wise P&L'), findsWidgets);
    expect(find.text('Account closure'), findsNothing);
  });
}

/// The right pane is the preview; a tooltip would be a second copy of it.
void _noTooltipTest() {
  testWidgets('list rows carry no tooltip', (tester) async {
    await _open(tester);
    expect(find.byType(Tooltip), findsNothing);
  });
}
