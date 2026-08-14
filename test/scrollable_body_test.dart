import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/web/scrollable_body.dart';

Future<List<BoxShadow>> _shadow(
  WidgetTester tester,
  double contentHeight,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: ZebuScrollableBody(
            footer: const SizedBox(height: 40, child: Text('footer')),
            child: SizedBox(height: contentHeight),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final box = tester.widget<AnimatedContainer>(
    find.ancestor(
      of: find.text('footer'),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return ((box.decoration! as BoxDecoration).boxShadow)!;
}

void main() {
  testWidgets('content taller than the box shadows the footer', (tester) async {
    final shadow = await _shadow(tester, 900);
    expect(shadow.single.color.a, greaterThan(0));
  });

  testWidgets('content that fits casts nothing', (tester) async {
    // A shadow that is always on says nothing — it has to mean "there is more".
    final shadow = await _shadow(tester, 50);
    expect(shadow.single.color.a, 0);
  });

  testWidgets('scrolling to the end puts it away', (tester) async {
    await _shadow(tester, 900);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    final box = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: find.text('footer'),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final shadow = ((box.decoration! as BoxDecoration).boxShadow)!;
    expect(shadow.single.color.a, 0);
  });
}
