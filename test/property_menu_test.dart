import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/web/check_mark.dart';
import 'package:zebu_helpdesk/widgets/web/property_menu.dart';
import 'package:zebu_helpdesk/widgets/web/property_rows.dart';

void main() {
  _widthTests();
  _tickTests();
  _alignmentTests();
  testWidgets('property row opens its menu', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ZebuPropertyGrid(
              rows: [
                ZebuPropertySpec(
                  label: 'Department',
                  value: null,
                  onTap: (anchor) async {
                    picked = await showZebuPropertyMenu<String>(
                      anchor,
                      items: const [
                        ZebuPropertyMenuItem<String>(
                          value: 'a',
                          label: 'Admin',
                        ),
                        ZebuPropertyMenuItem<String>(
                          value: 'b',
                          label: 'Back Office',
                          selected: true,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(find.text('Back Office'), findsOneWidget);

    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    expect(picked, 'a');
  });

  testWidgets('long lists get a search box that filters', (tester) async {
    const names = [
      'Admin',
      'ALGO PLATFORM',
      'Compliance',
      'Director',
      'DP',
      'Finance',
      'Vendor',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showZebuPropertyMenu<String>(
                  context,
                  items: [
                    const ZebuPropertyMenuItem<String>(
                      value: '',
                      label: 'None',
                      muted: true,
                    ),
                    for (final n in names)
                      ZebuPropertyMenuItem<String>(value: n, label: n),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'comp');
    await tester.pumpAndSettle();
    expect(find.text('Compliance'), findsOneWidget);
    expect(find.text('Director'), findsNothing);
    // Clearing the field stays reachable however you filter.
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('short lists get no search box', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showZebuPropertyMenu<String>(
                  context,
                  items: const [
                    ZebuPropertyMenuItem<String>(value: 'a', label: 'Sanjay M'),
                    ZebuPropertyMenuItem<String>(value: 'b', label: 'Divya P'),
                    ZebuPropertyMenuItem<String>(
                      value: 'c',
                      label: 'Karthik R',
                    ),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
  });
}

/// The value must sit hard against the row's right edge whatever its length —
/// a short value used to leave a growing gap there.
void _alignmentTests() {
  testWidgets('values right-align regardless of length', (tester) async {
    Future<double> rightEdgeOf(String value) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: ZebuPropertyGrid(
                rows: [
                  ZebuPropertySpec(
                    label: 'Assign to agent',
                    value: value,
                    onTap: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getBottomRight(find.text(value)).dx;
    }

    final short = await rightEdgeOf('DP');
    final long = await rightEdgeOf('Sowmlya Ramesh');
    expect((short - long).abs(), lessThan(1.0));
  });
}

/// The selected row must carry the check glyph, not just the tinted fill.
void _tickTests() {
  testWidgets('the selected row renders the check svg', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showZebuPropertyMenu<String>(
                  context,
                  items: const [
                    ZebuPropertyMenuItem<String>(
                      value: 'a',
                      label: 'Phone',
                      selected: true,
                    ),
                    ZebuPropertyMenuItem<String>(value: 'b', label: 'Email'),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Exactly one — the unselected row must not carry it.
    //
    // Drawn, not loaded: an asset renders as nothing when the running app's
    // bundle predates the file, which is silent and unfollowable. This
    // assertion holds regardless of what is in the bundle.
    expect(find.byType(ZebuCheckMark), findsOneWidget);
  });

  testWidgets('the search box clears from its own X', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => showZebuPropertyMenu<String>(
                  context,
                  items: [
                    for (final n in const [
                      'Admin',
                      'ALGO PLATFORM',
                      'Compliance',
                      'Director',
                      'DP',
                      'Finance',
                      'Vendor',
                    ])
                      ZebuPropertyMenuItem<String>(value: n, label: n),
                  ],
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Nothing typed yet, so no X to press.
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    await tester.enterText(find.byType(TextField), 'comp');
    await tester.pumpAndSettle();
    expect(find.text('Compliance'), findsOneWidget);
    expect(find.text('Director'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Field empty, full list back, and the menu still open.
    expect(find.text('Director'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.text('Search'), findsOneWidget);
  });

  _widthTests();
}

/// The menu's width against its trigger.
///
/// A property-grid value is short and sits at the right edge of its row, so
/// the menu keeps its own narrow width there. A full-width select is the
/// opposite case — a 190 px menu under a 400 px control looks like it belongs
/// to something else.
void _widthTests() {
  /// Opens a menu from a 400 px-wide trigger. The `Builder` sits *inside* the
  /// `SizedBox` on purpose: one level up and the anchor rect is the whole
  /// body, which is how the picker's tests first ended up off-screen.
  Future<void> open(WidgetTester tester, {required bool match}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showZebuPropertyMenu<String>(
                    context,
                    matchAnchorWidth: match,
                    items: const [
                      ZebuPropertyMenuItem<String>(value: 'a', label: 'Admin'),
                    ],
                  ),
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
  }

  testWidgets('matchAnchorWidth takes the trigger width', (tester) async {
    await open(tester, match: true);
    expect(tester.getSize(find.byType(Material).last).width, 400);
  });

  testWidgets('by default the menu keeps its own narrow width', (tester) async {
    await open(tester, match: false);
    expect(tester.getSize(find.byType(Material).last).width, 190);
  });

  testWidgets('a matched menu never overhangs its trigger', (tester) async {
    await open(tester, match: true);
    // Menus are right-aligned to the trigger, so a menu wider than its
    // trigger hangs off the left — which put the requester menu outside the
    // dialog that owned it. Matching the width lines both edges up.
    final menu = tester.getRect(find.byType(Material).last);
    final trigger = tester.getRect(find.byType(SizedBox).first);
    expect(menu.left, greaterThanOrEqualTo(trigger.left - 0.5));
    expect(menu.right, lessThanOrEqualTo(trigger.right + 0.5));
  });
}
