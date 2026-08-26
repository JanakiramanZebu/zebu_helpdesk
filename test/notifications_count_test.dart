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
        : page!(int.parse(uri.queryParameters['page'] ?? '1'));
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

/// One page of the unread feed: [ids] as ticket object ids, one row each.
Map<String, dynamic> _feed(List<int> ids, {required int total, int page = 1}) =>
    {
      'data': [
        for (final id in ids)
          {
            'id': id * 10,
            'type': 'ticket',
            'object_id': id,
            'event': 'message',
            'title': 'Ticket $id',
            'read': false,
          },
      ],
      'pagination': {'page': page, 'limit': 100, 'total': total},
    };

NotificationsRepository _repo(_StubApi stub) => NotificationsRepository(
  ApiClient(
    tokenStorage: _NoTokens(),
    dio: Dio()..httpClientAdapter = stub,
    apiRoot: 'https://example.test/scp/api.php',
  ),
);

void main() {
  // The badge used to show `data.unread` — a count of unread *rows* — while the
  // inbox lists one card per ticket/task, so a ticket with four unread events
  // badged 4 over a single card and never matched the web's `Unread (n)`.
  test('the badge counts unread conversations, not unread rows', () async {
    final stub = _StubApi(
      count: {'unread': 5},
      page: (p) => p == 1
          // Ticket #5 four times, ticket #7 once: 5 rows, 2 conversations.
          ? _feed([5, 5, 5, 5, 7], total: 5)
          : _feed(const [], total: 5, page: p),
    );

    final counts = await _repo(stub).counts();

    expect(counts.rows, 5);
    expect(counts.conversations, 2);
  });

  test('an object-level total in the payload is used as-is', () async {
    final stub = _StubApi(count: {'unread': 5, 'unread_objects': 2});

    final counts = await _repo(stub).counts();

    expect(counts.conversations, 2);
    expect(
      stub.calls.where((c) => !c.contains('/count')),
      isEmpty,
      reason: 'no need to read the feed when the server did the grouping',
    );
  });

  test('nothing unread costs a single call', () async {
    final stub = _StubApi(count: {'unread': 0});

    final counts = await _repo(stub).counts();

    expect(counts.conversations, 0);
    expect(stub.calls.length, 1);
  });

  test('the derivation reads the unread feed only, and is bounded', () async {
    var served = 0;
    final stub = _StubApi(
      count: {'unread': 10000},
      page: (p) {
        served++;
        return _feed(
          [for (var i = 0; i < 100; i++) p * 1000 + i],
          total: 10000,
          page: p,
        );
      },
    );

    final counts = await _repo(stub).counts();

    expect(served, 3, reason: 'the scan stops rather than paging an inbox dry');
    expect(counts.conversations, 300);
    expect(
      stub.calls.where((c) => c.contains('page=')).every(
        (c) => c.contains('read=0'),
      ),
      isTrue,
      reason: 'only unread rows are fetched',
    );
  });
}
