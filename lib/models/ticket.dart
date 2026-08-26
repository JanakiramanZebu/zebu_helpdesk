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
    this.dueDateLocked = false,
    this.source,
    this.topicId,
    this.topicName,
    this.organization,
    this.closedAt,
    this.lastMessage,
    this.lastResponse,
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

  /// True when an active SLA plan computes the due date, so it must not be
  /// edited by hand. The web renders a padlock instead of the inline editor
  /// (`include/staff/ticket-view.inc.php`) and the backend rejects a manual
  /// edit with the same rule (`Ticket::updateField()`).
  final bool dueDateLocked;

  /// How the ticket arrived ("Phone", "Web", "Email"). Only on backends that
  /// publish it.
  final String? source;

  /// Help topic (`topic`), when the payload carries it.
  final int? topicId;
  final String? topicName;

  /// Requester's organization name, when the payload carries it.
  final String? organization;

  /// Close date (closed tickets), and the web's Last Message / Last Response
  /// timestamps. Null on backends that don't publish them - the detail screen
  /// falls back to the thread it already loaded for the last two.
  final DateTime? closedAt;
  final DateTime? lastMessage;
  final DateTime? lastResponse;

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

    // SLA: `{frac,label,due}` today, potentially `{id,name,locked,...}` or a
    // bare plan name on a backend that publishes the plan itself.
    final slaRaw = j['sla'];
    var sla = slaRaw is Map
        ? Sla.fromJson(J.map(slaRaw))
        : (J.strNonBlank(slaRaw) == null
              ? null
              : Sla(name: J.strNonBlank(slaRaw)));

    // The plan may also arrive alongside the ring object rather than inside
    // it (`sla_id` / `sla_name` / `sla_plan`, any of them possibly an
    // `{id,name}` object); fold those in without losing the window data.
    final plan = Sla.planRef(
      j['sla_plan'] ?? j['sla_name'] ?? j['slaplan'] ?? j['sla_plan_name'],
    );
    final planId = J.intOrNull(j['sla_id'] ?? j['slaId']) ?? plan.$1;
    final planName = plan.$2;
    if (planId != null || planName != null) {
      sla = Sla(
        id: sla?.id ?? planId,
        name: sla?.name ?? planName,
        locked: sla?.locked,
        frac: sla?.frac,
        label: sla?.label,
        due: sla?.due,
      );
    }

    // Help topic: a string, an `{id,name}` object, or a bare `topic_id`.
    final topicRaw = j['topic'] ?? j['help_topic'] ?? j['helptopic'];
    final topicMap = topicRaw is Map ? J.map(topicRaw) : const <String, dynamic>{};

    // Organization: on the ticket or nested under `user`.
    final orgRaw = j['organization'] ?? j['org'] ?? user['organization'];

    // Due-date lock. `GET /tickets/{id}` publishes `sla_locked` /
    // `can_set_duedate` (the same keys `GET /tickets/form` uses) straight from
    // `Ticket::updateField()`'s own rejection rule, so the server wins whenever
    // it speaks. The plan-id fallback below only covers payloads that carry no
    // flag at all - a list row promoted to a Ticket, say.
    final bool locked;
    if (j['sla_locked'] != null) {
      locked = J.boolOr(j['sla_locked']);
    } else if (j['can_set_duedate'] != null) {
      locked = !J.boolOr(j['can_set_duedate'], true);
    } else if (sla?.locked != null) {
      locked = sla!.locked!;
    } else {
      locked = (sla?.id ?? 0) > 0;
    }

    return Ticket(
      id: J.intOr(j['id']),
      number: J.strOr(j['number']),
      subject: J.strOr(j['subject']),
      statusName: statusName,
      statusId: statusId,
      // Never substitute a default for display — the web doesn't. Its ticket
      // page renders the priority answer as-is (blank when unset) and the
      // queue reads the same empty cdata column, so "unset" must stay unset
      // and let the UI prompt for it. The two endpoints spell it differently:
      // detail sends "" for an unset priority, list rows omit the key, and
      // blank-aware parsing collapses both to null.
      priority: J.strNonBlank(j['priority']),
      departmentName: deptName,
      departmentId: deptId,
      // Blank-aware: the summary payload can carry an empty `requester`
      // string, which must fall through to `user{name}` and — failing that
      // — stay null so the rows render their "Unknown" placeholder.
      requester: J.strNonBlank(j['requester']) ?? J.strNonBlank(user['name']),
      assignee: J.str(j['assignee']),
      userId: J.intOrNull(user['id']),
      userEmail: J.str(user['email']),
      created: J.dateTime(j['created']),
      updated: J.dateTime(j['updated']),
      due: J.dateTime(j['due']),
      isOverdue: J.boolOr(j['isoverdue']),
      sla: sla,
      dueDateLocked: locked,
      source: J.strNonBlank(
        j['source'] is Map ? J.map(j['source'])['name'] : j['source'],
      ),
      topicId: topicRaw is Map
          ? J.intOrNull(topicMap['id'])
          : J.intOrNull(j['topic_id']),
      topicName: topicRaw is Map
          ? J.strNonBlank(topicMap['name'])
          : J.strNonBlank(topicRaw),
      organization: orgRaw is Map
          ? J.strNonBlank(J.map(orgRaw)['name'])
          : J.strNonBlank(orgRaw),
      closedAt: J.dateTime(
        j['closed'] ?? j['closed_at'] ?? j['close_date'] ?? j['closedate'],
      ),
      lastMessage: J.dateTime(
        j['last_message'] ?? j['lastmessage'] ?? j['last_msg_date'],
      ),
      lastResponse: J.dateTime(
        j['last_response'] ?? j['lastresponse'] ?? j['last_resp_date'],
      ),
      customFields: cf,
    );
  }
}

