import 'format.dart';

/// Hard per-file ceiling for every attachment the app uploads — ticket and
/// task create forms, thread replies/notes, canned responses and KB articles
/// alike: **8 MB**.
///
/// Enforced at the pick step (oversize files are dropped before their bytes
/// are ever read) and again in `ApiClient.upload` as a backstop, so no code
/// path can push a bigger file at the server.
const int kMaxAttachmentBytes = 8 * 1024 * 1024;

/// The ceiling worded for the UI. Spelled out rather than run through
/// [Fmt.fileSize], which would render it as "8.0 MB".
const String kMaxAttachmentSizeLabel = '8 MB';

/// Hint shown under the attach affordances so the rule is visible before the
/// user picks something too big.
const String kAttachmentSizeHint = 'Max $kMaxAttachmentSizeLabel per file';

/// True when a file of [bytes] is over the limit and must not be attached.
bool exceedsAttachmentLimit(int bytes) => bytes > kMaxAttachmentBytes;

/// Message for the files a pick dropped. Names the file (with its size) when
/// there is only one, counts them otherwise.
String attachmentsTooLargeMessage(List<({String name, int bytes})> rejected) {
  if (rejected.length == 1) {
    final f = rejected.single;
    return '${f.name} is ${Fmt.fileSize(f.bytes)} — attachments must be '
        '$kMaxAttachmentSizeLabel or smaller.';
  }
  return '${rejected.length} files skipped — attachments must be '
      '$kMaxAttachmentSizeLabel or smaller.';
}

/// The upload backstop's message, used when a file slips past the pick step.
const String kAttachmentTooLargeError =
    'Each attachment must be $kMaxAttachmentSizeLabel or smaller.';
