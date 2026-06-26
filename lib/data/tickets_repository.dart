import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/common.dart';
import '../models/ticket.dart';

/// Filter/search/sort parameters shared by `GET /tickets` and `/tickets/export`.
class TicketQuery {
  const TicketQuery({
    this.queue,
    this.view,
    this.statusId,
    this.deptId,
    this.assigneeId,
    this.teamId,
    this.topicId,
    this.priorityId,
    this.tagId,
    this.overdue,
    this.answered,
    this.unassigned,
    this.createdFrom,
    this.createdTo,
    this.q,
    this.sort,
    this.order,
    this.page = 1,
    this.limit = 25,
    this.extra = const {},
  });

  final int? queue;
  final String? view; // open|closed|overdue|answered|mine|unassigned
  final List<int>? statusId;
  final int? deptId;
  final int? assigneeId;
  final int? teamId;
  final int? topicId;
  final int? priorityId;
  final List<int>? tagId;
  final bool? overdue;
  final bool? answered;
  final bool? unassigned;
  final String? createdFrom; // YYYY-MM-DD
  final String? createdTo;
  final String? q;
  final String? sort;
  final String? order;
  final int page;
  final int limit;

  /// Escape hatch for `cf[<id>]` / collaborator filters etc.
  final Map<String, dynamic> extra;

  Map<String, dynamic> toMap() => {
        if (queue != null) 'queue': queue,
        if (view != null) 'view': view,
        if (statusId != null && statusId!.isNotEmpty)
          'status_id': statusId!.join(','),
        if (deptId != null) 'dept_id': deptId,
        if (assigneeId != null) 'assignee_id': assigneeId,
        if (teamId != null) 'team_id': teamId,
        if (topicId != null) 'topic_id': topicId,
        if (priorityId != null) 'priority_id': priorityId,
        if (tagId != null && tagId!.isNotEmpty) 'tag_id': tagId!.join(','),
        if (overdue == true) 'overdue': 1,
        if (answered == true) 'answered': 1,
        if (unassigned == true) 'unassigned': 1,
        if (createdFrom != null) 'created_from': createdFrom,
        if (createdTo != null) 'created_to': createdTo,
        if (q != null && q!.isNotEmpty) 'q': q,
        if (sort != null) 'sort': sort,
        if (order != null) 'order': order,
        'page': page,
        'limit': limit,
        ...extra,
      };

  TicketQuery copyWith({int? page, String? q, String? view}) => TicketQuery(
        queue: queue,
        view: view ?? this.view,
        statusId: statusId,
        deptId: deptId,
        assigneeId: assigneeId,
        teamId: teamId,
        topicId: topicId,
        priorityId: priorityId,
        tagId: tagId,
        overdue: overdue,
        answered: answered,
        unassigned: unassigned,
        createdFrom: createdFrom,
        createdTo: createdTo,
        q: q ?? this.q,
        sort: sort,
        order: order,
        page: page ?? this.page,
        limit: limit,
        extra: extra,
      );
}

/// Queue counters from `GET /tickets/stats`.
class TicketStats {
  const TicketStats({this.open = 0, this.unassigned = 0, this.total = 0});
  final int open;
  final int unassigned;
  final int total;

  factory TicketStats.fromJson(Map<String, dynamic> j) => TicketStats(
        open: J.intOr(j['open']),
        unassigned: J.intOr(j['unassigned']),
        total: J.intOr(j['total']),
      );
}

/// All `/tickets` endpoints.
class TicketsRepository {
  TicketsRepository(this._api);
  final ApiClient _api;

  Ticket _ticket(dynamic body) => Ticket.fromJson(J.map(J.map(body)['data']));

  // --- Lists & stats --------------------------------------------------------

  Future<Paginated<Ticket>> list(TicketQuery query) async {
    final body = await _api.get('/tickets', query: query.toMap());
    return Paginated.fromEnvelope(J.map(body), Ticket.fromJson);
  }

  Future<TicketStats> stats() async {
    final body = await _api.get('/tickets/stats');
    return TicketStats.fromJson(J.map(J.map(body)['data']));
  }

  /// Stream the filtered ticket list as raw CSV bytes (`GET /tickets/export`,
  /// capped at 5000 rows server-side). `page`/`limit` are ignored by the API.
  Future<Uint8List> exportCsv(TicketQuery query) =>
      _api.getBytes('/tickets/export', query: query.toMap());

  Future<Ticket> get(int id) async => _ticket(await _api.get('/tickets/$id'));

  // --- Create / delete ------------------------------------------------------

  Future<Ticket> create(Map<String, dynamic> payload) async =>
      _ticket(await _api.post('/tickets', body: payload));