/// SLA window summary on the full ticket object.
class Sla {
  const Sla({this.id, this.name, this.locked, this.frac, this.label, this.due});

  /// The plan itself, when the backend publishes it (0 / null = no plan).
  final int? id;
  final String? name;

  /// Server's own verdict on whether the plan drives the due date. Null when
  /// it doesn't say - [Ticket.dueDateLocked] then falls back to `id > 0`.
  final bool? locked;

  /// 0..1 fraction of the SLA window remaining.
  final double? frac;

  /// Short remaining time ("8h", "2d") or "Overdue".
  final String? label;
  final DateTime? due;

  bool get isOverdue => label?.toLowerCase() == 'overdue';

  factory Sla.fromJson(Map<String, dynamic> j) {
    // The plan sits inline (`id`/`name`) on some builds and nested under
    // `plan`/`sla_plan` on others — and `name` itself sometimes carries the
    // whole `{id, name}` object, which must not be stringified into the UI.
    final nested = planRef(j['plan'] ?? j['sla_plan']);
    final named = planRef(j['name'] ?? j['title']);
    return Sla(
      id:
          J.intOrNull(j['id'] ?? j['sla_id'] ?? j['plan_id']) ??
          named.$1 ??
          nested.$1,
      name: named.$2 ?? nested.$2,
      locked: (j['locked'] ?? j['sla_locked']) == null
          ? null
          : J.boolOr(j['locked'] ?? j['sla_locked']),
      frac: J.doubleOrNull(j['frac']),
      label: J.str(j['label']),
      due: J.dateTime(j['due']),
    );
  }

  /// Reads a plan reference in whatever shape it arrives: an `{id, name}`
  /// object, a bare name, or a bare id. Without this a nested object gets
  /// stringified straight into the UI as `{id: 5, name: Low}`.
  static (int?, String?) planRef(dynamic v) {
    if (v == null) return (null, null);
    if (v is Map) {
      final m = J.map(v);
      return (
        J.intOrNull(m['id'] ?? m['sla_id'] ?? m['plan_id']),
        J.strNonBlank(m['name'] ?? m['title']),
      );
    }
    if (v is num) return (v.toInt(), null);
    final s = J.strNonBlank(v);
    final asId = int.tryParse(s ?? '');
    return asId != null ? (asId, null) : (null, s);
  }
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
    this.id,
    this.parentField,
    this.choicesByParent,
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

  /// The server-side dynamic-field id. A `422` keys custom-field errors by this
  /// id, so we keep it to map those errors back onto the right input.
  final int? id;

  /// Cascading (nested) custom list: the [name] of the parent field whose
  /// selection narrows this field's [choices]. Null when not cascading.
  final String? parentField;

  /// `{ parentChoiceKey: {childKey: childLabel} }` — the child options allowed
  /// for each parent selection. Null when not cascading.
  final Map<String, Map<String, String>>? choicesByParent;

