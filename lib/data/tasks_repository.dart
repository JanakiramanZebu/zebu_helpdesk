import 'package:dio/dio.dart';

import '../core/api/api_client.dart';
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

  /// Total number of tasks matching [view] — cheap (fetches a single row and
  /// reads the pagination total). Used for dashboard stat counts.
  Future<int> count({String view = 'open'}) async {
    final body = await _api.get(
      '/tasks',
      query: TaskQuery(view: view, limit: 1).toMap(),
    );
    return Paginated.fromEnvelope(J.map(body), Task.fromJson).total;
  }

  Future<Task> get(int id) async => _task(await _api.get('/tasks/$id'));

  /// Create a task. When [files] are supplied the request is sent as multipart
  /// (the form fields + `files[]`), otherwise as a plain JSON body.
  Future<Task> create(
    Map<String, dynamic> payload, {
    List<MultipartFile> files = const [],
  }) async {
    if (files.isEmpty) {
      return _task(await _api.post('/tasks', body: payload));
    }
    return _task(
      await _api.upload('/tasks', fields: payload, files: {'files[]': files}),
    );
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

  Future<Task> assign(int id, {int? staffId, int? teamId, String? comments}) =>
      _task2(id, 'assign', {
        if (staffId != null) 'staff_id': staffId,
        if (teamId != null) 'team_id': teamId,
        if (comments != null) 'comments': comments,
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

  Future<Task> createSubtask(int id, Map<String, dynamic> payload) async =>
      _task(await _api.post('/tasks/$id/subtasks', body: payload));

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
