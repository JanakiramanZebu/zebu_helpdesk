import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/res/zebu_theme.dart';
import 'package:zebu_helpdesk/widgets/web/form_fields.dart';
import 'package:zebu_helpdesk/widgets/web/user_card.dart';

void main() {
  testWidgets('a field error shows under that field, in red', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZebuLabeledField(
            label: 'Title',
            error: 'A task needs a title',
            child: ZebuFormInput(
              controller: TextEditingController(),
              hint: 'e.g. Reconcile August partner ledger',
              hasError: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Under the control, not in a banner at the top of the dialog.
    final field = tester.getBottomLeft(find.byType(ZebuFormInput)).dy;
    final message = tester.getTopLeft(find.text('A task needs a title')).dy;
    expect(message, greaterThanOrEqualTo(field));
  });

  testWidgets('an errored input and a clean one differ', (tester) async {
    Future<InputDecoration> decoration({required bool hasError}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZebuFormInput(
              controller: TextEditingController(),
              hint: 'x',
              hasError: hasError,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.widget<TextField>(find.byType(TextField)).decoration!;
    }

    final clean = await decoration(hasError: false);
    final bad = await decoration(hasError: true);
    expect(bad.enabledBorder, isNot(clean.enabledBorder));
  });

  testWidgets('the empty person card goes red too', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZebuPersonPlaceholder(
            icon: Icons.person_outline,
            label: 'Select a requester',
            hint: 'Who the ticket is for',
            hasError: true,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(ZebuPersonPlaceholder),
            matching: find.byType(Container),
          )
          .first,
    );
    // Asserts it is the theme's danger tone, not a hardcoded hex — the tone
    // is the theme's to choose; what matters is that it is not the accent.
    final border = (box.decoration! as BoxDecoration).border! as Border;
    final t = ZebuTheme.of(tester.element(find.byType(ZebuPersonPlaceholder)));
    expect(border.top.color, t.danger);
    expect(border.top.color, isNot(t.accent));
  });
}
