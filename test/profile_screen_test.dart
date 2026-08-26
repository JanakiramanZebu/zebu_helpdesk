import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/network/connectivity_service.dart';
import 'package:zebu_helpdesk/core/theme/app_theme.dart';
import 'package:zebu_helpdesk/features/profile/profile_screen.dart';
import 'package:zebu_helpdesk/models/me.dart';
import 'package:zebu_helpdesk/providers.dart';
import 'package:zebu_helpdesk/widgets/glass.dart';
import 'package:zebu_helpdesk/widgets/keyboard_dismisser.dart';
import 'package:zebu_helpdesk/widgets/offline_banner.dart';

/// The profile screen rendered under the *real* app shell — the aurora canvas,
/// the offline banner's `Column`/`Expanded`, and `AppTheme`. The theme gives
/// filled/outlined buttons `Size.fromHeight(50)`, an infinite minimum width, so
/// an action button placed in a width-unbounded parent (a bare `Row` child)
/// throws "BoxConstraints forces an infinite width" and cascades into
/// "RenderBox was not laid out". Pumping the bare screen under a plain
/// `MaterialApp` does not catch it — the shell has to be here.
Me _me() => Me.fromJson({
  'id': 7,
  'username': 'agent7',
  'name': 'Agent Seven',
  'email': 'a7@example.com',
  'available': true,
  'profile': {
    'phone': '044-1234',
    'mobile': '9876543210',
    'timezone': 'Asia/Kolkata',
  },
});

Widget _app({required bool online, required ThemeData theme}) => ProviderScope(
  overrides: [
    meProvider.overrideWith((ref) async => _me()),
    connectivityProvider.overrideWith((ref) => Stream.value(online)),
  ],
  child: MaterialApp(
    theme: theme,
    home: const ProfileScreen(),
    // Mirrors `lib/app.dart`'s builder.
    builder: (context, child) {
      final base = Theme.of(context);
      return KeyboardDismisser(
        child: Theme(
          data: Glass.tint(base),
          child: Glass.canvas(
            brightness: base.brightness,
            child: OfflineBanner(child: child ?? const SizedBox.shrink()),
          ),
        ),
      );
    },
  ),
);

void main() {
  testWidgets('identity card shows the contact details from /me', (t) async {
    await t.pumpWidget(_app(online: true, theme: AppTheme.light()));
    await t.pumpAndSettle();

    expect(find.text('Agent Seven'), findsOneWidget);
    expect(find.text('@agent7'), findsOneWidget);
    expect(find.text('a7@example.com'), findsOneWidget);
    expect(find.text('044-1234'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);
    expect(find.text('Asia/Kolkata'), findsOneWidget);
  });

  testWidgets('a profile with no phone/mobile/timezone shows no empty rows', (
    t,
  ) async {
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          meProvider.overrideWith(
            (ref) async => Me.fromJson({
              'id': 7,
              'username': 'agent7',
              'name': 'Agent Seven',
              'email': 'a7@example.com',
            }),
          ),
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Phone'), findsNothing);
    expect(find.text('Mobile'), findsNothing);
    expect(find.text('Timezone'), findsNothing);
  });

  for (final dark in [false, true]) {
    for (final online in [true, false]) {
      testWidgets('sheets lay out in the app shell (dark=$dark online=$online)', (
        t,
      ) async {
        // A phone-shaped surface: the default 800x600 test window puts the
        // sheet footer below the fold, so the taps would miss.
        await t.binding.setSurfaceSize(const Size(420, 900));
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(
          _app(
            online: online,
            theme: dark ? AppTheme.dark() : AppTheme.light(),
          ),
        );
        await t.pumpAndSettle();

        await t.tap(find.text('Edit profile'));
        await t.pumpAndSettle();
        expect(find.text('Save'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();

        await t.tap(find.text('Change password'));
        await t.pumpAndSettle();
        expect(find.text('Update password'), findsOneWidget);
      });
    }
  }
}
