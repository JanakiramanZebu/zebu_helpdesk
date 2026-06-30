import '../core/api/json.dart';

/// A lightweight `{ id, name }` reference used widely (department, status, etc.).
class NamedRef {
  const NamedRef({required this.id, required this.name});
  final int id;
  final String name;

  factory NamedRef.fromJson(Map<String, dynamic> j) =>
      NamedRef(id: J.intOr(j['id']), name: J.strOr(j['name']));

  /// Some payloads give a bare display string instead of an object.
  static NamedRef? maybe(dynamic v) {
    if (v is Map) return NamedRef.fromJson(v.cast<String, dynamic>());
    return null;
  }
}

/// Status reference that also carries the open/closed `state`.
class StatusRef {
  const StatusRef({required this.id, required this.name, this.state});
  final int id;
  final String name;
  final String? state;

  bool get isOpen => state == null ? true : state == 'open';

  factory StatusRef.fromJson(Map<String, dynamic> j) => StatusRef(
    id: J.intOr(j['id']),
    name: J.strOr(j['name']),
    state: J.str(j['state']),
  );
}

/// An attachment row (tickets/tasks/canned). FAQ uses a smaller shape with no
/// [threadEntryId]/[streamUrl].
class Attachment {
  const Attachment({
    required this.id,
    required this.name,
    this.size,
    this.type,
    this.threadEntryId,
    this.downloadUrl,
    this.streamUrl,
  });

  final int id;
  final String name;
  final int? size;
  final String? type;
  final int? threadEntryId;

  /// Signed absolute `file.php` URL (Host-bound HMAC) for share/open-externally.
  final String? downloadUrl;

  /// Bearer-authed `/scp/api.php/files/<id>` URL for in-app previews.
  final String? streamUrl;

  bool get isImage => (type ?? '').startsWith('image/');

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
    id: J.intOr(j['id']),
    name: J.strOr(j['name'], 'file'),
    size: J.intOrNull(j['size']),
    type: J.str(j['type']),
    threadEntryId: J.intOrNull(j['thread_entry_id']),
    downloadUrl: J.str(j['download_url']),
    streamUrl: J.str(j['stream_url']),
  );
}

/// A thread entry: message (M), response (R), or note (N).
class ThreadEntry {
  const ThreadEntry({
    required this.id,
    required this.type,
    required this.poster,
    this.title,
    this.format,
    this.body,
    this.bodyHtml,
    this.attachments = const [],
    this.created,
  });

  final int id;
  final String type; // M | R | N
  final String poster;
  final String? title;
  final String? format; // html | text
  final String? body;
  final String? bodyHtml;
  final List<Attachment> attachments;
  final DateTime? created;

  bool get isNote => type == 'N';
  bool get isResponse => type == 'R';
  bool get isMessage => type == 'M';

  factory ThreadEntry.fromJson(Map<String, dynamic> j) => ThreadEntry(
    id: J.intOr(j['id']),
    type: J.strOr(j['type'], 'M'),
    poster: J.strOr(j['poster']),
    title: J.str(j['title']),
    format: J.str(j['format']),
    body: J.str(j['body']),
    bodyHtml: J.str(j['body_html']),
    attachments: J.mapList(j['attachments']).map(Attachment.fromJson).toList(),
    created: J.dateTime(j['created']),
  );
}

/// A non-noise thread event (created/assigned/transferred/...).
class ThreadEvent {
  const ThreadEvent({
    required this.id,
    required this.state,
    this.actor,
    this.description,
    this.created,
  });

  final int id;
  final String state;
  final String? actor;
  final String? description;
  final DateTime? created;

  factory ThreadEvent.fromJson(Map<String, dynamic> j) => ThreadEvent(
    id: J.intOr(j['id']),
    state: J.strOr(j['state']),
    actor: J.str(j['actor']),
    description: J.str(j['description']),
    created: J.dateTime(j['created']),
  );
}

/// Internal staff note on a user/org.
class StaffNote {
  const StaffNote({
    required this.id,
    required this.body,
    this.staff,
    this.created,
    this.updated,
  });

  final int id;
  final String body;
  final NamedRef? staff;
  final DateTime? created;
  final DateTime? updated;

  factory StaffNote.fromJson(Map<String, dynamic> j) => StaffNote(
    id: J.intOr(j['id']),
    body: J.strOr(j['body']),
    staff: NamedRef.maybe(j['staff']),
    created: J.dateTime(j['created']),
    updated: J.dateTime(j['updated']),
  );
}

/// A thread collaborator (CC).
class Collaborator {
  const Collaborator({
    required this.id,
    required this.userId,
    required this.name,
    this.email,
    this.active = true,
    this.isCc = true,
  });

  final int id;
  final int userId;
  final String name;
  final String? email;
  final bool active;
  final bool isCc;

  factory Collaborator.fromJson(Map<String, dynamic> j) => Collaborator(
    id: J.intOr(j['id']),
    userId: J.intOr(j['user_id']),
    name: J.strOr(j['name']),
    email: J.str(j['email']),
    active: J.boolOr(j['active'], true),
    isCc: J.boolOr(j['is_cc'], true),
  );
}

/// A tag with a display color.
class Tag {
  const Tag({required this.id, required this.name, this.color = '#666666'});
  final int id;
  final String name;
  final String color;

  factory Tag.fromJson(Map<String, dynamic> j) => Tag(
    id: J.intOr(j['id']),
    name: J.strOr(j['name']),
    color: J.strOr(j['color'], '#666666'),
  );
}