  Future<void> delete(int id) => _api.delete('/tickets/$id');

  /// Apply one action to up to 200 tickets.
  Future<Map<String, dynamic>> bulk(Map<String, dynamic> payload) async {
    final body = await _api.post('/tickets/bulk', body: payload);
    return J.map(J.map(body)['data']);
  }

  // --- Thread / events / attachments ---------------------------------------

  Future<Paginated<ThreadEntry>> thread(int id,
      {int page = 1, int limit = 25}) async {
    final body = await _api
        .get('/tickets/$id/thread', query: {'page': page, 'limit': limit});
    return Paginated.fromEnvelope(J.map(body), ThreadEntry.fromJson);
  }

  Future<List<ThreadEvent>> events(int id) async {
    final body = await _api.get('/tickets/$id/events');
    return J.mapList(J.map(body)['data']).map(ThreadEvent.fromJson).toList();
  }

  Future<Paginated<Attachment>> attachments(int id,
      {int page = 1, int limit = 25}) async {
    final body = await _api
        .get('/tickets/$id/attachments', query: {'page': page, 'limit': limit});
    return Paginated.fromEnvelope(J.map(body), Attachment.fromJson);
  }

  /// Resolve the signed download URL for one attachment
  /// (`GET /tickets/{id}/attachments/{att_id}/download` → `302`).
  Future<String?> attachmentDownloadUrl(int id, int attId) =>
      _api.redirectLocation('/tickets/$id/attachments/$attId/download');

  Future<Attachment> uploadAttachment(int id, MultipartFile file) async {
    final body = await _api.upload(
      '/tickets/$id/attachments',
      fields: {},
      files: {
        'file': [file]
      },
    );
    return Attachment.fromJson(J.map(J.map(body)['data']));
  }

  // --- Replies / notes ------------------------------------------------------

  Future<Ticket> reply(
    int id, {
    String? body,
    int? statusId,
    bool? alert,
    List<MultipartFile> files = const [],
  }) async {
    if (files.isEmpty) {
      return _ticket(await _api.post('/tickets/$id/reply', body: {
        if (body != null) 'body': body,
        if (statusId != null) 'status_id': statusId,
        if (alert != null) 'alert': alert,
      }));
    }
    return _ticket(await _api.upload(
      '/tickets/$id/reply',
      fields: {
        if (body != null) 'body': body,
        if (statusId != null) 'status_id': statusId,
        if (alert != null) 'alert': alert ? 1 : 0,
      },
      files: {'files[]': files},
    ));
  }

  Future<Ticket> note(
    int id, {
    String? body,
    String? title,
    List<MultipartFile> files = const [],
  }) async {
    if (files.isEmpty) {
      return _ticket(await _api.post('/tickets/$id/note', body: {
        if (body != null) 'body': body,
        if (title != null) 'title': title,
      }));
    }
    return _ticket(await _api.upload(
      '/tickets/$id/note',
      fields: {
        if (body != null) 'body': body,
        if (title != null) 'title': title,
      },
      files: {'files[]': files},
    ));
  }

  // --- State transitions (all return the full ticket) -----------------------

  Future<Ticket> setStatus(int id, int statusId, {String? comments}) =>
      _post(id, 'status', {'status_id': statusId, if (comments != null) 'comments': comments});

  Future<Ticket> assign(int id, {int? staffId, int? teamId, String? comments}) =>
      _post(id, 'assign', {
        if (staffId != null) 'staff_id': staffId,
        if (teamId != null) 'team_id': teamId,
        if (comments != null) 'comments': comments,
      });

  Future<Ticket> claim(int id) => _post(id, 'claim', {});

  Future<Ticket> release(int id) => _post(id, 'release', {});

  Future<Ticket> transfer(int id, int deptId, {String? comments}) =>
      _post(id, 'department',
          {'dept_id': deptId, if (comments != null) 'comments': comments});

  Future<Ticket> setPriority(int id, int priorityId) =>
      _post(id, 'priority', {'priority_id': priorityId});

  Future<Ticket> mark(int id, String state) => _post(id, 'mark', {'state': state});

  Future<Ticket> setOwner(int id, int userId) =>
      _post(id, 'owner', {'user_id': userId});

  Future<Ticket> setTopic(int id, int topicId) =>
      _post(id, 'topic', {'topic_id': topicId});

  Future<Ticket> setDueDate(int id, {String? duedate, int? slaId}) =>
      _post(id, 'duedate', {
        if (duedate != null) 'duedate': duedate,
        if (slaId != null) 'sla_id': slaId,
      });

