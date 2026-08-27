import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';
import 'package:zebu_helpdesk/data/notifications_repository.dart';

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

/// Serves `/notifications/count` from [count] and `/notifications` from
/// [page], recording every path it was asked for.
class _StubApi implements HttpClientAdapter {
  _StubApi({required this.count, this.page});

  final Map<String, dynamic> count;
  final Map<String, dynamic> Function(int page)? page;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    calls.add('${uri.path}?${uri.query}');
    final body = uri.path.endsWith('/notifications/count')
        ? {'data': count}
        : (page?.call(int.parse(uri.queryParameters['page'] ?? '1')) ??
              {
                'data': {'updated': 1},
              });
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

NotificationsRepository _repo(_StubApi stub) => NotificationsRepository(
  ApiClient(
    tokenStorage: _NoTokens(),
    dio: Dio()..httpClientAdapter = stub,
    apiRoot: 'https://example.test/scp/api.php',
  ),
);

void main() {
  // `/notifications/count` used to report unread *rows* while the inbox listed
  // one card per ticket/task, so the app had to page the unread feed and group
  // it just to badge a number. The endpoint counts objects now — the same unit
  // the list paginates in — so the badge is read straight off the payload.
  test('the counts are read straight off the payload, in one call', () async {
    final stub = _StubApi(
      count: {
        'unread': 157,
        'total': 169,
        'by_type': {
          'ticket': {'total': 56, 'unread': 52},
          'task': {'total': 113, 'unread': 105},
        },
      },
    );

    final counts = await _repo(stub).counts();

    expect(counts.unread, 157);
    expect(counts.total, 169);
    expect(counts.unreadOf('ticket'), 52);
    expect(counts.totalOf('ticket'), 56);
    expect(counts.unreadOf('task'), 105);
    expect(counts.totalOf('task'), 113);
    expect(
      stub.calls.length,
      1,
      reason: 'the server groups, so the feed is never scanned to derive a badge',
    );
  });

  test('a missing by_type breakdown reads as zero, not as an error', () async {
    final stub = _StubApi(count: {'unread': 3, 'total': 4});

    final counts = await _repo(stub).counts();

    expect(counts.unread, 3);
    expect(counts.total, 4);
    expect(counts.unreadOf('ticket'), 0);
    expect(counts.totalOf('task'), 0);
  });

  // The list now returns one entry per ticket/task with its events nested. The
  // old flat rows were the *activity* model; parsing must keep them as such and
  // take the card's identity (and its counts) from the wrapper.
  test('a page parses into one card per object, events nested', () async {
    final stub = _StubApi(
      count: const {},
      page: (p) => {
        'data': [
          {
            'type': 'ticket',
            'object_id': 7038,
            'number': '009893',
            'subject': 'apiv2 sysmail 80528fc4',
            'unread_count': 2,
            'total_count': 6,
            'last_activity': '2026-08-27 13:17:41',
            'activities': [
              {
                'id': 2882,
                'event': 'message',
                'title': 'New reply on #009893',
                'label': null,
                'body': 'apiv2 reply e64d1f5b',
                'actor': 'Zebu Admin',
                'created': '2026-08-27 13:17:41',
                'read': false,
              },
            ],
          },
        ],
        'pagination': {'page': p, 'limit': 25, 'total': 169},
      },
    );

    final page = await _repo(stub).list();

    expect(page.total, 169, reason: 'pagination is counted in cards');
    expect(page.items, hasLength(1));

    final g = page.items.single;
    expect(g.type, 'ticket');
    expect(g.objectId, 7038, reason: 'the tap target is object_id');
    expect(g.displayRef, '#009893');
    expect(g.displaySubject, 'apiv2 sysmail 80528fc4');
    expect(g.unreadCount, 2);
    // total_count is the object's real event count, not the windowed payload's.
    expect(g.count, 6);
    expect(g.hasUnread, isTrue);
    expect(g.activities.single.id, 2882);
    expect(g.activities.single.actor, 'Zebu Admin');
    expect(g.activities.single.read, isFalse);
  });

  // `number` and `subject` are null when the object was resolvable at write
  // time but not now; the first activity's title always carries a usable string.
  test('a card with no number or subject falls back to the activity', () async {
    final stub = _StubApi(
      count: const {},
      page: (p) => {
        'data': [
          {
            'type': 'task',
            'object_id': 44,
            'number': null,
            'subject': null,
            'unread_count': 1,
            'total_count': 1,
            'last_activity': '2026-08-27 09:00:00',
            'activities': [
              {
                'id': 9,
                'event': 'assigned',
                'title': 'Task #44 assigned',
                'label': 'Assigned to you',
                'created': '2026-08-27 09:00:00',
                'read': false,
              },
            ],
          },
        ],
        'pagination': {'page': p, 'limit': 25, 'total': 1},
      },
    );

    final g = (await _repo(stub).list()).items.single;

    expect(g.displayRef, '#44');
    expect(g.displaySubject, 'Task #44 assigned');
    expect(g.isTask, isTrue);
  });

  // All three filters narrow groups server-side, so they must reach the query.
  test('type / read / q are sent as query params', () async {
    final stub = _StubApi(
      count: const {},
      page: (p) => {
        'data': const [],
        'pagination': {'page': p, 'limit': 25, 'total': 0},
      },
    );

    await _repo(stub).list(page: 2, limit: 25, type: 'task', read: false, q: 'sso');

    final call = stub.calls.single;
    expect(call, contains('page=2'));
    expect(call, contains('limit=25'));
    expect(call, contains('type=task'));
    expect(call, contains('read=0'));
    expect(call, contains('q=sso'));
  });

  // Tapping a card marks the whole object read in one request — a card with
  // four unread events must not cost four.
  test('read-object posts the object, not each activity', () async {
    final stub = _StubApi(count: const {});
    final api = ApiClient(
      tokenStorage: _NoTokens(),
      dio: Dio()..httpClientAdapter = stub,
      apiRoot: 'https://example.test/scp/api.php',
    );
    await NotificationsRepository(api).readObject('ticket', 7038);

    expect(stub.calls.single, contains('/notifications/read-object'));
  });
}
