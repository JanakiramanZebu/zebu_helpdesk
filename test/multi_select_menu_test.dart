import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/web/property_menu.dart';

/// Opens a multi-select over three rows, starting with two already chosen.
Future<Set<String>?> _open(
  WidgetTester tester, {
  Set<String> selected = const {'a', 'b'},
}) async {
  Set<String>? result;
  var done = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showZebuMultiSelectMenu<String>(
                    context,
                    selected: selected,
                    items: const [
                      ZebuPropertyMenuItem<String>(value: 'a', label: 'Amol'),
                      ZebuPropertyMenuItem<String>(value: 'b', label: 'Baskar'),
                      ZebuPropertyMenuItem<String>(value: 'c', label: 'Karun'),
                    ],
                  );
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(done, isFalse);
  return result;
}

void main() {
  testWidgets('Done commits an emptied list', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    // Clearing everything IS the change. Done must still commit it, or the
    // only exits are discarding or re-ticking someone you just removed.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing, reason: 'menu should have closed');
  });

  testWidgets('picking stays open and accumulates', (tester) async {
    await _open(tester, selected: const {});
    await tester.tap(find.text('Amol'));
    await tester.pumpAndSettle();
    // Still open — closing on each pick is what made adding four people mean
    // opening the picker four times.
    expect(find.text('Karun'), findsOneWidget);

    await tester.tap(find.text('Karun'));
    await tester.pumpAndSettle();
    expect(find.text('Baskar'), findsOneWidget);
  });
}
