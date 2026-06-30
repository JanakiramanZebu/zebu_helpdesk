import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config.dart';
import '../auth/token_storage.dart';
import 'api_exception.dart';

/// Thin wrapper around Dio that:
///  * targets the single `/scp/api.php` dispatcher,
///  * injects `Authorization: Bearer <access>` on every request,
///  * transparently refreshes the access token on `401` and retries once,
///  * normalizes every failure into an [ApiException],
///  * unwraps the `{ "data": ... }` success envelope for callers.
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    this.onSessionExpired,
    Dio? dio,
    Dio? refreshDio,
  }) : _tokens = tokenStorage,
       _dio = dio ?? Dio(),
       _refreshDio = refreshDio ?? Dio() {
    final base = BaseOptions(
      baseUrl: AppConfig.apiRoot,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      responseType: ResponseType.json,
      // We validate statuses ourselves so the interceptor sees 4xx/5xx.
      validateStatus: (_) => true,
      headers: {'Accept': 'application/json'},
    );
    _dio.options = base;
    _refreshDio.options = base.copyWith();

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _tokens.readAccessToken();
          if (token != null && !options.headers.containsKey('Authorization')) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final Dio _refreshDio;
  final TokenStorage _tokens;

  /// Invoked when refresh is impossible/failed — the app should sign out.
  final Future<void> Function()? onSessionExpired;

  // --- Public verbs ---------------------------------------------------------

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) => _send(() => _dio.get(path, queryParameters: _clean(query)), auth: auth);

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
  }) => _send(
    () => _dio.post(path, data: body, queryParameters: _clean(query)),
    auth: auth,
  );

  Future<dynamic> put(String path, {Object? body, bool auth = true}) =>
      _send(() => _dio.put(path, data: body), auth: auth);

  Future<dynamic> delete(String path, {Object? body, bool auth = true}) =>
      _send(() => _dio.delete(path, data: body), auth: auth);

  /// Multipart upload (attachments). [files] maps the form field name to a
  /// list of [MultipartFile] (use `files[]` for reply/note, `file` for single).
  Future<dynamic> upload(
    String path, {
    required Map<String, dynamic> fields,
    required Map<String, List<MultipartFile>> files,
  }) {
    final form = FormData();
    fields.forEach((k, v) {
      if (v != null) form.fields.add(MapEntry(k, '$v'));
    });
    files.forEach((field, list) {
      for (final f in list) {
        form.files.add(MapEntry(field, f));
      }
    });
    return _send(() => _dio.post(path, data: form), auth: true);
  }

  /// Resolve a `302`-redirect endpoint (e.g. attachment `download`) to its
  /// signed target URL **without** following it, so callers can hand the URL to
  /// the browser / share sheet. Returns `null` if no `Location` was returned.
  Future<String?> redirectLocation(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final token = await _tokens.readAccessToken();
    final res = await _dio.get(
      path,
      queryParameters: _clean(query),
      options: Options(
        followRedirects: false,
        responseType: ResponseType.plain,
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      ),
    );
    final code = res.statusCode ?? 0;
    if (code >= 300 && code < 400) return res.headers.value('location');
    if (code >= 200 && code < 300)
      return null; // already the bytes; no redirect
    throw _exceptionFromResponse(res);
  }

  /// Fetch raw bytes (used by `GET /files/{id}` for inline images/previews).
  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? query}) async {
    final token = await _tokens.readAccessToken();
    final res = await _dio.get<List<int>>(
      path,
      queryParameters: _clean(query),
      options: Options(
        responseType: ResponseType.bytes,
        headers: token != null ? {'Authorization': 'Bearer $token'} : null,
      ),
    );
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300 && res.data != null) {
      return Uint8List.fromList(res.data!);
    }
    throw ApiException(
      statusCode: code,
      code: code == 404 ? 'not_found' : 'server_error',
      message: code == 404 ? 'File not found' : 'Failed to load file',
    );
  }

  // --- Internals ------------------------------------------------------------

  /// Runs [request], handling status validation + a single 401 refresh+retry.
  Future<dynamic> _send(
    Future<Response> Function() request, {
    required bool auth,
    bool isRetry = false,
  }) async {
    Response res;
    try {
      res = await request();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }

    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300) {
      return res.data;
    }

    // Attempt one transparent refresh on auth failure for protected calls.
    if (code == 401 && auth && !isRetry) {
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _send(request, auth: auth, isRetry: true);
      }
      await onSessionExpired?.call();
    }

    throw _exceptionFromResponse(res);
  }

  ApiException _exceptionFromResponse(Response res) {
    final code = res.statusCode ?? 0;
    final data = res.data;
    if (data is Map && data['error'] is Map) {
      final err = (data['error'] as Map).cast<String, dynamic>();
      final fields = <String, String>{};
      if (err['fields'] is Map) {
        (err['fields'] as Map).forEach((k, v) => fields['$k'] = '$v');
      }
      return ApiException(
        statusCode: code,
        code: (err['code'] ?? 'error').toString(),
        message: (err['message'] ?? 'Request failed').toString(),
        fields: fields,
      );
    }
    return ApiException(
      statusCode: code,
      code: code == 401 ? 'authentication_required' : 'server_error',
      message: 'Request failed ($code)',
    );
  }

  bool _refreshing = false;

  /// Mints a new access token from the stored refresh token.
  /// Uses a separate Dio (no auth interceptor) to avoid recursion.
  Future<bool> _tryRefresh() async {
    if (_refreshing) return false; // avoid stampede on parallel 401s
    final refresh = await _tokens.readRefreshToken();
    if (refresh == null) return false;
    _refreshing = true;
    try {
      final res = await _refreshDio.post(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      final code = res.statusCode ?? 0;
      if (code >= 200 && code < 300 && res.data is Map) {
        final data = (res.data as Map)['data'];
        if (data is Map && data['access_token'] is String) {
          await _tokens.saveAccessToken(data['access_token'] as String);
          return true;
        }
      }
      return false;
    } on DioException {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  /// Drop null query values so we never send `?x=null`.
  Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final out = <String, dynamic>{};
    query.forEach((k, v) {
      if (v != null) out[k] = v;
    });
    return out.isEmpty ? null : out;
  }
}
