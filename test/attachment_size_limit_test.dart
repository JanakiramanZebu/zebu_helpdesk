import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zebu_helpdesk/core/api/api_client.dart';
import 'package:zebu_helpdesk/core/api/api_exception.dart';
import 'package:zebu_helpdesk/core/attachment_limits.dart';
import 'package:zebu_helpdesk/core/auth/token_storage.dart';

/// Attachments are capped at 8 MB per file. The pickers drop an oversize file
/// before its bytes are ever read; `ApiClient.upload` is the backstop that
/// keeps every other path — ticket create, task create, reply, note, canned
/// response, KB article — from spending the user's bandwidth on a file the
/// server would refuse anyway.

/// Secure storage has no platform channel in a unit test.
class _NoTokens extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => null;

  @override
  Future<String?> readRefreshToken() async => null;
}

/// Records whether a request ever reached the wire.
class _SpyAdapter implements HttpClientAdapter {
  bool sent = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent = true;
    return ResponseBody.fromString('{"data":{}}', 200);
  }

  @override
  void close({bool force = false}) {}
}

MultipartFile _fileOf(int bytes) =>
    MultipartFile.fromBytes(Uint8List(bytes), filename: 'big.bin');

void main() {
  test('the ceiling is 8 MB per file', () {
    expect(kMaxAttachmentBytes, 8 * 1024 * 1024);
    expect(exceedsAttachmentLimit(0), isFalse);
    expect(exceedsAttachmentLimit(kMaxAttachmentBytes), isFalse);
    expect(exceedsAttachmentLimit(kMaxAttachmentBytes + 1), isTrue);
  });

  group('rejection message', () {
    test('one file is named, with the size that broke the rule', () {
      final msg = attachmentsTooLargeMessage([
        (name: 'recording.mp4', bytes: 12 * 1024 * 1024),
      ]);
      expect(msg, contains('recording.mp4'));
      expect(msg, contains('12.0 MB'));
      expect(msg, contains('8 MB'));
    });

    test('several files are counted rather than listed', () {
      final msg = attachmentsTooLargeMessage([
        (name: 'a.zip', bytes: 9 * 1024 * 1024),
        (name: 'b.mov', bytes: 40 * 1024 * 1024),
      ]);
      expect(msg, contains('2 files skipped'));
      expect(msg, isNot(contains('a.zip')));
    });
  });

  group('ApiClient.upload backstop', () {
    late _SpyAdapter adapter;
    late ApiClient client;

    setUp(() {
      adapter = _SpyAdapter();
      client = ApiClient(
        tokenStorage: _NoTokens(),
        dio: Dio()..httpClientAdapter = adapter,
      );
    });

    test('an oversize file is refused before the request goes out', () {
      expect(
        () => client.upload(
          '/tickets/1/attachments',
          fields: const {},
          files: {
            'file': [_fileOf(kMaxAttachmentBytes + 1)],
          },
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'attachment_too_large')
              .having((e) => e.statusCode, 'statusCode', 413)
              .having((e) => e.message, 'message', kAttachmentTooLargeError),
        ),
      );
      expect(adapter.sent, isFalse);
    });

    test('one oversize file blocks the whole multi-file post', () {
      expect(
        () => client.upload(
          '/tickets/1/reply',
          fields: const {'body': 'hi'},
          files: {
            'files[]': [_fileOf(1024), _fileOf(kMaxAttachmentBytes + 1)],
          },
        ),
        throwsA(isA<ApiException>()),
      );
      expect(adapter.sent, isFalse);
    });

    test('files within the ceiling still upload', () async {
      await client.upload(
        '/tickets/1/reply',
        fields: const {'body': 'hi'},
        files: {
          'files[]': [_fileOf(1024), _fileOf(kMaxAttachmentBytes)],
        },
      );
      expect(adapter.sent, isTrue);
    });
  });
}