  /// The key the server addresses this field by. osTicket resolves a field's
  /// form name as `name ?: id` (FormField::getFormName), so a custom field with
  /// no variable name configured in admin is addressed by its **id** — sending
  /// it under an empty name silently drops the answer and the create then fails
  /// with "<Label> is a required field". Use this for the answer map and the
  /// `custom_fields` payload.
  String get key {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    return id?.toString() ?? label;
  }

  /// True when this renders as a picker. Keyed off [choices] rather than
  /// `type == 'choices'` because custom lists arrive typed `list-2`, `list-4`,
  /// … — without this they fall through to a free-text input.
  bool get isChoice => choices != null && choices!.isNotEmpty;

  /// The choices valid for [parentValue] on a cascading child field. Returns
  /// the full [choices] when this field doesn't cascade, and an empty map while
  /// its parent is unanswered (nothing is selectable yet).
  Map<String, String> choicesFor(dynamic parentValue) {
    final all = choices ?? const <String, String>{};
    final byParent = choicesByParent;
    if (parentField == null || byParent == null) return all;
    if (parentValue == null ||
        (parentValue is String && parentValue.trim().isEmpty) ||
        (parentValue is List && parentValue.isEmpty)) {
      return const {};
    }
    // A multiselect parent contributes the union of each selected key's options.
    final keys = parentValue is List
        ? parentValue.map((e) => e.toString())
        : [parentValue.toString()];
    final out = <String, String>{};
    for (final k in keys) {
      final m = byParent[k];
      if (m != null) out.addAll(m);
    }
    return out;
  }

