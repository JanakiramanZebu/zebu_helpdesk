import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/core/network/connectivity_service.dart';
import 'package:zebu_helpdesk/core/theme/app_theme.dart';
import 'package:zebu_helpdesk/data/me_repository.dart';
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
    // `/me` always serves both — `getFirstName()` / `getLastName()`, which
    // `Staff::updateProfile()` requires back.
    'firstname': 'Agent',
    'lastname': 'Seven',
    'phone': '044-1234',
    'mobile': '9876543210',
    'timezone': 'Asia/Kolkata',
  },
});

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

/// Records what the Edit profile sheet actually sent, so a test can assert
/// that a rejected field never reached the network.
class _FakeMe extends MeRepository {
  _FakeMe() : super(ApiClient(tokenStorage: _NoTokens(), dio: Dio()));

  final List<Map<String, dynamic>> saved = [];

  @override
  Future<Me> updateMe(Map<String, dynamic> changes) async {
    saved.add(changes);
    return _me();
  }
}

/// Opens the Edit profile sheet on a phone-shaped surface.
Future<void> _openEdit(WidgetTester t, _FakeMe repo) async {
  await t.binding.setSurfaceSize(const Size(420, 1000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        meProvider.overrideWith((ref) async => _me()),
        meRepositoryProvider.overrideWithValue(repo),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const ProfileScreen()),
    ),
  );
  await t.pumpAndSettle();
  await t.tap(find.text('Edit profile'));
  await t.pumpAndSettle();
}

Finder get _mobileField => find.widgetWithText(TextField, 'Mobile');

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
    // The landline is too short to be an Indian subscriber number, so it is
    // shown as stored; the mobile is rendered in Indian form ([Fmt.phone]) —
    // osTicket hands both back through its own US formatter.
    expect(find.text('044-1234'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget);
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

  // --- Phone / mobile validation ------------------------------------------
  //
  // `Staff::updateProfile()` runs `Validator::is_phone()` on each number that
  // was typed (`include/class.staff.php:958`): strip `( ) - . +` and spaces,
  // then require 7-16 numeric characters. The web only learns this on submit;
  // the app checks first and uses the server's own wording.

  testWidgets('a too-short mobile is rejected before any request', (t) async {
    final repo = _FakeMe();
    await _openEdit(t, repo);

    await t.enterText(_mobileField, '12345');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    expect(find.text('Valid phone number is required'), findsOneWidget);
    expect(repo.saved, isEmpty, reason: 'nothing should reach the network');
  });

  testWidgets('letters in a mobile number are rejected', (t) async {
    final repo = _FakeMe();
    await _openEdit(t, repo);

    await t.enterText(_mobileField, '98765 call me');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    expect(find.text('Valid phone number is required'), findsOneWidget);
    expect(repo.saved, isEmpty);
  });

  testWidgets('an international mobile is accepted as typed', (t) async {
    final repo = _FakeMe();
    await _openEdit(t, repo);

    // 12 digits once `+` and the spaces are stripped — inside osTicket's
    // 7-16 window, so the web accepts it too. It must not be reformatted or
    // stripped on the way out.
    await t.enterText(_mobileField, '+91 98765 43210');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    expect(repo.saved, hasLength(1));
    expect(repo.saved.single['mobile'], '+91 98765 43210');
  });

  testWidgets('clearing the mobile is allowed — it is optional', (t) async {
    final repo = _FakeMe();
    await _openEdit(t, repo);

    await t.enterText(_mobileField, '');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    expect(repo.saved, hasLength(1));
    expect(repo.saved.single['mobile'], '');
  });

  testWidgets('the error clears while the number is being corrected', (t) async {
    final repo = _FakeMe();
    await _openEdit(t, repo);

    await t.enterText(_mobileField, '12345');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Valid phone number is required'), findsOneWidget);

    await t.enterText(_mobileField, '123456');
    await t.pumpAndSettle();
    expect(find.text('Valid phone number is required'), findsNothing);
  });
}
