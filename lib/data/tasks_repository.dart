import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
import '../core/api/api_exception.dart';
import '../core/api/json.dart';
import '../core/api/paginated.dart';
import '../models/common.dart';
import '../models/task.dart';

/// Filter/search/sort parameters for `GET /tasks`.
class TaskQuery {
  const TaskQuery({
    this.view,
    this.deptId,
    this.assigneeId,
    this.teamId,
    this.priorityId,
    this.tagId,
    this.overdue,
    this.dueFrom,
    this.dueTo,
    this.createdFrom,
    this.createdTo,
    this.q,
    this.sort,
    this.order,
    this.page = 1,
    this.limit = 25,
    this.extra = const {},
  });

  final String? view; // open|closed|overdue|mine|created|collaborator|all
  final int? deptId;
  final int? assigneeId;
  final int? teamId;
  final int? priorityId;
  final List<int>? tagId;
  final bool? overdue;
  final String? dueFrom;
  final String? dueTo;
  final String? createdFrom;
  final String? createdTo;
  final String? q;
  final String? sort;
  final String? order;
  final int page;
  final int limit;
  final Map<String, dynamic> extra;

  Map<String, dynamic> toMap() => {
    if (view != null) 'view': view,
    if (deptId != null) 'dept_id': deptId,
    if (assigneeId != null) 'assignee_id': assigneeId,
    if (teamId != null) 'team_id': teamId,
    if (priorityId != null) 'priority_id': priorityId,
    if (tagId != null && tagId!.isNotEmpty) 'tag_id': tagId!.join(','),
    if (overdue == true) 'overdue': 1,
    if (dueFrom != null) 'due_from': dueFrom,
    if (dueTo != null) 'due_to': dueTo,
    if (createdFrom != null) 'created_from': createdFrom,
    if (createdTo != null) 'created_to': createdTo,
    if (q != null && q!.isNotEmpty) 'q': q,
    if (sort != null) 'sort': sort,
    if (order != null) 'order': order,
    'page': page,
    'limit': limit,
    ...extra,
  };

  TaskQuery copyWith({int? page, String? q, String? view, int? limit}) =>
      TaskQuery(
    view: view ?? this.view,
    deptId: deptId,
    assigneeId: assigneeId,
    teamId: teamId,
    priorityId: priorityId,
    tagId: tagId,
    overdue: overdue,
    dueFrom: dueFrom,
    dueTo: dueTo,
    createdFrom: createdFrom,
    createdTo: createdTo,
    q: q ?? this.q,
    sort: sort,
    order: order,
    page: page ?? this.page,
    limit: limit ?? this.limit,
    extra: extra,
  );
}

/// All `/tasks` endpoints.
class TasksRepository {
  TasksRepository(this._api);
  final ApiClient _api;

  Task _task(dynamic body) => Task.fromJson(J.map(J.map(body)['data']));

  Future<Paginated<Task>> list(TaskQuery query) async {
    final body = await _api.get('/tasks', query: query.toMap());
    return Paginated.fromEnvelope(J.map(body), Task.fromJson);
  }

  /// Total number of tasks matching [view] (or a full [query], which lets the
  /// tab badges reflect active filters) — cheap: fetches a single row and reads
  /// the pagination total. Also used for dashboard stat counts.
  Future<int> count({String view = 'open', TaskQuery? query}) async {
    final body = await _api.get(
      '/tasks',
      query: (query ?? TaskQuery(view: view)).copyWith(limit: 1).toMap(),
    );
    return Paginated.fromEnvelope(J.map(body), Task.fromJson).total;
  }

  Future<Task> get(int id) async => _task(await _api.get('/tasks/$id'));

  /// Create a task. The create endpoint accepts a JSON body only — it does not
  /// parse multipart form fields — so the request is ALWAYS sent as JSON.
  /// (Posting it as multipart, which older builds did when an attachment was
  /// present, left every field empty server-side and failed the create with a
  /// spurious "Required" on department/title/description.)
  ///
  /// Any [files] are uploaded in a best-effort follow-up note — which does
  /// accept multipart `files[]` — so attachments stay on the task without a
  /// failed upload ever failing the create itself.
  /// `POST /tasks` reports form-validation failures keyed by osTicket's numeric
  /// **field id**, not by field name: `Form::isValid()` stores
  /// `$this->_errors[$field->get('id')]`, and `TaskInternalForm::buildFields()`
  /// hard-codes those ids (`class.task.php`). So a due date the server refuses
  /// comes back as `{"3": ["Selected date is earlier than permitted (…)"]}`,
  /// which no screen can match against a field name — the error was landing
  /// nowhere and the form looked like it had simply done nothing.
  ///
  /// Only the internal form's ids are fixed; the default form's title and
  /// description are DB-backed and vary per install, so they stay unmapped and
  /// the screen shows them in its banner instead (see [_renameTaskFormErrors]).
  static const _internalFormFields = {
    '1': 'dept_id',
    '3': 'duedate',
    '4': 'priority_id',
    '5': 'parent_id',
  };

