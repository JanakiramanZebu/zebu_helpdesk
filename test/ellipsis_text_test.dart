import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/web/ellipsis_text.dart';

Widget _host(String text, double width) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        child: ZebuEllipsisText(text, style: const TextStyle(fontSize: 13)),
      ),
    ),
  ),
);

void main() {
  testWidgets('a truncated line carries the whole string in a tooltip', (
    tester,
  ) async {
    const long = 'no-reply@tmes-in.trendmicro.com.invalid.example.co.in';
    await tester.pumpWidget(_host(long, 90));
    await tester.pumpAndSettle();

    final tip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tip.message, long);
  });

  testWidgets('a line that fits carries none', (tester) async {
    await tester.pumpWidget(_host('a@b.com', 400));
    await tester.pumpAndSettle();
    // A tooltip repeating what is on screen fires on every hover and teaches
    // the reader to ignore tooltips.
    expect(find.byType(Tooltip), findsNothing);
  });
}
