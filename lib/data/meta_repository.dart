import '../core/api/api_client.dart';
import '../core/api/json.dart';
import '../models/meta.dart';

/// Reference/dropdown lists (`GET /meta/{kind}`). Results are cached in-memory
/// for the session since they rarely change.
class MetaRepository {
  MetaRepository(this._api);
  final ApiClient _api;

  final Map<String, List<MetaItem>> _cache = {};

  Future<List<MetaItem>> get(String kind, {bool refresh = false}) async {
    if (!refresh && _cache.containsKey(kind)) return _cache[kind]!;
    final body = await _api.get('/meta/$kind');
    final items = J
        .mapList(J.map(body)['data'])
        .map(MetaItem.fromJson)
        .toList();
    _cache[kind] = items;
    return items;
  }

  // Convenience accessors.
  Future<List<MetaItem>> statuses() => get(MetaKind.statuses);
  Future<List<MetaItem>> departments() => get(MetaKind.departments);
  Future<List<MetaItem>> teams() => get(MetaKind.teams);
  Future<List<MetaItem>> priorities() => get(MetaKind.priorities);
  Future<List<MetaItem>> agents() => get(MetaKind.agents);
  Future<List<MetaItem>> topics() => get(MetaKind.topics);
  Future<List<MetaItem>> tags() => get(MetaKind.tags);
  Future<List<MetaItem>> taskPriorities() => get(MetaKind.taskPriorities);

  void clearCache() => _cache.clear();
}