  static ApiException _renameTaskFormErrors(ApiException e) {
    if (e.fields.isEmpty) return e;
    final renamed = {
      for (final entry in e.fields.entries)
        _internalFormFields[entry.key] ?? entry.key: entry.value,
    };
    return ApiException(
      statusCode: e.statusCode,
      code: e.code,
      message: e.message,
      fields: renamed,
    );
  }

  /// [parentId] creates the task as a subtask of that task, through the
  /// parent-scoped `POST /tasks/{id}/subtasks` — the same shape as the web's
  /// `#tasks/{id}/subtask/add`, where the parent comes from the URL and every
  /// other field from the body.
  Future<Task> create(
    Map<String, dynamic> payload, {
    int? parentId,
    List<MultipartFile> files = const [],
  }) async {
    final path = parentId == null ? '/tasks' : '/tasks/$parentId/subtasks';
    final Task task;
    try {
      task = _task(await _api.post(path, body: payload));
    } on ApiException catch (e) {
      throw _renameTaskFormErrors(e);
    }
    if (files.isNotEmpty) {
      try {
        await note(task.id, title: 'Attachments', files: files);
      } catch (_) {
        // The task already exists; a hiccup attaching files must not fail it.
      }
    }
    return task;
  }

  // --- Thread / events / attachments ---------------------------------------

  Future<Paginated<ThreadEntry>> thread(
    int id, {
    int page = 1,
    int limit = 25,
  }) async {
    final body = await _api.get(
      '/tasks/$id/thread',
      query: {'page': page, 'limit': limit},
    );
    return Paginated.fromEnvelope(J.map(body), ThreadEntry.fromJson);
  }

  /// Prior versions of an edited thread entry, oldest→newest (the current
  /// version is not included). Empty when the entry was never edited.
  Future<List<ThreadEntryVersion>> threadHistory(int id, int entryId) async {
    final body = await _api.get('/tasks/$id/thread/$entryId/history');
    return J
        .mapList(J.map(body)['data'])
        .map(ThreadEntryVersion.fromJson)
        .toList();
  }

  /// Rewrites a thread entry's body, mirroring the web's pencil action. The
  /// server files the edit as a NEW entry (the old one becomes history), so the
  /// returned entry carries a different id than [entryId].
  Future<ThreadEntry> editThreadEntry(
    int id,
    int entryId, {
    required String body,
    String? title,
  }) async {
    final res = await _api.post(
      '/tasks/$id/thread/$entryId',
      body: {'body': body, if (title != null) 'title': title},
    );
    return ThreadEntry.fromJson(J.map(J.map(res)['data']));
  }

  Future<List<ThreadEvent>> events(int id) async {
    final body = await _api.get('/tasks/$id/events');
    return J.mapList(J.map(body)['data']).map(ThreadEvent.fromJson).toList();
  }

  Future<Paginated<Attachment>> attachments(
    int id, {
    int page = 1,
    int limit = 25,
  }) async {
    final body = await _api.get(
      '/tasks/$id/attachments',
      query: {'page': page, 'limit': limit},
    );
    return Paginated.fromEnvelope(J.map(body), Attachment.fromJson);
  }

  // --- State transitions ----------------------------------------------------

  Future<Task> close(int id) => _task2(id, 'close', {});
  Future<Task> reopen(int id) => _task2(id, 'reopen', {});

  Future<Task> assign(
    int id, {
    int? staffId,
    int? teamId,
    String? comments,
    bool? refer,
  }) => _task2(id, 'assign', {
    if (staffId != null) 'staff_id': staffId,
    if (teamId != null) 'team_id': teamId,
    if (comments != null) 'comments': comments,
    if (refer != null) 'refer': refer,
  });

  Future<Task> transfer(int id, int deptId, {String? comments}) => _task2(
    id,
    'department',
    {'dept_id': deptId, if (comments != null) 'comments': comments},
  );

