import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/app_sheet.dart';
import 'package:zebu_helpdesk/widgets/pickers.dart';

/// Builds `{ '1': 'Option 1', ... }` — the `{value: label}` shape a custom
/// list field's choices arrive in.
Map<String, String> choices(int n) => {
  for (var i = 1; i <= n; i++) '$i': 'Option $i',
};

Future<String?> openSheet(WidgetTester tester, Map<String, String> options) async {
  String? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await pickChoice(
                context,
                title: 'Products',
                choices: options,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('shows no search box for a short list', (tester) async {
    await openSheet(tester, choices(10));
    expect(find.byType(SheetSearchField), findsNothing,
        reason: '10 options is still scannable');
    expect(find.text('Option 1'), findsOneWidget);
  });

  testWidgets('shows a search box once the list passes 10', (tester) async {
    await openSheet(tester, choices(11));
    expect(find.byType(SheetSearchField), findsOneWidget);
  });

  testWidgets('search filters the options', (tester) async {
    await openSheet(tester, choices(30));
    // Type a fragment, not a whole label — `find.text` also matches the text
    // sitting in the search box itself.
    await tester.enterText(find.byType(TextField), '17');
    await tester.pumpAndSettle();

    expect(find.text('Option 17'), findsOneWidget);
    expect(find.text('Option 1'), findsNothing);
  });

  testWidgets('reports no matches rather than an empty sheet', (tester) async {
    await openSheet(tester, choices(30));
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('a long list scrolls instead of overflowing', (tester) async {
    await openSheet(tester, choices(60));
    // Nothing overflowed while laying out 60 rows...
    expect(tester.takeException(), isNull);

    final list = find.byType(ListView);
    expect(list, findsOneWidget);
    // ...and an option far down the list is reachable by scrolling.
    await tester.dragUntilVisible(
      find.text('Option 40'),
      list,
      const Offset(0, -300),
    );
    expect(find.text('Option 40'), findsOneWidget);
  });

  testWidgets('returns the selected key', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await pickChoice(
                  context,
                  title: 'Products',
                  choices: choices(12),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Option 3'));
    await tester.pumpAndSettle();

    expect(picked, '3', reason: 'the key, not the label');
  });
}
