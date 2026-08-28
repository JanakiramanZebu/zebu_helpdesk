import 'dart:convert';

import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:parchment/codecs.dart';

import '../core/api/api_exception.dart';
import '../core/format.dart';
import '../core/theme/app_text.dart';
import '../models/common.dart';
import 'app_dialog.dart';
import 'app_sheet.dart';
import 'composer_actions.dart';
import 'rich_message_field.dart';
import 'states.dart';
import 'thread_html.dart';

/// Rewrites one thread entry, the mobile twin of the web's pencil action
/// (`include/staff/templates/thread-entry-edit.tmpl.php`). Resolves with the
/// edited body, or null when the agent backs out or changed nothing (the server
/// treats an identical body as a no-op, so there's no point posting it).
///
/// The editor matches the entry's own format the way the web's does: osTicket
/// stores each entry as HTML *or* plain text (`ThreadEntry.format`) and
/// `TEA_EditThreadEntry::updateEntry()` re-encodes whatever is posted back into
/// that original format. Send HTML for a text entry and it is stored escaped —
/// the save "succeeds" and the message turns into visible `<p>` markup. So a
/// text entry gets a plain textarea, exactly as the web template does when
/// `$cfg->isRichTextEnabled() && $entry->format == 'html'` is false.
Future<String?> showEditEntryDialog(
  BuildContext context, {
  required ThreadEntry entry,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _EditEntryDialog(entry: entry),
  );
}

/// `ThreadEntryBody` truncates any body longer than this to just under the
/// database's `max_allowed_packet` and appends " ... (truncated)"
/// (`include/class.thread.php`). Losing the tail silently is worse than being
/// told, so the dialog refuses to post one instead.
const int _maxBodyBytes = 250000;

class _EditEntryDialog extends StatefulWidget {
  const _EditEntryDialog({required this.entry});
  final ThreadEntry entry;

  @override
  State<_EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<_EditEntryDialog> {
  final _rich = FleatherController();
  final _plain = TextEditingController();

  /// True for an `html` entry (the default), false for a `text` one.
  late final bool _isRich;
  late final String _original;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _isRich = (entry.format ?? 'html').toLowerCase() != 'text';
    if (_isRich) {
      insertRichHtml(_rich, entry.bodyHtml ?? entry.body ?? '');
      // Compare against the encoding of what we loaded, not the server's HTML:
      // a round-trip through the editor reformats markup that never changed.
      _original = parchmentHtml.encode(_rich.document);
    } else {
      // `body` is the raw stored text for a text entry; body_html is only the
      // display rendering of it.
      _plain.text = entry.body ?? Fmt.stripHtml(entry.bodyHtml ?? '');
      _original = _plain.text;
    }
  }

  @override
  void dispose() {
    _rich.dispose();
    _plain.dispose();
    super.dispose();
  }

  String get _value =>
      _isRich ? parchmentHtml.encode(_rich.document) : _plain.text;

  bool get _isEmpty => _isRich
      ? _rich.document.toPlainText().trim().isEmpty
      : _plain.text.trim().isEmpty;

  void _save() {
    if (_isEmpty) {
      setState(() => _error = 'Message cannot be empty');
      return;
    }
    final value = _value;
    if (utf8.encode(value).length > _maxBodyBytes) {
      setState(
        () => _error = 'Message is too long to save — keep it under 250 KB',
      );
      return;
    }
    Navigator.pop(context, value == _original ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Edit message',
      actionLabel: 'Save',
      onAction: _save,
      child: _isRich
          ? RichMessageField(
              controller: _rich,
              hintText: 'Message',
              errorText: _error,
              minHeight: 140,
              maxHeight: 280,
            )
          : TextField(
              controller: _plain,
              autofocus: true,
              minLines: 6,
              maxLines: 12,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Message',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
    );
  }
}

/// Prior versions of an edited entry, oldest first — the mobile twin of the
/// web's "View History". [load] fetches them so the sheet owns its own
/// spinner / error / retry.
Future<void> showEntryHistorySheet(
  BuildContext context, {
  required Future<List<ThreadEntryVersion>> Function() load,
}) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => _HistorySheet(load: load),
  );
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.load});
  final Future<List<ThreadEntryVersion>> Function() load;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  List<ThreadEntryVersion>? _versions;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _versions = null;
    });
    try {
      final v = await widget.load();
      if (mounted) setState(() => _versions = v);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final versions = _versions;
    return AppSheet(
      title: 'Edit history',
      scrollable: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: _error != null
            ? ErrorView(error: _error!, onRetry: _load, compact: true)
            : versions == null
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : versions.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: AppText.subText(context, 'No earlier versions'),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: versions.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 24, color: scheme.outlineVariant),
                itemBuilder: (_, i) {
                  final v = versions[i];
                  // The oldest entry in the chain is the message as first
                  // posted; every later one is somebody's edit.
                  final stamp = v.editedAt ?? v.created;
                  final who = v.editedAt != null && v.editor != null
                      ? 'Edited by ${v.editor} · ${Fmt.dateTime(stamp)}'
                      : 'Original · ${Fmt.dateTime(stamp)}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText.captionText(
                        context,
                        who,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 6),
                      ThreadHtml(html: v.bodyHtml ?? v.body ?? ''),
                    ],
                  );
                },
              ),
      ),
    );
  }
}
