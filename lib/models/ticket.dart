import '../core/api/json.dart';

/// A ticket. The API returns a lightweight *summary* shape in list endpoints
/// and a richer *full* shape from `GET /tickets/{id}` and action endpoints.
/// This model absorbs both (e.g. `status`/`department` may be a string or an
/// `{id,name}` object).
class Ticket {
  const Ticket({
    required this.id,
    required this.number,
    required this.subject,
    required this.statusName,
    this.statusId,
    this.priority,
    this.departmentName,
    this.departmentId,
    this.requester,
    this.assignee,
    this.userId,
    this.userEmail,
    this.created,
    this.updated,
    this.due,
    this.isOverdue = false,
    this.sla,
    this.customFields = const {},
  });

  final int id;
  final String number;
  final String subject;
  final String statusName;
  final int? statusId;
  final String? priority;
  final String? departmentName;
  final int? departmentId;

  /// Summary uses `requester`; full uses `user{name}`.
  final String? requester;
  final String? assignee;
  final int? userId;
  final String? userEmail;
  final DateTime? created;
  final DateTime? updated;
  final DateTime? due;
  final bool isOverdue;
  final Sla? sla;

  /// `{ label: displayValue }` (full shape only).
  final Map<String, String> customFields;

  bool get isClosed => statusName.toLowerCase().contains('closed');

  factory Ticket.fromJson(Map<String, dynamic> j) {
    // status: string (summary) or { id, name } (full)
    String statusName;
    int? statusId;
    final statusRaw = j['status'];
    if (statusRaw is Map) {
      statusName = J.strOr(statusRaw['name']);
      statusId = J.intOrNull(statusRaw['id']);
    } else {
      statusName = J.strOr(statusRaw);
    }

    // department: string (summary) or { id, name } (full)
    String? deptName;
    int? deptId;
    final deptRaw = j['department'];
    if (deptRaw is Map) {
      deptName = J.str(deptRaw['name']);
      deptId = J.intOrNull(deptRaw['id']);
    } else {
      deptName = J.str(deptRaw);
    }

    // user: { id, name, email } (full only)
    final user = j['user'] is Map ? J.map(j['user']) : const {};

    final cf = <String, String>{};
    if (j['custom_fields'] is Map) {
      J.map(j['custom_fields']).forEach((k, v) => cf[k] = J.strOr(v));
    }

    return Ticket(
      id: J.intOr(j['id']),
      number: J.strOr(j['number']),
      subject: J.strOr(j['subject']),
      statusName: statusName,
      statusId: statusId,
      priority: J.str(j['priority']),
      departmentName: deptName,
      departmentId: deptId,
      requester: J.str(j['requester']) ?? J.str(user['name']),
      assignee: J.str(j['assignee']),
      userId: J.intOrNull(user['id']),
      userEmail: J.str(user['email']),
      created: J.dateTime(j['created']),
      updated: J.dateTime(j['updated']),
      due: J.dateTime(j['due']),
      isOverdue: J.boolOr(j['isoverdue']),
      sla: j['sla'] is Map ? Sla.fromJson(J.map(j['sla'])) : null,
      customFields: cf,
    );
  }
}

/// SLA window summary on the full ticket object.
class Sla {
  const Sla({this.frac, this.label, this.due});

  /// 0..1 fraction of the SLA window remaining.
  final double? frac;

  /// Short remaining time ("8h", "2d") or "Overdue".
  final String? label;
  final DateTime? due;

  bool get isOverdue => label?.toLowerCase() == 'overdue';

  factory Sla.fromJson(Map<String, dynamic> j) => Sla(
        frac: J.doubleOrNull(j['frac']),
        label: J.str(j['label']),
        due: J.dateTime(j['due']),
      );
}

/// An editable custom dynamic field on a ticket (`GET /tickets/{id}/fields`).
class TicketField {
  const TicketField({
    required this.name,
    required this.label,
    this.hint,
    required this.type,
    this.required = false,
    this.editable = true,
    this.choices,
    this.multiselect = false,
    this.value,
  });

  final String name;
  final String label;
  final String? hint;
  final String type; // text | choices | ...
  final bool required;
  final bool editable;

  /// `{ choiceKey: choiceLabel }` for choice fields, else null.
  final Map<String, String>? choices;
  final bool multiselect;

  /// Choice key (or list of keys when multiselect), or a plain string; null
  /// when unanswered.
  final dynamic value;

  factory TicketField.fromJson(Map<String, dynamic> j) {
    Map<String, String>? choices;
    if (j['choices'] is Map) {
      choices = {};
      J.map(j['choices']).forEach((k, v) => choices![k] = J.strOr(v));
    }
    return TicketField(
      name: J.strOr(j['name']),
      label: J.strOr(j['label']),
      hint: J.str(j['hint']),
      type: J.strOr(j['type'], 'text'),
      required: J.boolOr(j['required']),
      editable: J.boolOr(j['editable'], true),
      choices: choices,
      multiselect: J.boolOr(j['multiselect']),
      value: j['value'],
    );
  }
}

/// A ticket/task referral target.
class Referral {
  const Referral({
    required this.id,
    required this.type,
    required this.objectId,
    required this.name,
  });
  final int id;
  final String type; // staff | team | dept
  final int objectId;
  final String name;

  factory Referral.fromJson(Map<String, dynamic> j) => Referral(
        id: J.intOr(j['id']),
        type: J.strOr(j['type']),
        objectId: J.intOr(j['object_id']),
        name: J.strOr(j['name']),
      );
}

/// Parent/child relations (`GET /tickets/{id}/relations`).
class TicketRelations {
  const TicketRelations({this.parent, this.mergeType, this.children = const []});

  final RelatedTicket? parent;
  final String? mergeType; // combine | ... | null
  final List<RelatedTicket> children;

  factory TicketRelations.fromJson(Map<String, dynamic> j) => TicketRelations(
        parent: j['parent'] is Map
            ? RelatedTicket.fromJson(J.map(j['parent']))
            : null,
        mergeType: J.str(j['merge_type']),
        children:
            J.mapList(j['children']).map(RelatedTicket.fromJson).toList(),
      );
}

class RelatedTicket {
  const RelatedTicket({
    required this.ticketId,
    required this.number,
    required this.subject,
  });
  final int ticketId;
  final String number;
  final String subject;

  factory RelatedTicket.fromJson(Map<String, dynamic> j) => RelatedTicket(
        ticketId: J.intOr(j['ticket_id']),
        number: J.strOr(j['number']),
        subject: J.strOr(j['subject']),
      );
}
