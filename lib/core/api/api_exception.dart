import 'package:dio/dio.dart';

/// Parsed representation of the API's error envelope:
/// ```json
/// { "error": { "code": "<slug>", "message": "<msg>", "fields": { "f": "msg" } } }
/// ```
class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.fields = const {},
  });

  /// HTTP status code (0 when there was no response, e.g. a network failure).
  final int statusCode;

  /// Machine-readable slug, e.g. `authentication_required`, `validation`,
  /// `forbidden`, `not_found`, `csrf_failed`.
  final String code;

  /// Human-readable message.
  final String message;

  /// Field-level validation errors (present for `422 validation`).
  final Map<String, String> fields;

  bool get isAuthError =>
      statusCode == 401 ||
      code == 'authentication_required' ||
      code == 'invalid_token';

  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isValidation => statusCode == 422 || code == 'validation';

  /// Best validation message to surface for [field], falling back to [message].
  String fieldOr(String field) => fields[field] ?? message;

  /// Build from a Dio error, decoding the standard `{ "error": {...} }` body.
  factory ApiException.fromDio(DioException e) {
    final response = e.response;
    final status = response?.statusCode ?? 0;
    final data = response?.data;

    if (data is Map && data['error'] is Map) {
      final err = (data['error'] as Map).cast<String, dynamic>();
      final rawFields = err['fields'];
      final fields = <String, String>{};
      if (rawFields is Map) {
        rawFields.forEach((k, v) => fields['$k'] = '$v');
      }
      return ApiException(
        statusCode: status,
        code: (err['code'] ?? 'error').toString(),
        message: (err['message'] ?? _defaultMessage(status)).toString(),
        fields: fields,
      );
    }

    // Non-enveloped / network errors.
    final code = switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => 'timeout',
      DioExceptionType.connectionError => 'network_error',
      DioExceptionType.cancel => 'cancelled',
      _ => status == 0 ? 'network_error' : 'server_error',
    };
    return ApiException(
      statusCode: status,
      code: code,
      message: _defaultMessage(status, code: code, fallback: e.message),
    );
  }

  static String _defaultMessage(int status, {String? code, String? fallback}) {
    if (code == 'timeout') return 'The request timed out. Please try again.';
    if (code == 'network_error') {
      return 'Network error. Check your connection and try again.';
    }
    if (code == 'cancelled') return 'Request cancelled.';
    return switch (status) {
      401 => 'Your session has expired. Please sign in again.',
      403 => 'You do not have permission to do that.',
      404 => 'Not found.',
      409 => 'This action conflicts with the current state.',
      422 => 'Please check the highlighted fields.',
      >= 500 => 'Something went wrong on the server.',
      _ => fallback ?? 'Unexpected error.',
    };
  }

  @override
  String toString() => 'ApiException($statusCode/$code): $message';
}
