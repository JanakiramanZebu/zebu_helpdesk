import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/models/meta.dart';

/// osTicket renders SLA plans as `"<name> (<n> hours - Active|Disabled)"`
/// (`SLA::getSLAs()`) and lists disabled plans alongside active ones. Only an
/// active plan computes a due date, so the app has to tell them apart.
void main() {
  group('MetaItem.activeFromLabel', () {
    test('reads the web dropdown labels', () {
      expect(MetaItem.activeFromLabel('High (2 hours - Active)'), isTrue);
      expect(MetaItem.activeFromLabel('Low (8 hours - Active)'), isTrue);
      expect(MetaItem.activeFromLabel('Emergency (1 hours - Disabled)'), isFalse);
      expect(MetaItem.activeFromLabel('SLA (18 hours - Disabled)'), isFalse);
    });

    test('is null for a plain name', () {
      expect(MetaItem.activeFromLabel('High'), isNull);
      expect(MetaItem.activeFromLabel('— System Default —'), isNull);
    });
  });

  group('MetaItem.fromJson', () {
    test('prefers an explicit flag', () {
      expect(
        MetaItem.fromJson({'id': 2, 'name': 'High', 'active': false}).active,
        isFalse,
      );
      expect(
        MetaItem.fromJson({'id': 2, 'name': 'High', 'isactive': 1}).active,
        isTrue,
      );
    });

    test('reads osTicket flag bits (FLAG_ACTIVE = 0x1)', () {
      expect(MetaItem.fromJson({'id': 2, 'name': 'High', 'flags': 3}).active, isTrue);
      expect(MetaItem.fromJson({'id': 5, 'name': 'SLA', 'flags': 0}).active, isFalse);
    });

    test('falls back to the label', () {
      expect(
        MetaItem.fromJson({'id': 1, 'name': 'Emergency (1 hours - Disabled)'}).active,
        isFalse,
      );
      expect(MetaItem.fromJson({'id': 3, 'name': 'Low'}).active, isNull);
    });

    test('leaves other meta kinds alone', () {
      final m = MetaItem.fromJson({'id': 4, 'name': 'Open', 'state': 'open'});
      expect(m.active, isNull);
      expect(m.state, 'open');
    });
  });
}
