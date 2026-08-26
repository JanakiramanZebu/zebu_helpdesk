import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/core/network/connectivity_service.dart';
import 'package:zebu_helpdesk/core/theme/app_theme.dart';
import 'package:zebu_helpdesk/core/timezones.dart';
import 'package:zebu_helpdesk/data/me_repository.dart';
import 'package:zebu_helpdesk/features/profile/profile_screen.dart';
import 'package:zebu_helpdesk/models/me.dart';
import 'package:zebu_helpdesk/providers.dart';
import 'package:zebu_helpdesk/widgets/app_sheet.dart';

/// Guards the fix for the tester's "changing the timezone kills the web login"
/// report: a free-text Timezone box let `ind` reach `ost_staff.timezone`, and
/// every later staff-panel load then threw
/// `DateTimeZone::__construct(): Unknown or bad timezone`.

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

Me _me({String timezone = 'Asia/Kolkata'}) => Me.fromJson({
  'id': 7,
  'username': 'agent7',
  'name': 'Agent Seven',
  'email': 'a7@example.com',
  'available': true,
  'profile': {'timezone': timezone},
});

/// Records the body of every `POST /me`.
class _FakeMe extends MeRepository {
  _FakeMe() : super(ApiClient(tokenStorage: _NoTokens(), dio: Dio()));

  final List<Map<String, dynamic>> updates = [];

  @override
  Future<Me> updateMe(Map<String, dynamic> changes) async {
    updates.add(changes);
    return _me();
  }
}

Widget _app(_FakeMe repo, {String timezone = 'Asia/Kolkata'}) => ProviderScope(
  overrides: [
    meProvider.overrideWith((ref) async => _me(timezone: timezone)),
    meRepositoryProvider.overrideWith((ref) => repo),
    connectivityProvider.overrideWith((ref) => Stream.value(true)),
  ],
  child: MaterialApp(theme: AppTheme.light(), home: const ProfileScreen()),
);

Future<void> _openEditProfile(WidgetTester t, _FakeMe repo) async {
  // A phone-shaped surface, so the sheet's footer stays above the fold.
  await t.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(_app(repo));
  await t.pumpAndSettle();
  await t.tap(find.text('Edit profile'));
  await t.pumpAndSettle();
}

/// The sheet's Timezone control — the identity card behind it renders the same
/// zone string, so a bare `find.text` is ambiguous.
Finder _timezoneField(String value) => find.ancestor(
  of: find.text(value),
  matching: find.byType(InputDecorator),
);

Finder get _pickerSearch => find.descendant(
  of: find.byType(SheetSearchField),
  matching: find.byType(TextField),
);

void main() {
  group('kTimezones', () {
    test('carries only identifiers PHP can build a DateTimeZone from', () {
      expect(kTimezones, contains('Asia/Kolkata'));
      expect(kTimezones, contains('UTC'));
      expect(kSystemDefaultTimezone, '');
      expect(kSystemDefaultTimezone, isNot(anyOf(kTimezones)));

      // ICU hands back the legacy tzdb spellings; `listIdentifiers()` — and so
      // the web's `<select>` — uses the modern ones. A legacy id still builds a
      // DateTimeZone, but it matches no `<option>`, so the web would render the
      // agent as "System Default" and wipe the value on its next save.
      for (final legacy in [
        'Asia/Calcutta',
        'Asia/Saigon',
        'Asia/Rangoon',
        'Europe/Kiev',
        'America/Godthab',
        'America/Buenos_Aires',
        'Atlantic/Faeroe',
        'Pacific/Truk',
      ]) {
        expect(kTimezones, isNot(contains(legacy)), reason: legacy);
      }
    });

    test('is sorted and free of duplicates, as the web dropdown is', () {
      expect(kTimezones, orderedEquals([...kTimezones]..sort()));
      expect(kTimezones.toSet(), hasLength(kTimezones.length));
    });

    test('every entry is a well-formed region/city identifier', () {
      final shape = RegExp(r'^[A-Za-z_+-]+(/[A-Za-z_+-]+){0,2}$');
      for (final zone in kTimezones) {
        expect(shape.hasMatch(zone), isTrue, reason: zone);
      }
    });
  });

  testWidgets('Timezone is a picker, not a text box', (t) async {
    final repo = _FakeMe();
    await _openEditProfile(t, repo);

    // The current value is shown, and there is no controller to type `ind` into.
    expect(_timezoneField('Asia/Kolkata'), findsOneWidget);
    expect(
      find.descendant(
        of: _timezoneField('Asia/Kolkata'),
        matching: find.byType(EditableText),
      ),
      findsNothing,
    );
  });

  testWidgets('picking a zone sends that exact identifier', (t) async {
    final repo = _FakeMe();
    await _openEditProfile(t, repo);

    await t.tap(_timezoneField('Asia/Kolkata'));
    await t.pumpAndSettle();

    // 419 zones: the sheet searches rather than scrolls.
    await t.enterText(_pickerSearch, 'Europe/Kyiv');
    await t.pumpAndSettle();
    await t.tap(find.text('Europe/Kyiv').last);
    await t.pumpAndSettle();

    expect(_timezoneField('Europe/Kyiv'), findsOneWidget);

    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    expect(repo.updates, hasLength(1));
    expect(repo.updates.single['timezone'], 'Europe/Kyiv');
  });

  testWidgets('"System default" clears the zone, matching the web\'s blank '
      'option', (t) async {
    final repo = _FakeMe();
    await _openEditProfile(t, repo);

    await t.tap(_timezoneField('Asia/Kolkata'));
    await t.pumpAndSettle();
    await t.tap(find.text('System default'));
    await t.pumpAndSettle();

    expect(_timezoneField('System default'), findsOneWidget);

    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    // Empty is what makes `OsticketConfig::getTimezone()` fall back to the
    // helpdesk default — the only escape hatch when a bad value is already set.
    expect(repo.updates.single['timezone'], '');
  });
}
