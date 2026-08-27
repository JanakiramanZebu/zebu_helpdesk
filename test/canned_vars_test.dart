import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/canned_vars.dart';
import 'package:zebu_helpdesk/models/canned.dart';
import 'package:zebu_helpdesk/models/task.dart';
import 'package:zebu_helpdesk/models/ticket.dart';

void main() {
  group('expandCannedVars', () {
    test('resolves the tokens the ticket can answer', () {
      final t = Ticket(
        id: 7,
        number: '000123',
        subject: 'Login fails',
        statusName: 'Open',
        priority: 'High',
        departmentName: 'Support',
        topicName: 'Account',
        requester: 'Asha Ramesh Kumar',
        assignee: 'J. Iyer',
        userEmail: 'asha@example.com',
      );
      const body = '<p>Hi %{ticket.name.first}, ticket %{ticket.number} '
          '(%{ticket.subject}) is %{ticket.status} with %{ticket.dept}.</p>';
      expect(
        expandCannedVars(body, CannedVars.forTicket(t)),
        '<p>Hi Asha, ticket 000123 (Login fails) is Open with Support.</p>',
      );
    });

    test('a variable the payload cannot answer resolves to blank, not markup',
        () {
      final t = Ticket(
        id: 7,
        number: '000123',
        subject: 'S',
        statusName: 'Open',
        requester: 'Asha',
      );
      // No phone on the ticket payload, and the ticket is still open.
      final out = expandCannedVars(
          '<p>[%{ticket.phone}][%{ticket.close_date}]</p>',
          CannedVars.forTicket(t));
      expect(out, '<p>[][]</p>');
      expect(out.contains('%{'), isFalse);
    });

    test('a token outside our variable set is left alone', () {
      final out = expandCannedVars(
          '<p>%{ticket.number} %{something.else}</p>',
          CannedVars.forTicket(Ticket(
              id: 1, number: '42', subject: 'S', statusName: 'Open')));
      expect(out, '<p>42 %{something.else}</p>');
    });

    test('values are html-escaped so they cannot break the body', () {
      final out = expandCannedVars(
          '<p>%{ticket.subject}</p>',
          CannedVars.forTicket(Ticket(
              id: 1,
              number: '42',
              subject: 'A & B <script>',
              statusName: 'Open')));
      expect(out, '<p>A &amp; B &lt;script&gt;</p>');
    });

    test('task thread resolves what the task carries', () {
      final t = Task(
        id: 3,
        number: '000900',
        title: 'Ship the box',
        statusName: 'Open',
        departmentName: 'Logistics',
        assignee: 'R. Nair',
      );
      expect(
        expandCannedVars(
            '<p>%{ticket.number} / %{ticket.subject} / %{ticket.dept} / '
            '%{ticket.assigned}</p>',
            CannedVars.forTask(t)),
        '<p>000900 / Ship the box / Logistics / R. Nair</p>',
      );
    });

    test('new-ticket form resolves from what the agent filled in', () {
      final vars = CannedVars.forNewTicket(
        requester: 'Meera Devi',
        email: 'meera@example.com',
        phone: '9876543210',
        subject: 'Card blocked',
        department: 'Support',
      );
      expect(
        expandCannedVars(
            '<p>Dear %{ticket.name.first} (%{ticket.email} / %{ticket.phone}), '
            're %{ticket.subject}. Ref %{ticket.number}.</p>',
            vars),
        '<p>Dear Meera (meera@example.com / 9876543210), re Card blocked. '
        'Ref .</p>',
      );
    });

    test('an empty value map leaves the body untouched', () {
      const body = '<p>%{ticket.number}</p>';
      expect(expandCannedVars(body, const {}), body);
    });
  });

  group('CannedExpansion.fromJson', () {
    test('reads the documented key', () {
      final e = CannedExpansion.fromJson(const {
        'title': 'T',
        'response_raw': 'Hi %{ticket.name}',
        'response_expanded': 'Hi Asha',
      });
      expect(e.expanded, 'Hi Asha');
      expect(e.raw, 'Hi %{ticket.name}');
    });

    test('falls back to the other shapes a backend may serve', () {
      expect(
        CannedExpansion.fromJson(const {'response': 'Hi Asha'}).expanded,
        'Hi Asha',
      );
      expect(
        CannedExpansion.fromJson(const {'expanded': 'Hi Asha'}).expanded,
        'Hi Asha',
      );
    });

    test('stays empty when nothing usable came back', () {
      expect(CannedExpansion.fromJson(const {'title': 'T'}).expanded, '');
    });
  });
}
