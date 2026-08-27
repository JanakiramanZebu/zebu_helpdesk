import 'dart:convert';

import '../models/task.dart';
import '../models/ticket.dart';
import 'format.dart';

/// The osTicket ticket variables a canned body may embed, mirroring the
/// "Supported Variables" help tip (`include/ajax.content.php::ticket_variables`).
/// The canned editor offers these for insertion; [expandCannedVars] resolves
/// them on the way back out.
const List<(String, String)> kCannedVariables = [
  ('%{ticket.number}', 'Ticket number'),
  ('%{ticket.subject}', 'Subject'),
  ('%{ticket.name}', 'Requester full name'),
  ('%{ticket.name.first}', 'Requester first name'),
  ('%{ticket.email}', 'Requester email'),
  ('%{ticket.phone}', 'Phone number | ext'),
  ('%{ticket.status}', 'Status'),
  ('%{ticket.priority}', 'Priority'),
  ('%{ticket.assigned}', 'Assigned agent / team'),
  ('%{ticket.dept}', 'Department'),
  ('%{ticket.topic}', 'Help topic'),
  ('%{ticket.create_date}', 'Date created'),
  ('%{ticket.due_date}', 'Due date'),
  ('%{ticket.close_date}', 'Date closed'),
  ('%{ticket.staff}', 'Assigned / closing agent'),
  ('%{ticket.team}', 'Assigned / closing team'),
  ('%{recipient.name.first}', 'Recipient first name'),
  ('%{url}', 'Helpdesk base URL'),
];

/// `%{ticket.number}` / `%{url}` — the token as osTicket writes it. The inner
/// name is captured so the value map can be keyed on `ticket.number`.
final RegExp _kVarToken = RegExp(r'%\{([A-Za-z0-9_.]+)\}');

/// Values are spliced into an HTML body, so they are escaped as element text.
/// `HtmlEscapeMode.element` covers `& < >` and leaves quotes and slashes
/// readable — these land in prose an agent is about to send, not in an
/// attribute.
const HtmlEscape _escapeText = HtmlEscape(HtmlEscapeMode.element);

/// Every variable this app offers, mapped to an empty value.
///
/// osTicket resolves an unknown variable to an empty string rather than
/// leaving the token in the text, so a body written against a field the
/// payload doesn't carry (`%{ticket.phone}`) comes out blank rather than as
/// literal markup in front of a customer. Tokens *outside* this set are left
/// untouched — they aren't ours to erase.
Map<String, String?> get _blankScope => {
  for (final v in kCannedVariables) v.$1.substring(2, v.$1.length - 1): null,
};

/// Replaces every `%{…}` token in [html] that [values] knows about.
///
/// A key present with a null or empty value resolves to an empty string; a
/// token absent from [values] is left exactly as it was.
String expandCannedVars(String html, Map<String, String?> values) {
  if (html.isEmpty || values.isEmpty) return html;
  return html.replaceAllMapped(_kVarToken, (m) {
    final name = m[1]!;
    if (!values.containsKey(name)) return m[0]!;
    final value = values[name];
    return value == null || value.isEmpty ? '' : _escapeText.convert(value);
  });
}

/// Builders for the value map [expandCannedVars] consumes.
///
/// `GET /canned/{id}/expand` is the authority whenever it can be reached — it
/// runs osTicket's own `VariableReplacer` against the real ticket. These cover
/// the surfaces it cannot serve: a task reply (the task payload carries no
/// ticket id) and the new-ticket form (there is no ticket yet), plus the
/// fallback for when that call fails, so an agent never sends a customer a
/// literal `%{ticket.name}`.
abstract final class CannedVars {
  /// First word of a full name — osTicket's `PersonsName::getFirst()`.
  static String? _first(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? null : parts.first;
  }

  /// Null (not "—") for a missing date, so the token resolves to blank rather
  /// than to [Fmt]'s em-dash placeholder.
  static String? _when(DateTime? d) => d == null ? null : Fmt.dateTime(d);

  static Map<String, String?> forTicket(Ticket? t) {
    if (t == null) return const {};
    return {
      ..._blankScope,
      'ticket.number': t.number,
      'ticket.subject': t.subject,
      'ticket.name': t.requester,
      'ticket.name.first': _first(t.requester),
      'ticket.email': t.userEmail,
      'ticket.status': t.statusName,
      'ticket.priority': t.priority,
      'ticket.assigned': t.assignee,
      'ticket.dept': t.departmentName,
      'ticket.topic': t.topicName,
      'ticket.create_date': _when(t.created),
      'ticket.due_date': _when(t.due),
      'ticket.close_date': _when(t.closedAt),
      // The payload doesn't split assignment into agent vs team, so both
      // osTicket tokens resolve to whoever/whatever holds the ticket.
      'ticket.staff': t.assignee,
      'ticket.team': t.assignee,
      'recipient.name.first': _first(t.requester),
    };
  }

  /// A task thread. The task payload carries no requester, email or parent
  /// ticket, so the requester-side tokens stay blank until the backend
  /// publishes the task's ticket (see BACKEND_REQUIREMENTS).
  static Map<String, String?> forTask(Task? t) {
    if (t == null) return const {};
    return {
      ..._blankScope,
      'ticket.number': t.number,
      'ticket.subject': t.title,
      'ticket.status': t.statusName,
      'ticket.priority': t.priority?.name,
      'ticket.assigned': t.assignee,
      'ticket.dept': t.departmentName,
      'ticket.create_date': _when(t.created),
      'ticket.due_date': _when(t.duedate),
      'ticket.staff': t.assignee,
      'ticket.team': t.assignee,
    };
  }

  /// The new-ticket form, resolved from what the agent has filled in so far.
  /// There is no ticket yet, so `%{ticket.number}` and the dates that only
  /// exist after creation resolve to blank.
  static Map<String, String?> forNewTicket({
    String? requester,
    String? email,
    String? phone,
    String? subject,
    String? department,
    String? topic,
    String? priority,
    DateTime? due,
  }) => {
    ..._blankScope,
    'ticket.subject': subject,
    'ticket.name': requester,
    'ticket.name.first': _first(requester),
    'ticket.email': email,
    'ticket.phone': phone,
    'ticket.dept': department,
    'ticket.topic': topic,
    'ticket.priority': priority,
    'ticket.due_date': _when(due),
    'recipient.name.first': _first(requester),
  };
}
