import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/update/update_info.dart';

/// The update sheet is driven by the shared Strapi entry at
/// `sess.mynt.in/strapi/appversion`, which Mynt Plus also reads. The helpdesk
/// takes its own `Helpdeskversion` attribute so neither app overwrites the
/// other's version:
///
/// ```json
/// { "data": { "attributes": { "Helpdeskversion": {
///     "and": "1.0.1", "ios": "1.0.1", "mandate": "no" } } } }
/// ```
UpdateInfo? _parse(Object? body) =>
    UpdateInfo.parse(body, field: 'Helpdeskversion', fallbackUrl: 'https://dl.test');

Map<String, dynamic> _wrap(Object? entry) => {
  'data': {
    'id': 1,
    'attributes': {'Helpdeskversion': entry},
  },
};

void main() {
  group('reads the helpdesk field', () {
    test('the live CMS shape', () {
      final info = _parse(_wrap({'and': '1.0.1', 'ios': '1.0.2', 'mandate': 'no'}));
      // Tests run as the host platform, not iOS, so the Android string wins.
      expect(info!.version, '1.0.1');
      expect(info.force, isFalse);
    });

    test('mandate "yes" forces the update', () {
      expect(_parse(_wrap({'and': '1.0.1', 'mandate': 'yes'}))!.force, isTrue);
    });

    test('ignores the Mynt Plus field entirely', () {
      // Mynt Plus publishing 1.0.85 must never prompt helpdesk staff.
      final body = {
        'data': {
          'attributes': {
            'Helpdeskversion': null,
            'version': {'and': '1.0.85', 'ios': '1.0.145', 'mandate': 'no'},
          },
        },
      };
      expect(_parse(body), isNull);
    });

    test('null field — the state before anyone fills it in', () {
      expect(_parse(_wrap(null)), isNull);
    });
  });

  group('envelope tolerance', () {
    test('v5 flattens attributes onto data', () {
      final info = _parse({
        'data': {
          'id': 1,
          'Helpdeskversion': {'and': '1.0.1'},
        },
      });
      expect(info!.version, '1.0.1');
    });

    test('bare unwrapped object', () {
      expect(
        _parse({
          'Helpdeskversion': {'and': '1.0.1'},
        })!.version,
        '1.0.1',
      );
    });

    test('junk envelopes yield no update, never a crash', () {
      expect(_parse(null), isNull);
      expect(_parse('not json'), isNull);
      expect(_parse(const <String, dynamic>{}), isNull);
      expect(_parse({'data': null}), isNull);
      expect(_parse(_wrap('a string, not an object')), isNull);
      expect(_parse(_wrap(const <String, dynamic>{})), isNull);
    });
  });

  group('force flag is fail-safe', () {
    test('missing mandate is optional, not forced', () {
      expect(_parse(_wrap({'and': '1.0.1'}))!.force, isFalse);
    });

    test('unexpected mandate values do not lock the app', () {
      for (final v in ['no', 'No', 'maybe', '', 'YES_PLEASE']) {
        expect(
          _parse(_wrap({'and': '1.0.1', 'mandate': v}))!.force,
          isFalse,
          reason: 'mandate "$v" must not force',
        );
      }
    });

    test('case-insensitive yes', () {
      expect(_parse(_wrap({'and': '1.0.1', 'mandate': 'YES'}))!.force, isTrue);
    });
  });

  group('download url', () {
    test('falls back to the configured page', () {
      expect(_parse(_wrap({'and': '1.0.1'}))!.downloadUrl, 'https://dl.test');
    });

    test('a url in the CMS entry wins', () {
      final info = _parse(_wrap({'and': '1.0.1', 'url': 'https://x.test/a.apk'}));
      expect(info!.downloadUrl, 'https://x.test/a.apk');
    });
  });

  group('version comparison', () {
    test('detects a newer patch', () {
      expect(UpdateInfo.isNewer('1.0.1', '1.0.0'), isTrue);
    });

    test('equal versions do not prompt', () {
      expect(UpdateInfo.isNewer('1.0.0', '1.0.0'), isFalse);
    });

    test('older remote does not prompt', () {
      expect(UpdateInfo.isNewer('1.0.0', '1.0.1'), isFalse);
    });

    test('a minor bump beats a high patch — the Mynt Plus bug', () {
      // Mynt Plus strips the dots and compares 110 > 1084, which is false, so
      // shipping 1.1.0 to users on 1.0.84 would prompt nobody.
      expect(UpdateInfo.isNewer('1.1.0', '1.0.84'), isTrue);
      expect(UpdateInfo.isNewer('2.0.0', '1.9.99'), isTrue);
    });

    test('double-digit patches compare numerically, not as text', () {
      expect(UpdateInfo.isNewer('1.0.84', '1.0.9'), isTrue);
      expect(UpdateInfo.isNewer('1.0.9', '1.0.84'), isFalse);
    });

    test('uneven segment counts pad with zeros', () {
      expect(UpdateInfo.isNewer('1.0', '1.0.0'), isFalse);
      expect(UpdateInfo.isNewer('1.0.1', '1.0'), isTrue);
    });

    test('tolerates prefixes and suffixes', () {
      expect(UpdateInfo.isNewer('v1.0.1', '1.0.0'), isTrue);
      expect(UpdateInfo.isNewer('1.0.1-beta', '1.0.0'), isTrue);
    });

    test('garbage never fabricates an update', () {
      expect(UpdateInfo.isNewer('', '1.0.0'), isFalse);
      expect(UpdateInfo.isNewer('abc', '1.0.0'), isFalse);
    });
  });
}
