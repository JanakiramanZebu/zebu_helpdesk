import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/api_exception.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';

/// Secure storage has no platform channel in a unit test, so the token reads
/// are stubbed out — the deadline is what's under test, not auth.
class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

/// An adapter that accepts the request and then never answers.
///
/// This is the shape of the failure the deadline exists for: the backend takes
/// the connection and works for minutes before sending any response headers
/// (osTicket re-sanitizing a huge bounce/NDR thread body), so Dio's
/// `receiveTimeout` — a gap-between-chunks timer — never fires and the caller
/// waits forever.
class _StallingAdapter implements HttpClientAdapter {
  final _never = Completer<ResponseBody>();
  bool cancelled = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    cancelFuture?.then((_) => cancelled = true);
    return _never.future;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _StallingAdapter adapter;
  late ApiClient client;

  setUp(() {
    adapter = _StallingAdapter();
    client = ApiClient(
      tokenStorage: _NoTokens(),
      dio: Dio()..httpClientAdapter = adapter,
      requestDeadline: const Duration(milliseconds: 50),
    );
  });

  test('a stalled request fails with a timeout instead of hanging', () async {
    await expectLater(
      client.get('/tickets/1/thread'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'timeout')
            .having((e) => e.isNetworkError, 'isNetworkError', isTrue),
      ),
    );
  });

  test('the deadline cancels the in-flight request', () async {
    await client.get('/tickets/1/thread').catchError((_) => null);
    // The cancellation reaches the adapter on the next microtask.
    await Future<void>.delayed(Duration.zero);
    expect(adapter.cancelled, isTrue);
  });

  test('the deadline covers writes too', () async {
    await expectLater(
      client.post('/tickets/1/note', body: {'body': 'hi'}),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'timeout')),
    );
  });
}
