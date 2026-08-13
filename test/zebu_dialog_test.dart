import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/widgets/web/zebu_dialog.dart';

/// `ZebuDialogShell` is a full-screen `Center`, so its own size is the window.
/// The frame is the `ClipRRect` that holds the header, body and footer.
Finder _frame() => find.descendant(
  of: find.byType(ZebuDialogShell),
  matching: find.byType(ClipRRect),
);

Widget _host(Widget shell, Size window) => MediaQuery(
  data: MediaQueryData(size: window),
  child: MaterialApp(home: Scaffold(body: shell)),
);

void main() {
  testWidgets('a capped dialog stops growing and scrolls its body', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        ZebuDialogShell(
          title: 'New ticket',
          maxWidth: 640,
          maxHeight: 700,
          onDismiss: () {},
          actions: const [],
          body: Column(
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 40, child: Text('$i')),
            ],
          ),
        ),
        const Size(1400, 1000),
      ),
    );
    await tester.pumpAndSettle();

    // 40 x 40 px of body is 1600 px of content; the frame holds at 700.
    final box = tester.getSize(_frame());
    expect(box.width, 640);
    expect(box.height, 700);
    expect(find.byType(Scrollable), findsWidgets);
  });

  testWidgets('the cap never pushes the dialog off a short window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        ZebuDialogShell(
          title: 'New ticket',
          maxWidth: 640,
          maxHeight: 700,
          onDismiss: () {},
          actions: const [],
          body: Column(
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 40, child: Text('$i')),
            ],
          ),
        ),
        const Size(1400, 600),
      ),
    );
    await tester.pumpAndSettle();

    // 600 window − 24 inset top and bottom. The window wins over the cap.
    expect(tester.getSize(_frame()).height, 552);
  });

  testWidgets('without a cap the dialog is still content-sized', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ZebuDialogShell(
          title: 'Delete',
          onDismiss: () {},
          actions: const [],
          body: const SizedBox(height: 60),
        ),
        const Size(1400, 1000),
      ),
    );
    await tester.pumpAndSettle();
    // Header + 20 + 60 + 20, nowhere near any cap.
    expect(tester.getSize(_frame()).height, lessThan(200));
  });
}