  factory TicketField.fromJson(Map<String, dynamic> j) {
    Map<String, String>? choices;
    if (j['choices'] is Map) {
      choices = {};
      J.map(j['choices']).forEach((k, v) => choices![k] = J.strOr(v));
    }
    // `choices_by_parent` → { parentKey: {childKey: label} } (cascading lists).
    Map<String, Map<String, String>>? byParent;
    if (j['choices_by_parent'] is Map) {
      final acc = <String, Map<String, String>>{};
      J.map(j['choices_by_parent']).forEach((pk, pv) {
        final inner = <String, String>{};
        if (pv is Map) J.map(pv).forEach((k, v) => inner[k] = J.strOr(v));
        acc[pk] = inner;
      });
      byParent = acc;
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
      id: J.intOrNull(j['id']),
      parentField: J.str(j['parent_field']),
      choicesByParent: byParent,
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
  const TicketRelations({
    this.parent,
    this.mergeType,
    this.children = const [],
  });

  final RelatedTicket? parent;
  final String? mergeType; // combine | ... | null
  final List<RelatedTicket> children;

  factory TicketRelations.fromJson(Map<String, dynamic> j) => TicketRelations(
    parent: j['parent'] is Map
        ? RelatedTicket.fromJson(J.map(j['parent']))
        : null,
    mergeType: J.str(j['merge_type']),
    children: J.mapList(j['children']).map(RelatedTicket.fromJson).toList(),
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

/// A named option offered by the server for a create-form dropdown
/// (`sources` / `statuses` on `GET /tickets/form`).
class FormOption {
  const FormOption({required this.value, required this.label});
  final String value; // status id (as text) or source value
  final String label;
}

/// The staff "New Ticket" form for a help topic (`GET /tickets/form`).
///
/// This is the schema the web renders once a Help Topic is picked: the topic's
/// custom fields plus its defaults (department / priority / SLA / status /
/// assignee / due date) and the permission-aware Source + Status option lists.
/// Unlike `GET /tickets/{id}/fields` it needs no existing ticket, so a topic
/// with no tickets yet still returns its full form.
class TicketCreateForm {
  const TicketCreateForm({
    this.topicId,
    this.fields = const [],
    this.deptId,
    this.priorityId,
    this.slaId,
    this.statusId,
    this.staffId,
    this.teamId,
    this.duedate,
    this.slaLocked = false,
    this.canSetDuedate = true,
    this.canAssign = true,
    this.sources = const [],
    this.defaultSource,
    this.statuses = const [],
    this.defaultStatusId,
    this.slas = const [],
  });

  final int? topicId;

  /// The topic's custom fields, already in the shape the dynamic-field section
  /// renders. `subject` / `message` / `priority` are excluded by the server —
  /// the screen renders those natively.
  final List<TicketField> fields;

  // --- `defaults` — prefill the built-in pickers -----------------------------
  final int? deptId;
  final int? priorityId;
  final int? slaId;
  final int? statusId;
  final int? staffId;
  final int? teamId;

  /// The SLA-computed due date, when the server supplies one.
  final DateTime? duedate;

  /// True when the SLA plan drives the due date. Then the due date is
  /// read-only and must NOT be sent on create — the server computes it.
  final bool slaLocked;

  /// `!slaLocked` — when true the agent sets the due date and `POST /tickets`
  /// requires it.
  final bool canSetDuedate;

  /// False when this agent may not assign on create (hide the assign rows).
  final bool canAssign;

  final List<FormOption> sources;
  final String? defaultSource;
  final List<FormOption> statuses;
  final int? defaultStatusId;

  /// Selectable SLA plans, when the server publishes them. Empty on backends
  /// that expose no SLA list — the plan is then whatever the help topic sets
  /// and the screen shows it read-only.
  final List<FormOption> slas;

  // This endpoint omits the built-in `subject` and `message` (osTicket labels
  // them "Issue Summary" and "Issue Details") so the client renders them
  // natively. An install that instead publishes its OWN summary/description
  // fields would otherwise be asked for the same thing twice, so expose them
  // here and let the screen render one or the other.
  static final _summaryLike = RegExp(
    r'^(subject|summary|issue[ _-]?summary)$',
    caseSensitive: false,
  );
  static final _detailsLike = RegExp(
    r'^(message|description|details|issue[ _-]?details)$',
    caseSensitive: false,
  );

  TicketField? _match(RegExp re) {
    for (final f in fields) {
      if (re.hasMatch(f.name.trim()) || re.hasMatch(f.label.trim())) return f;
    }
    return null;
  }

  /// The topic's own stand-in for the built-in `subject`, or null when it
  /// relies on the built-in one.
  TicketField? get summaryField => _match(_summaryLike);

  /// The topic's own stand-in for the built-in `message` (the issue body).
  TicketField? get detailsField => _match(_detailsLike);

  /// SLA plans offered by the server, tolerant of where/how they're published:
  /// `slas` or `sla_plans`, either as a bare list or wrapped in `{values: []}`
  /// like `sources`/`statuses`. Returns empty when the backend offers none.
  static List<FormOption> slaOptions(Map<String, dynamic> j) {
    dynamic raw = j['slas'] ?? j['sla_plans'] ?? j['sla'];
    if (raw is Map) raw = raw['values'] ?? raw['items'];
    if (raw is! List) return const [];
    final out = <FormOption>[];
    for (final o in raw) {
      if (o is! Map) continue;
      final m = J.map(o);
      final id = m['id'] ?? m['value'];
      if (id == null) continue;
      out.add(
        FormOption(
          value: '$id',
          label: J.strOr(m['name'] ?? m['label'] ?? m['title'], '#$id'),
        ),
      );
    }
    return out;
  }

  /// `defaults.duedate` arrives in osTicket's staff format — `m/d/y g:i a`
  /// (e.g. "8/19/26 8:14 AM"), already in the agent's timezone — which
  /// `DateTime.parse` cannot read. Parse that shape, falling back to the
  /// ISO handling in [J.dateTime].
  static DateTime? parseStaffDate(dynamic v) {
    final iso = J.dateTime(v);
    if (iso != null) return iso;
    final s = J.str(v)?.trim();
    if (s == null || s.isEmpty) return null;
    final m = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{2,4})(?:\s+(\d{1,2}):(\d{2})\s*([AaPp])\.?[Mm]?\.?)?$',
    ).firstMatch(s);
    if (m == null) return null;
    final yearText = m.group(3)!;
    var year = int.parse(yearText);
    if (year < 100) year += 2000;
    var hour = 0;
    if (m.group(4) != null) {
      hour = int.parse(m.group(4)!) % 12;
      if (m.group(6)!.toLowerCase() == 'p') hour += 12;
    }
    // Which number is the day is an *install setting* in osTicket
    // (`$cfg->getDateFormat()`), so both orders turn up: this install emits
    // `20/08/2026 10:00 AM` (d/m/Y) while osTicket's stock staff format is
    // `8/19/26 8:14 AM` (m/d/y). Read it off the values where they say so,
    // and fall back to the year width, which tracks the two styles. Getting
    // this wrong doesn't fail loudly — `DateTime(2026, 20, 8)` silently rolls
    // over into 2027 — so guard the result instead of trusting it.
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2)!);
    final int day;
    final int month;
    if (a > 12) {
      day = a;
      month = b;
    } else if (b > 12) {
      month = a;
      day = b;
    } else if (yearText.length == 4) {
      day = a;
      month = b;
    } else {
      month = a;
      day = b;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(
      year,
      month,
      day,
      hour,
      m.group(5) == null ? 0 : int.parse(m.group(5)!),
    );
  }

  factory TicketCreateForm.fromJson(Map<String, dynamic> j) {
    final d = J.map(j['defaults']);

    List<FormOption> options(dynamic raw, String valueKey, String labelKey) => [
      for (final o in J.mapList(J.map(raw)['values']))
        FormOption(
          value: J.strOr(o[valueKey]),
          label: J.strOr(o[labelKey], J.strOr(o[valueKey])),
        ),
    ];

    final srcRaw = J.map(j['sources']);
    final stRaw = J.map(j['statuses']);
    // `sla_locked` is authoritative; `can_set_duedate` is its inverse, so
    // derive whichever the payload omits rather than defaulting to a guess.
    final hasLocked = j['sla_locked'] != null;
    final hasCanSet = j['can_set_duedate'] != null;
    final locked = hasLocked
        ? J.boolOr(j['sla_locked'])
        : (hasCanSet ? !J.boolOr(j['can_set_duedate'], true) : false);

    return TicketCreateForm(
      topicId: J.intOrNull(j['topic_id']),
      fields: J.mapList(j['fields']).map(TicketField.fromJson).toList(),
      deptId: J.intOrNull(d['dept_id']),
      priorityId: J.intOrNull(d['priority_id']),
      slaId: J.intOrNull(d['sla_id']),
      statusId: J.intOrNull(d['status_id']),
      staffId: J.intOrNull(d['staff_id']),
      teamId: J.intOrNull(d['team_id']),
      duedate: parseStaffDate(d['duedate']),
      slaLocked: locked,
      canSetDuedate: !locked,
      canAssign: J.boolOr(j['can_assign'], true),
      sources: options(srcRaw, 'value', 'label'),
      defaultSource: J.str(srcRaw['default']),
      statuses: options(stRaw, 'id', 'name'),
      defaultStatusId: J.intOrNull(stRaw['default']),
      slas: slaOptions(j),
    );
  }
}

/// One row of the ticket's "Ticket details" panel: a form field's label, its
/// display value, whether a *required* answer is still missing, and the field
/// definition behind it ([field] is null when the form couldn't be read, so
/// the row can't be edited on its own).
typedef TicketFieldRow = ({
  String label,
  String? value,
  bool missing,
  TicketField? field,
});

/// Merge a ticket's answers with its topic's form definition for display.
///
/// `GET /tickets/{id}` carries only a flat `{label: displayValue}` map, which
/// can't say which answers are required; `GET /tickets/{id}/fields` carries the
/// required flag and the form's own order. With [fields] present the form
/// drives the list (so an unanswered required field still gets a row, marked
/// [TicketFieldRow.missing] - the web draws a warning triangle on those and
/// osTicket refuses to close the ticket until they're filled in). Without it,
/// the flat map stands alone and nothing is marked.
List<TicketFieldRow> ticketFieldRows(
  Map<String, String> customFields,
  List<TicketField> fields,
) {
  if (fields.isEmpty) {
    return [
      for (final e in customFields.entries)
        (label: e.key, value: e.value, missing: false, field: null),
    ];
  }
  final rows = <TicketFieldRow>[];
  for (final f in fields) {
    final value = _nonBlank(customFields[f.label]) ?? _displayValue(f);
    rows.add((
      label: f.label,
      value: value,
      missing: f.required && value == null,
      // Only an editable field opens its own dialog; a read-only one still
      // shows its row.
      field: f.editable ? f : null,
    ));
  }
  return rows;
}

String? _nonBlank(String? s) => (s == null || s.trim().isEmpty) ? null : s;

/// A field's own answer rendered for display: choice keys resolved to their
/// labels, a multiselect joined, a switch as Yes/No.
String? _displayValue(TicketField f) {
  final v = f.value;
  if (v == null) return null;
  if (v is bool) return v ? 'Yes' : 'No';
  if (v is List) {
    final parts = v
        .map((e) => f.choices?[e.toString()] ?? e.toString())
        .where((e) => e.trim().isNotEmpty);
    return parts.isEmpty ? null : parts.join(', ');
  }
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return f.choices?[s] ?? s;
}
