import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/api_exception.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';

/// An error the API answers **outside** its `{"error": {...}}` envelope must
/// still reach the caller in words.
///
/// osTicket's dispatcher answers a route it has no matcher for with a bare
/// `URL not supported` and a 400 (`Dispatcher::resolve()`), and `matches()`
/// rejects a POST against a `url_get` — so an unrouted write looks exactly
/// like this. Collapsing that to "Request failed (400)" is what made a missing
/// `POST /faq` route read as a payload bug.

class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

/// Answers every request with one canned body, status and content type.
class _StubApi implements HttpClientAdapter {
  _StubApi(this.body, {this.status = 400, this.contentType = 'text/plain'});

  final String body;
  final int status;
  final String contentType;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [contentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

ApiClient _client(_StubApi stub) {
  final dio = Dio()..httpClientAdapter = stub;
  return ApiClient(tokenStorage: _NoTokens(), dio: dio);
}

Future<ApiException> _post(_StubApi stub) async {
  try {
    await _client(stub).post('/faq', body: const {'question': 'x'});
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  test('a plain-text dispatcher error keeps its words', () async {
    final e = await _post(_StubApi('URL not supported'));
    expect(e.statusCode, 400);
    expect(e.message, 'URL not supported (400)');
  });

  test('the JSON envelope still wins, fields and all', () async {
    final e = await _post(
      _StubApi(
        '{"error":{"code":"validation","message":"Could not create FAQ '
        'article","fields":{"question":"Question already exists"}}}',
        status: 422,
        contentType: Headers.jsonContentType,
      ),
    );
    expect(e.code, 'validation');
    expect(e.message, 'Could not create FAQ article');
    expect(e.fields, {'question': 'Question already exists'});
  });

  test('an HTML error page is stripped to one line', () async {
    final e = await _post(
      _StubApi(
        '<html>\n<head><title>502 Bad Gateway</title></head>\n'
        '<body>\n<center><h1>502 Bad Gateway</h1></center>\n</body>\n</html>',
        status: 502,
        contentType: 'text/html',
      ),
    );
    expect(e.message, '502 Bad Gateway 502 Bad Gateway (502)');
  });

  test('script and style blocks never reach the message', () async {
    final e = await _post(
      _StubApi(
        '<html><head><style>body{color:#fff;margin:0}</style>'
        '<script>var boom=1;</script></head><body>Access denied</body></html>',
        status: 403,
        contentType: 'text/html',
      ),
    );
    expect(e.message, 'Access denied (403)');
  });

  test('a stack trace is capped rather than dumped whole', () async {
    final e = await _post(
      _StubApi('Fatal error: ${'#0 /var/www/include/class.faq.php(200) ' * 40}'),
      // A PHP fatal comes back as a 500 with the trace in the body.
    );
    expect(e.message.length, lessThan(200));
    expect(e.message, startsWith('Fatal error: #0 /var/www/'));
    expect(e.message, contains('…'));
  });

  test('an empty body falls back to the status', () async {
    final e = await _post(_StubApi(''));
    expect(e.message, 'Request failed (400)');
  });

  test('a bare {"message": ...} body is read too', () async {
    final e = await _post(
      _StubApi(
        '{"message":"Rate limit exceeded"}',
        status: 429,
        contentType: Headers.jsonContentType,
      ),
    );
    expect(e.message, 'Rate limit exceeded (429)');
  });
}
