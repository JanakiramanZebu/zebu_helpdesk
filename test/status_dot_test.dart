import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/res/zebu_status_style.dart';
import 'package:zebu_helpdesk/res/zebu_theme.dart';

void main() {
  testWidgets('every priority dot is visible on a white menu', (tester) async {
    late ZebuTheme t;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            t = ZebuTheme.of(c);
            return const SizedBox();
          },
        ),
      ),
    );

    // The solid badges put white text on a coloured field, so `ink` is white
    // and a dot taken from it vanished. `dot` must never be near-white.
    for (final p in ['Low', 'Normal', 'High', 'Emergency']) {
      final dot = zebuPriorityStyle(p, t).dot;
      expect(
        dot.computeLuminance(),
        lessThan(0.7),
        reason: '$p dot is too light to see',
      );
    }
    for (final s in ['Open', 'Closed', 'Resolved', 'Escalated', 'Overdue']) {
      final dot = zebuStatusStyle(s, t).dot;
      expect(
        dot.computeLuminance(),
        lessThan(0.7),
        reason: '$s dot is too light to see',
      );
    }
  });
}
