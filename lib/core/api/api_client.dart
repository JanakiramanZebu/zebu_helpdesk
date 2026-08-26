import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config.dart';
import '../auth/token_storage.dart';
import 'api_exception.dart';

/// Thin wrapper around Dio that:
///  * targets the single `/scp/api.php` dispatcher,
///  * injects `Authorization: Bearer <access>` on every request,
///  * caps every call with a hard deadline (Dio's timeouts don't cover a
///    server that stalls before it sends any response headers),
///  * transparently refreshes the access token on `401` and retries once,
///  * normalizes every failure into an [ApiException],
///  * unwraps the `{ "data": ... }` success envelope for callers.
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    this.onSessionExpired,
    String? apiRoot,
    Duration? requestDeadline,
    Dio? dio,
    Dio? refreshDio,
    Dio? signedDio,
  }) : _tokens = tokenStorage,
       _requestDeadline = requestDeadline ?? AppConfig.requestDeadline,
       _dio = dio ?? Dio(),
       _refreshDio = refreshDio ?? Dio(),
       _signedDio = signedDio ?? Dio() {
    final base = BaseOptions(
      baseUrl: apiRoot ?? AppConfig.apiRoot,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      responseType: ResponseType.json,
      // We validate statuses ourselves so the interceptor sees 4xx/5xx.
      validateStatus: (_) => true,
      headers: {'Accept': 'application/json'},
    );
    _dio.options = base;
    _refreshDio.options = base.copyWith();
    // The signed-download Dio keeps the timeouts but drops the base URL, the
    // JSON Accept header and the auth interceptor: it only ever fetches an
    // absolute, self-authenticating URL and reads the body as raw bytes.
    _signedDio.options = BaseOptions(
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      validateStatus: (_) => true,
    );

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
  final Dio _signedDio;
  final TokenStorage _tokens;

  /// Cap on a single JSON call, [AppConfig.requestDeadline] unless overridden
  /// (tests shorten it).
  final Duration _requestDeadline;

  /// Invoked when refresh is impossible/failed — the app should sign out.
  final Future<void> Function()? onSessionExpired;

  // --- Public verbs ---------------------------------------------------------

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = true,
  }) => _send(
    (cancel) =>
        _dio.get(path, queryParameters: _clean(query), cancelToken: cancel),
    auth: auth,
  );

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
  }) => _send(
    (cancel) => _dio.post(
      path,
      data: body,
      queryParameters: _clean(query),
      cancelToken: cancel,
    ),
    auth: auth,
  );

  Future<dynamic> put(String path, {Object? body, bool auth = true}) => _send(
    (cancel) => _dio.put(path, data: body, cancelToken: cancel),
    auth: auth,
  );

  Future<dynamic> delete(String path, {Object? body, bool auth = true}) =>
      _send(
        (cancel) => _dio.delete(path, data: body, cancelToken: cancel),
        auth: auth,
      );

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
    // Uploads move real bytes, so they run under the looser transfer
    // deadline rather than the JSON one.
    return _send(
      (cancel) => _dio.post(path, data: form, cancelToken: cancel),
      auth: true,
      deadline: AppConfig.transferDeadline,
    );
  }

  /// Resolve a `302`-redirect endpoint (e.g. attachment `download`) to its
  /// signed target URL **without** following it, so callers can hand the URL to
  /// the browser / share sheet. Returns `null` if no `Location` was returned.
  Future<String?> redirectLocation(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final token = await _tokens.readAccessToken();
    final cancel = CancelToken();
    final res = await _deadline(
      _requestDeadline,
      cancel,
      () => _dio.get(
        path,
        queryParameters: _clean(query),
        cancelToken: cancel,
        options: Options(
          followRedirects: false,
          responseType: ResponseType.plain,
          headers: token != null ? {'Authorization': 'Bearer $token'} : null,
        ),
      ),
    );
    final code = res.statusCode ?? 0;
    if (code >= 300 && code < 400) return res.headers.value('location');
    if (code >= 200 && code < 300) {
      return null; // already the bytes; no redirect
    }
    throw _exceptionFromResponse(res);
  }

  /// Fetch raw bytes (used by `GET /files/{id}` for inline images/previews).
  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? query}) async {
    final token = await _tokens.readAccessToken();
    final cancel = CancelToken();
    final res = await _deadline(
      AppConfig.transferDeadline,
      cancel,
      () => _dio.get<List<int>>(
        path,
        queryParameters: _clean(query),
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.bytes,
          headers: token != null ? {'Authorization': 'Bearer $token'} : null,
        ),
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

  /// Fetch a pre-signed absolute URL as raw bytes — the `GET /reports/download`
  /// route both report-link endpoints hand back.
  ///
  /// Deliberately runs on a bare Dio with no auth interceptor: that route takes
  /// no bearer token or session (the HMAC in the URL *is* the credential), and
  /// the URL's host is chosen by the server's own config, so there is no reason
  /// to send this install's access token to it.
  ///
  /// Failures still come back as the usual `{ "error": … }` envelope, so a
  /// non-2xx body is decoded rather than handed to the caller as bytes.
  Future<Uint8List> getSignedBytes(String url) async {
    final cancel = CancelToken();
    final res = await _deadline(
      AppConfig.transferDeadline,
      cancel,
      () => _signedDio.get<List<int>>(
        url,
        cancelToken: cancel,
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    final code = res.statusCode ?? 0;
    if (code >= 200 && code < 300 && res.data != null) {
      return Uint8List.fromList(res.data!);
    }
    throw _signedException(code, res.data);
  }

  /// Decode the JSON error the download route returns instead of a CSV body.
  ApiException _signedException(int code, List<int>? body) {
    if (body != null && body.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(body, allowMalformed: true));
        if (decoded is Map && decoded['error'] is Map) {
          final err = (decoded['error'] as Map).cast<String, dynamic>();
          return ApiException(
            statusCode: code,
            code: (err['code'] ?? 'server_error').toString(),
            message: (err['message'] ?? 'Download failed').toString(),
          );
        }
      } on FormatException {
        // Not JSON after all; fall through to the generic message.
      }
    }
    return ApiException(
      statusCode: code,
      code: code == 410 ? 'link_expired' : 'server_error',
      message: code == 410
          ? 'This download link has expired. Try the download again.'
          : 'Download failed ($code)',
    );
  }

  // --- Internals ------------------------------------------------------------

  /// Runs [op] under a hard deadline, cancelling the in-flight request when it
  /// fires (so the socket is released) and surfacing a timeout [ApiException].
  ///
  /// Dio's [BaseOptions.receiveTimeout] only measures the pause between two
  /// chunks of a response that has already started, so a backend that holds the
  /// connection open while it works never trips it - the caller just waits, and
  /// the screen sits on its spinner. This is the backstop for that.
  Future<T> _deadline<T>(
    Duration limit,
    CancelToken cancel,
    Future<T> Function() op,
  ) => op().timeout(
    limit,
    onTimeout: () {
      cancel.cancel('deadline');
      throw ApiException(
        statusCode: 0,
        code: 'timeout',
        message: 'The server took too long to respond. Please try again.',
      );
    },
  );

  /// Runs [request], handling status validation + a single 401 refresh+retry.
  /// Each attempt gets its own [CancelToken] and is capped by [deadline]
  /// (defaulting to [AppConfig.requestDeadline]).
  Future<dynamic> _send(
    Future<Response> Function(CancelToken cancel) request, {
    required bool auth,
    Duration? deadline,
    bool isRetry = false,
  }) async {
    final cancel = CancelToken();
    Response res;
    try {
      res = await _deadline(
        deadline ?? _requestDeadline,
        cancel,
        () => request(cancel),
      );
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
        return _send(request, auth: auth, deadline: deadline, isRetry: true);
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
      final cancel = CancelToken();
      final res = await _deadline(
        _requestDeadline,
        cancel,
        () => _refreshDio.post(
          '/auth/refresh',
          data: {'refresh_token': refresh},
          cancelToken: cancel,
        ),
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
    } on ApiException {
      return false; // deadline hit - no usable token came back
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
