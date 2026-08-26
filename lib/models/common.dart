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

  String get _t => (type ?? '').toLowerCase();
  String get _ext {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  bool get isImage =>
      _t.startsWith('image/') ||
      const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic'}.contains(_ext);

  bool get isPdf => _t.contains('pdf') || _ext == 'pdf';

  bool get isVideo =>
      _t.startsWith('video/') ||
      const {'mp4', 'mov', 'm4v', 'webm', '3gp', 'mkv'}.contains(_ext);

  bool get isAudio =>
      _t.startsWith('audio/') ||
      const {'mp3', 'wav', 'm4a', 'aac', 'ogg'}.contains(_ext);

  /// Plain-text / source-code files we can render in an in-app text viewer
  /// instead of handing off to an external app (which may not exist for
  /// `.txt`/`.log`/code files, and would fail to open).
  bool get isText =>
      _t.startsWith('text/') ||
      _t == 'application/json' ||
      _t == 'application/xml' ||
      const {
        'txt', 'log', 'csv', 'tsv', 'json', 'xml', 'md', 'markdown',
        'yaml', 'yml', 'ini', 'conf', 'cfg', 'env', 'properties',
        'css', 'js', 'ts', 'dart', 'py', 'java', 'c', 'cpp', 'cc', 'h',
        'hpp', 'cs', 'go', 'rb', 'php', 'sh', 'bash', 'sql', 'kt', 'kts',
        'swift', 'rs', 'html', 'htm', 'srt', 'vtt',
      }.contains(_ext);

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
    this.edited = false,
    this.editedAt,
    this.editor,
    this.hasHistory = false,
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

  /// This entry is a revision of an earlier one (osTicket's FLAG_EDITED): the
  /// bubble shows an "Edited" marker the way the web does.
  final bool edited;

  /// When the edit was saved, and who saved it (display name).
  final DateTime? editedAt;
  final String? editor;

  /// A prior version exists behind `/thread/{id}/history`.
  final bool hasHistory;

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
    edited: J.boolOr(j['edited']),
    editedAt: J.dateTime(j['edited_at']),
    editor: J.str(j['editor']),
    hasHistory: J.boolOr(j['has_history']),
  );
}

/// One PRIOR version of an edited thread entry
/// (`GET /tickets/{id}/thread/{entryId}/history`), oldest first. The original
/// version carries no [editedAt] — only later revisions do.
class ThreadEntryVersion {
  const ThreadEntryVersion({
    required this.id,
    required this.poster,
    this.body,
    this.bodyHtml,
    this.created,
    this.editedAt,
    this.editor,
  });

  final int id;
  final String poster;
  final String? body;
  final String? bodyHtml;
  final DateTime? created;
  final DateTime? editedAt;
  final String? editor;

  factory ThreadEntryVersion.fromJson(Map<String, dynamic> j) =>
      ThreadEntryVersion(
        id: J.intOr(j['id']),
        poster: J.strOr(j['poster']),
        body: J.str(j['body']),
        bodyHtml: J.str(j['body_html']),
        created: J.dateTime(j['created']),
        editedAt: J.dateTime(j['edited_at']),
        editor: J.str(j['editor']),
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

  /// Activity-timeline order: newest first, so "Created" lands at the bottom.
  ///
  /// The API orders by `timestamp` alone, which says nothing about events that
  /// share a second — "Created" and the assignment written in the same request
  /// can come back either way round. Sorting on (timestamp, id) first restores
  /// true insertion order, since `id` is auto-increment; only then is it safe
  /// to reverse. Events missing a timestamp fall back to id rather than
  /// dragging the rest of the list out of order.
  static List<ThreadEvent> newestFirst(Iterable<ThreadEvent> events) {
    final ordered = [...events]..sort((a, b) {
      final ta = a.created, tb = b.created;
      final byTime = (ta == null || tb == null) ? 0 : ta.compareTo(tb);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return ordered.reversed.toList();
  }
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
///
/// Two payloads land here. A tag *applied* to a ticket/task (and the
/// `/meta/tags` picker list) carries only id/name/color; the catalogue
/// (`GET /tags`, the port of `scp/managetags.php`) adds the management fields
/// below, which keep their defaults everywhere else.
class Tag {
  const Tag({
    required this.id,
    required this.name,
    this.color = '#666666',
    this.isActive = true,
    this.deptId = 0,
    this.objectCount = 0,
    this.createdLabel,
    this.updatedLabel,
  });

  final int id;
  final String name;
  final String color;

  /// A disabled tag still exists and stays on the objects that carry it; it is
  /// just not offered for new tagging.
  final bool isActive;

  /// Department the tag is scoped to; 0 = global (visible to everyone).
  final int deptId;

  /// How many tickets/tasks currently carry the tag — what a destructive
  /// action has to state before it runs.
  final int objectCount;

  /// Timestamps as the catalogue serializes them (the install's display
  /// format, not a parseable timestamp).
  final String? createdLabel;
  final String? updatedLabel;

  bool get isGlobal => deptId == 0;

  factory Tag.fromJson(Map<String, dynamic> j) => Tag(
    id: J.intOr(j['id']),
    name: J.strOr(j['name']),
    color: J.strOr(j['color'], '#666666'),
    // `is_active` on the catalogue; `active` / flag bits on the picker list.
    isActive: J.boolOr(j['is_active'] ?? j['active'], true),
    deptId: J.intOr(j['dept_id']),
    objectCount: J.intOr(j['object_count']),
    createdLabel: J.strNonBlank(j['created']),
    updatedLabel: J.strNonBlank(j['updated']),
  );
}

/// What `DELETE /tags/{id}` reports back: the delete happened, and what the
/// tag had been applied to.
class TagDeleteResult {
  const TagDeleteResult({required this.ok, required this.objectCount});
  final bool ok;
  final int objectCount;

  factory TagDeleteResult.fromJson(Map<String, dynamic> j) => TagDeleteResult(
    ok: J.boolOr(j['ok'], true),
    objectCount: J.intOr(j['object_count']),
  );
}

/// The outcome of `POST /tags/merge`. [into] is the survivor **after** the
/// merge, [merged] the tags it consumed, and [skipped] ids the server ignored
/// rather than merged — so nothing disappears unaccounted for.
class TagMergeResult {
  const TagMergeResult({
    required this.into,
    this.merged = const [],
    this.skipped = const [],
  });

  final Tag into;
  final List<MergedTag> merged;
  final List<int> skipped;

  factory TagMergeResult.fromJson(Map<String, dynamic> j) => TagMergeResult(
    into: Tag.fromJson(J.map(j['into'])),
    merged: J.mapList(j['merged']).map(MergedTag.fromJson).toList(),
    skipped: J.list(j['skipped']).map((e) => J.intOr(e)).toList(),
  );
}

/// One consumed tag, with what it contributed to the survivor.
class MergedTag {
  const MergedTag({
    required this.id,
    required this.name,
    required this.objectsBefore,
  });

  final int id;
  final String name;
  final int objectsBefore;

  factory MergedTag.fromJson(Map<String, dynamic> j) => MergedTag(
    id: J.intOr(j['id']),
    name: J.strOr(j['name']),
    objectsBefore: J.intOr(j['objects_before']),
  );
}
