import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zebu_helpdesk/app.dart';

void main() {
  testWidgets('App boots into the splash screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ZebuHelpdeskApp()));
    await tester.pump();

    // The splash shows the app name while the session bootstraps.
    expect(find.text('Zebu Helpdesk'), findsOneWidget);
  });
}
