import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/theme/app_theme.dart';
import 'package:zebu_helpdesk/features/dashboard/widgets/attention_row.dart';
import 'package:zebu_helpdesk/models/ticket.dart';

/// DB-004 / TC_41: each Needs-attention row carries a right-aligned tag reading
/// "Overdue" for an overdue ticket, otherwise the ticket's age.
///
/// The catch is that the list serializer publishes neither `isoverdue` nor
/// `due`, so a ticket parsed from a list row always reports isOverdue == false.
/// The dashboard queries view: 'overdue', so it passes the flag explicitly.
Ticket _fromListRow({Object? priority = _absent}) => Ticket.fromJson({
  if (priority != _absent) 'priority': priority,
  'id': 7,
  'number': '807431',
  'subject': 'Cannot log in',
  'status': 'Open',
  'requester': 'Sowmiya Ramesh',
  'created': '2026-08-01 10:00:00',
  // note: no 'isoverdue' and no 'due' — exactly what /tickets returns
});

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(home: Scaffold(body: child)),
);

const _absent = Object();

void main() {
  testWidgets('a list-row ticket reports isOverdue false', (tester) async {
    expect(_fromListRow().isOverdue, isFalse);
  });

  testWidgets('without the override the row falls back to the age', (
    tester,
  ) async {
    await _pump(
      tester,
      AttentionRow(ticket: _fromListRow(), onTap: () {}),
    );
    expect(find.text('Overdue'), findsNothing);
  });

  testWidgets('the dashboard override renders the Overdue tag', (tester) async {
    await _pump(
      tester,
      AttentionRow(ticket: _fromListRow(), overdue: true, onTap: () {}),
    );
    expect(find.text('Overdue'), findsOneWidget);
  });

  testWidgets('the row still shows number, requester and subject', (
    tester,
  ) async {
    await _pump(
      tester,
      AttentionRow(ticket: _fromListRow(), overdue: true, onTap: () {}),
    );
    expect(find.text('#807431'), findsOneWidget);
    expect(find.text('Sowmiya Ramesh'), findsOneWidget);
    expect(find.text('Cannot log in'), findsOneWidget);
  });

  // TC_42 / DB-004: the rail must actually indicate the priority.
  group('priority rail', () {
    testWidgets('is coloured per priority and labelled for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      for (final p in ['High', 'Emergency', 'Low', 'Normal']) {
        await _pump(
          tester,
          AttentionRow(
            ticket: _fromListRow(priority: p),
            overdue: true,
            onTap: () {},
          ),
        );
        expect(
          find.bySemanticsLabel('Priority $p'),
          findsOneWidget,
          reason: '$p should label its rail',
        );
      }
      handle.dispose();
    });

    testWidgets('says so when the ticket carries no priority', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        AttentionRow(
          ticket: _fromListRow(priority: ''),
          overdue: true,
          onTap: () {},
        ),
      );
      expect(find.bySemanticsLabel('No priority set'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an unset priority still paints a visible rail', (
      tester,
    ) async {
      // Regression guard: the rail used to fall back to outlineVariant, a
      // hairline tone that reads as a rendering fault on a 3px bar.
      final scheme = AppTheme.light().colorScheme;
      expect(
        AppTheme.priorityAccent(null, scheme),
        isNot(scheme.outlineVariant),
      );
      expect(AppTheme.priorityAccent(null, scheme), scheme.outline);
    });
  });
}
