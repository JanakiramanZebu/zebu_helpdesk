import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_text.dart';
import '../../../models/common.dart';
import '../../../widgets/attachment_tile.dart';
import '../../../widgets/thread_html.dart';
import '../../../widgets/user_avatar.dart';

/// Renders a single thread entry (message / response / note) as a chat bubble.
class ThreadEntryTile extends StatelessWidget {
  const ThreadEntryTile({super.key, required this.entry});
  final ThreadEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNote = entry.isNote;
    final isResponse = entry.isResponse;

    // Notes = amber; agent responses = primary tint, right-aligned; messages
    // (from requester) = neutral, left-aligned.
    final bg = isNote
        ? const Color(0xFFFFF8E1)
        : isResponse
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final align = isResponse
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    final html = entry.bodyHtml ?? entry.body ?? '';
    final isEmpty = Fmt.stripHtml(html).trim().isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              UserAvatar(name: entry.poster, radius: 11),
              const SizedBox(width: 6),
              AppText.paraText(context, entry.poster, fw: 1),
              const SizedBox(width: 6),
              if (isNote)
                const StatusChipDot(label: 'Note', color: Color(0xFFF9A825)),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.title != null && entry.title!.isNotEmpty) ...[
                  AppText.subText(context, entry.title!, fw: 1),
                  const SizedBox(height: 4),
                ],
                if (isEmpty)
                  AppText.subText(context, '(no content)')
                else
                  ThreadHtml(html: html, textStyle: theme.textTheme.bodyMedium),
                if (entry.attachments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final a in entry.attachments)
                    AttachmentTile(attachment: a),
                ],
              ],
            ),
          ),
          const SizedBox(height: 3),
          AppText.paraText(context, Fmt.ago(entry.created)),
        ],
      ),
    );
  }
}

/// Tiny labeled dot used inline (e.g. "Note").
class StatusChipDot extends StatelessWidget {
  const StatusChipDot({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
