import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/web/form_fields.dart';

Future<void> _pump(WidgetTester tester, {int? minLines, int maxLines = 1}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ZebuFormInput(
                  controller: TextEditingController(),
                  hint: 'e.g. Reconcile August partner ledger',
                  minLines: minLines,
                  maxLines: maxLines,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ZebuSelectField(
                  onTap: () {},
                  icon: Icons.apartment_outlined,
                  placeholder: 'Choose a department',
                ),
              ),
            ],
          ),
        ),
      ),
    );

void main() {
  testWidgets('a single-line input and a select stand at the same height', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pumpAndSettle();

    // InputDecorator, not TextField: the decorator paints the filled box and
    // its border, so it is the height you actually see. Measuring the
    // TextField once passed while the visible box was half that.
    final input = tester.getSize(find.byType(InputDecorator)).height;
    final select = tester.getSize(find.byType(ZebuSelectField)).height;

    expect(input, select, reason: 'input $input vs select $select');
    expect(input, kZebuFieldHeight);
  });

  testWidgets('a multi-line input is free to grow past it', (tester) async {
    await _pump(tester, minLines: 5, maxLines: 12);
    await tester.pumpAndSettle();

    // The pin is for single-line controls sharing a row with a select. A
    // Description box obeying it would be a one-line slot.
    expect(
      tester.getSize(find.byType(InputDecorator)).height,
      greaterThan(kZebuFieldHeight * 2),
    );
  });
}
