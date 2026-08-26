import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/api_exception.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/tasks_repository.dart';

/// Secure storage has no platform channel in a unit test.
class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

/// Answers every request with one canned enveloped 422.
class _Rejecting implements HttpClientAdapter {
  _Rejecting(this.fields);
  final Map<String, dynamic> fields;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'error': {
        'code': 'validation',
        'message': 'Could not create task',
        'fields': fields,
      },
    }),
    422,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

/// The error `POST /tasks` raises when the server rejects it with [fields].
Future<ApiException> createError(Map<String, dynamic> fields) async {
  final dio = Dio()..httpClientAdapter = _Rejecting(fields);
  final repo = TasksRepository(
    ApiClient(
      tokenStorage: _NoTokens(),
      apiRoot: 'https://example.invalid/api/v2',
      dio: dio,
    ),
  );
  try {
    await repo.create({'title': 'x', 'dept_id': 1, 'description': 'y'});
  } on ApiException catch (e) {
    return e;
  }
  fail('create should have thrown');
}

void main() {
  test('a due date the server refuses lands on the duedate field', () async {
    // osTicket's Form::isValid() keys errors by field id, and TaskInternalForm
    // hard-codes duedate as id 3 — so this arrives as "3", matching no row.
    final e = await createError({
      '3': ['Selected date is earlier than permitted (8/24/26)'],
    });

    expect(e.fields['duedate'], contains('earlier than permitted'));
    expect(
      e.fields.containsKey('3'),
      isFalse,
      reason: 'the numeric id must not survive — no row can match it',
    );
  });

  test('the other internal-form ids map to their field names', () async {
    final e = await createError({
      '1': 'Required',
      '4': 'Bad',
      '5': 'Unknown task',
    });

    expect(e.fields['dept_id'], 'Required');
    expect(e.fields['priority_id'], 'Bad');
    expect(e.fields['parent_id'], 'Unknown task');
  });

  test('errors already keyed by name pass through untouched', () async {
    // The controller's own pre-check reports these by name, not by id.
    final e = await createError({'title': 'Required', 'dept_id': 'Required'});

    expect(e.fields, {'title': 'Required', 'dept_id': 'Required'});
  });

  test('an unmapped id is kept rather than dropped', () async {
    // Title/description sit on the DB-backed form, so their ids vary per
    // install; the create screen shows anything unplaceable in its banner.
    final e = await createError({'27': 'Answer required'});

    expect(e.fields['27'], 'Answer required');
  });
}
