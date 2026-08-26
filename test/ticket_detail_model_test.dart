import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/models/ticket.dart';

/// `GET /tickets/{id}` as the deployed backend serves it today: `sla` carries
/// only the ring data, and nothing names the plan or the lock.
Map<String, dynamic> _base() => {
  'id': 1042,
  'number': '807431',
  'subject': 'Cannot log in',
  'status': {'id': 1, 'name': 'Open'},
  'priority': 'High',
  'department': {'id': 2, 'name': 'IT Development'},
  'assignee': 'Sowmiya Ramesh',
  'user': {'id': 24, 'name': 'Sowmiya Ramesh', 'email': 's@zebuetrade.com'},
  'created': '2026-08-18 11:32:00',
  'updated': '2026-08-18 12:00:00',
  'due': '2026-08-19 04:30:00',
  'isoverdue': false,
  'sla': {'frac': 0.42, 'label': '8h', 'due': '2026-08-19 04:30:00'},
  'custom_fields': {'Client Id': '03'},
};

void main() {
  group('Ticket.dueDateLocked', () {
    test('today\'s payload leaves the due date editable', () {
      final t = Ticket.fromJson(_base());
      expect(t.dueDateLocked, isFalse);
      expect(t.sla!.label, '8h');
      expect(t.sla!.name, isNull);
    });

    test('sla_locked is authoritative', () {
      expect(Ticket.fromJson({..._base(), 'sla_locked': true}).dueDateLocked,
          isTrue);
      expect(Ticket.fromJson({..._base(), 'sla_locked': false}).dueDateLocked,
          isFalse);
    });

    test('can_set_duedate is read as the inverse', () {
      expect(
        Ticket.fromJson({..._base(), 'can_set_duedate': false}).dueDateLocked,
        isTrue,
      );
      expect(
        Ticket.fromJson({..._base(), 'can_set_duedate': true}).dueDateLocked,
        isFalse,
      );
    });

    test('a locked flag inside sla counts', () {
      final t = Ticket.fromJson({
        ..._base(),
        'sla': {'id': 3, 'name': 'High', 'locked': true, 'label': '8h'},
      });
      expect(t.dueDateLocked, isTrue);
      expect(t.sla!.name, 'High');
    });

    test('falls back to the web rule: any real plan drives the date', () {
      // slaId > 0 locks, "None" (0) does not - see ticket-open.inc.php.
      expect(
        Ticket.fromJson({
          ..._base(),
          'sla': {'id': 3, 'name': 'High'},
        }).dueDateLocked,
        isTrue,
      );
      expect(
        Ticket.fromJson({
          ..._base(),
          'sla': {'id': 0, 'name': 'None'},
        }).dueDateLocked,
        isFalse,
      );
    });
  });

  group('Ticket detail extras', () {
    test('are absent on the current contract', () {
      final t = Ticket.fromJson(_base());
      expect(t.source, isNull);
      expect(t.topicName, isNull);
      expect(t.organization, isNull);
      expect(t.closedAt, isNull);
      expect(t.lastMessage, isNull);
      expect(t.lastResponse, isNull);
    });

    test('parse once the backend publishes them', () {
      final t = Ticket.fromJson({
        ..._base(),
        'source': 'Phone',
        'topic': {'id': 7, 'name': 'Client'},
        'organization': {'name': 'Zebu'},
        'closed': '2026-08-20 09:00:00',
        'last_message': '2026-08-18 11:35:00',
        'last_response': '2026-08-18 12:00:00',
      });
      expect(t.source, 'Phone');
      expect(t.topicId, 7);
      expect(t.topicName, 'Client');
      expect(t.organization, 'Zebu');
      expect(t.closedAt, isNotNull);
      expect(t.lastMessage, isNotNull);
      expect(t.lastResponse, isNotNull);
    });

    test('accept a plain string topic and a bare topic_id', () {
      final t = Ticket.fromJson({
        ..._base(),
        'topic': 'Client',
        'topic_id': 7,
      });
      expect(t.topicName, 'Client');
      expect(t.topicId, 7);
    });

    test('accept the plan alongside the ring object', () {
      // `sla` keeps carrying the window data while the plan itself arrives as
      // top-level `sla_id` / `sla_name`.
      final t = Ticket.fromJson({
        ..._base(),
        'sla_id': 2,
        'sla_name': 'High',
      });
      expect(t.sla!.name, 'High');
      expect(t.sla!.id, 2);
      expect(t.sla!.label, '8h', reason: 'ring data must survive the merge');
      expect(t.dueDateLocked, isTrue);
    });

    test('unwrap a nested plan object instead of stringifying it', () {
      // Live payload shape that rendered as "{id: 5, name: Low}" on screen.
      for (final j in [
        {'sla': {'plan': {'id': 5, 'name': 'Low'}, 'frac': 0.42, 'label': '8h'}},
        {'sla': {'name': {'id': 5, 'name': 'Low'}, 'label': '8h'}},
        {'sla_plan': {'id': 5, 'name': 'Low'}},
      ]) {
        final t = Ticket.fromJson({..._base(), ...j});
        expect(t.sla!.name, 'Low', reason: 'from $j');
        expect(t.sla!.id, 5, reason: 'from $j');
        expect(t.dueDateLocked, isTrue, reason: 'from $j');
      }
    });

    test('accept a bare SLA plan name', () {
      final t = Ticket.fromJson({..._base(), 'sla': 'High'});
      expect(t.sla!.name, 'High');
      // No id and no flag, so the date stays editable until the server says
      // otherwise (the screen still locks itself if the write is refused).
      expect(t.dueDateLocked, isFalse);
    });
  });


  /// TC_440: an unset priority must stay unset so the UI prompts for it, the
  /// way the web's ticket page renders a blank inline-edit field. The two
  /// endpoints spell "none" differently — detail sends an empty string, list
  /// rows omit the key entirely — and both have to land on null.
  group('Ticket.priority empty-state', () {
    test('detail\'s empty string is not a priority', () {
      final t = Ticket.fromJson({..._base(), 'priority': ''});
      expect(t.priority, isNull);
    });

    test('whitespace-only is not a priority either', () {
      final t = Ticket.fromJson({..._base(), 'priority': '   '});
      expect(t.priority, isNull);
    });

    test('a list row omitting the key is not defaulted to Normal', () {
      final j = _base()..remove('priority');
      expect(Ticket.fromJson(j).priority, isNull);
    });

    test('a real priority is preserved verbatim', () {
      expect(Ticket.fromJson(_base()).priority, 'High');
      expect(
        Ticket.fromJson({..._base(), 'priority': 'Normal'}).priority,
        'Normal',
      );
    });
  });
}
