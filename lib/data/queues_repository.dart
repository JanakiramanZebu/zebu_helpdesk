import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../models/saved_queue.dart';

/// Saved queues (`/queues`). Only personal API-authored queues are writable.
class QueuesRepository {
  QueuesRepository(this._api);
  final ApiClient _api;

  SavedQueue _queue(dynamic body) =>
      SavedQueue.fromJson(J.map(J.map(body)['data']));

  /// [type] filters `ticket` or `task`; omit for all.
  Future<List<SavedQueue>> list({String? type}) async {
    final body = await _api.get('/queues', query: {'type': type});
    return J.mapList(J.map(body)['data']).map(SavedQueue.fromJson).toList();
  }

  Future<SavedQueue> get(int id) async => _queue(await _api.get('/queues/$id'));

  Future<SavedQueue> create({
    required String name,
    Map<String, dynamic>? criteria,
    String? sort,
    List<String>? columns,
  }) async => _queue(
    await _api.post(
      '/queues',
      body: {
        'name': name,
        if (criteria != null) 'criteria': criteria,
        if (sort != null) 'sort': sort,
        if (columns != null) 'columns': columns,
      },
    ),
  );

  Future<SavedQueue> update(int id, Map<String, dynamic> changes) async =>
      _queue(await _api.post('/queues/$id', body: changes));

  Future<void> delete(int id) => _api.delete('/queues/$id');
}