  Future<Ticket> editFields(int id, Map<String, dynamic> fields) =>
      _post(id, 'edit', {'fields': fields});

  Future<Ticket> _post(int id, String action, Map<String, dynamic> body) async =>
      _ticket(await _api.post('/tickets/$id/$action', body: body));

  // --- Ban email ------------------------------------------------------------

  Future<bool> banEmail(int id) async {
    final body = await _api.post('/tickets/$id/ban-email');
    return J.boolOr(J.map(J.map(body)['data'])['banned']);
  }

  Future<bool> unbanEmail(int id) async {
    final body = await _api.delete('/tickets/$id/ban-email');
    return J.boolOr(J.map(J.map(body)['data'])['banned']);
  }

  // --- Collaborators --------------------------------------------------------

  Future<List<Collaborator>> collaborators(int id) async {
    final body = await _api.get('/tickets/$id/collaborators');
    return J.mapList(J.map(body)['data']).map(Collaborator.fromJson).toList();
  }

  Future<void> addCollaborator(int id, int userId) =>
      _api.post('/tickets/$id/collaborators', body: {'user_id': userId});

  Future<List<Collaborator>> removeCollaborator(int id, int cid) async {
    final body = await _api.delete('/tickets/$id/collaborators/$cid');
    return J.mapList(J.map(body)['data']).map(Collaborator.fromJson).toList();
  }

  // --- Tags -----------------------------------------------------------------

  Future<List<Tag>> tags(int id) async {
    final body = await _api.get('/tickets/$id/tags');
    return J.mapList(J.map(body)['data']).map(Tag.fromJson).toList();
  }

  Future<List<Tag>> addTag(int id, {int? tagId, String? name}) async {
    final body = await _api.post('/tickets/$id/tags', body: {
      if (tagId != null) 'tag_id': tagId,
      if (name != null) 'name': name,
    });
    return J.mapList(J.map(body)['data']).map(Tag.fromJson).toList();
  }

  Future<List<Tag>> removeTag(int id, int tagId) async {
    final body = await _api.delete('/tickets/$id/tags/$tagId');
    return J.mapList(J.map(body)['data']).map(Tag.fromJson).toList();
  }

  // --- Custom fields --------------------------------------------------------

  Future<List<TicketField>> fields(int id) async {
    final body = await _api.get('/tickets/$id/fields');
    return J.mapList(J.map(body)['data']).map(TicketField.fromJson).toList();
  }

  // --- Referrals ------------------------------------------------------------

  Future<List<Referral>> referrals(int id) async {
    final body = await _api.get('/tickets/$id/referrals');
    return J.mapList(J.map(body)['data']).map(Referral.fromJson).toList();
  }

  Future<List<Referral>> addReferral(int id,
      {int? staffId, int? teamId, int? deptId}) async {
    final body = await _api.post('/tickets/$id/referrals', body: {
      if (staffId != null) 'staff_id': staffId,
      if (teamId != null) 'team_id': teamId,
      if (deptId != null) 'dept_id': deptId,
    });
    return J.mapList(J.map(body)['data']).map(Referral.fromJson).toList();
  }

  Future<List<Referral>> removeReferral(int id, int rid) async {
    final body = await _api.delete('/tickets/$id/referrals/$rid');
    return J.mapList(J.map(body)['data']).map(Referral.fromJson).toList();
  }

  // --- Relations / link / merge --------------------------------------------

  Future<TicketRelations> relations(int id) async {
    final body = await _api.get('/tickets/$id/relations');
    return TicketRelations.fromJson(J.map(J.map(body)['data']));
  }

  Future<TicketRelations> link(int id, List<String> ticketNumbers) async {
    final body =
        await _api.post('/tickets/$id/link', body: {'ticket_numbers': ticketNumbers});
    return TicketRelations.fromJson(J.map(J.map(body)['data']));
  }

  Future<TicketRelations> unlink(int id) async {
    final body = await _api.delete('/tickets/$id/link');
    return TicketRelations.fromJson(J.map(J.map(body)['data']));
  }

  Future<TicketRelations> merge(
    int id,
    List<String> ticketNumbers, {
    int combine = 1,
    int childStatusId = 3,
  }) async {
    final body = await _api.post('/tickets/$id/merge', body: {
      'ticket_numbers': ticketNumbers,
      'combine': combine,
      'child_status_id': childStatusId,
    });
    return TicketRelations.fromJson(J.map(J.map(body)['data']));
  }

  Future<TicketRelations> unmerge(int id) async {
    final body = await _api.delete('/tickets/$id/merge');
    return TicketRelations.fromJson(J.map(J.map(body)['data']));
  }
}
