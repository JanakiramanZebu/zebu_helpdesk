import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/web/user_card.dart';

void main() {
  _noJumpTest();
  testWidgets('the two people cards line up in a row', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ZebuUserCard(
                  name: 'Arpit Aggarwal',
                  email: 'arpit@globecapital.com',
                  onChange: () {},
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ZebuCollaboratorsCard(
                  names: const ['Amol', 'Baskar', 'Jayashree', 'Karunakar'],
                  onEdit: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A 36 px avatar over two lines against a 32 px stack over one used to
    // land 4 px apart, which reads as a step where they sit side by side.
    final requester = tester.getSize(find.byType(ZebuUserCard)).height;
    final collaborators = tester
        .getSize(find.byType(ZebuCollaboratorsCard))
        .height;
    expect(requester, collaborators);
    expect(requester, greaterThanOrEqualTo(kZebuUserCardMinHeight));
  });

  testWidgets('four avatars then a +n disc, never more', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZebuCollaboratorsCard(
            names: List.generate(12, (i) => 'Person $i'),
            onEdit: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('+8'), findsOneWidget);
    expect(find.text('12 collaborators'), findsOneWidget);
    // No names line: twelve of them ellipsised to a fragment naming three.
    expect(find.textContaining('Person 0,'), findsNothing);
  });
}

/// Choosing someone must not resize the field.
void _noJumpTest() {
  testWidgets('empty and filled stand at the same height', (tester) async {
    Future<double> heightOf(Widget child) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SizedBox(width: 300, child: child)),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getSize(find.byWidget(child)).height;
    }

    final empty = await heightOf(
      ZebuPersonPlaceholder(
        icon: Icons.person_outline,
        label: 'Select a requester',
        hint: 'Who the ticket is for',
        onTap: () {},
      ),
    );
    final filled = await heightOf(
      ZebuUserCard(
        name: 'Amol Mohile',
        email: 'amol.mohile@billdesk.com',
        onChange: () {},
      ),
    );
    final many = await heightOf(
      ZebuCollaboratorsCard(names: const ['A', 'B'], onEdit: () {}),
    );

    // A 40 px select turning into a 64 px card pushed everything below it
    // down the page the moment you picked someone.
    expect(empty, filled);
    expect(empty, many);
  });
}