  Future<Task> edit(
    int id, {
    Map<String, dynamic>? fields,
    int? priorityId,
    int? progress,
    int? parentId,
  }) => _task2(id, 'edit', {
    if (fields != null) 'fields': fields,
    if (priorityId != null) 'priority_id': priorityId,
    if (progress != null) 'progress': progress,
    if (parentId != null) 'parent_id': parentId,
  });

  Future<Task> reply(
    int id, {
    String? body,
    bool? alert,
    List<MultipartFile> files = const [],
  }) async {
    if (files.isEmpty) {
      return _task2(id, 'reply', {
        if (body != null) 'body': body,
        if (alert != null) 'alert': alert,
      });
    }
    return _task(
      await _api.upload(
        '/tasks/$id/reply',
        fields: {
          if (body != null) 'body': body,
          if (alert != null) 'alert': alert ? 1 : 0,
        },
        files: {'files[]': files},
      ),
    );
  }

  Future<Task> note(
    int id, {
    String? body,
    String? title,
    List<MultipartFile> files = const [],
  }) async {
    if (files.isEmpty) {
      return _task2(id, 'note', {
        if (body != null) 'body': body,
        if (title != null) 'title': title,
      });
    }
    return _task(
      await _api.upload(
        '/tasks/$id/note',
        fields: {
          if (body != null) 'body': body,
          if (title != null) 'title': title,
        },
        files: {'files[]': files},
      ),
    );
  }

  Future<Task> _task2(int id, String action, Map<String, dynamic> body) async =>
      _task(await _api.post('/tasks/$id/$action', body: body));

  // --- Collaborators / tags -------------------------------------------------

  Future<List<Collaborator>> collaborators(int id) async {
    final body = await _api.get('/tasks/$id/collaborators');
    return J.mapList(J.map(body)['data']).map(Collaborator.fromJson).toList();
  }

  Future<void> addCollaborator(int id, int userId) =>
      _api.post('/tasks/$id/collaborators', body: {'user_id': userId});

  Future<List<Collaborator>> removeCollaborator(int id, int cid) async {
    final body = await _api.delete('/tasks/$id/collaborators/$cid');
    return J.mapList(J.map(body)['data']).map(Collaborator.fromJson).toList();
  }

  Future<List<Tag>> tags(int id) async {
    final body = await _api.get('/tasks/$id/tags');
    return J.mapList(J.map(body)['data']).map(Tag.fromJson).toList();
  }

  Future<List<Tag>> addTag(int id, {int? tagId, String? name}) async {
    final body = await _api.post(
      '/tasks/$id/tags',
      body: {
        if (tagId != null) 'tag_id': tagId,
        if (name != null) 'name': name,
      },
    );
    return J.mapList(J.map(body)['data']).map(Tag.fromJson).toList();
  }

  Future<List<Tag>> removeTag(int id, int tagId) async {
    final body = await _api.delete('/tasks/$id/tags/$tagId');
    return J.mapList(J.map(body)['data']).map(Tag.fromJson).toList();
  }

  // --- Subtasks -------------------------------------------------------------

  Future<List<Task>> subtasks(int id) async {
    final body = await _api.get('/tasks/$id/subtasks');
    return J.mapList(J.map(body)['data']).map(Task.fromJson).toList();
  }

  // Subtasks are *created* through `POST /tasks` with `parent_id` (see
  // [create]) — the same path the web uses — because osTicket validates a
  // subtask like any other staff-created task (department and due date
  // included). `POST /tasks/{id}/subtasks` carried none of that and always
  // failed; this endpoint stays read-only here.

  // --- Dependencies ---------------------------------------------------------

  Future<List<TaskDependency>> dependencies(int id) async {
    final body = await _api.get('/tasks/$id/dependencies');
    return J.mapList(J.map(body)['data']).map(TaskDependency.fromJson).toList();
  }

  Future<List<TaskDependency>> addDependency(int id, int dependsOnId) async {
    final body = await _api.post(
      '/tasks/$id/dependencies',
      body: {'depends_on_id': dependsOnId},
    );
    return J.mapList(J.map(body)['data']).map(TaskDependency.fromJson).toList();
  }

  Future<List<TaskDependency>> removeDependency(int id, int depId) async {
    final body = await _api.delete('/tasks/$id/dependencies/$depId');
    return J.mapList(J.map(body)['data']).map(TaskDependency.fromJson).toList();
  }
}
