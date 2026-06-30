import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../models/common.dart';

/// A tappable attachment row that opens the signed download URL externally.
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({super.key, required this.attachment});
  final Attachment attachment;

  IconData get _icon {
    final t = attachment.type ?? '';
    if (t.startsWith('image/')) return Icons.image_outlined;
    if (t.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (t.contains('sheet') || t.contains('excel')) {
      return Icons.table_chart_outlined;
    }
    if (t.contains('word') || t.contains('document')) {
      return Icons.description_outlined;
    }
    return Icons.attach_file;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      leading: Icon(_icon, color: scheme.primary),
      title: Text(
        attachment.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: attachment.size != null
          ? Text(Fmt.fileSize(attachment.size))
          : null,
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () async {
        final url = attachment.downloadUrl ?? attachment.streamUrl;
        if (url == null) return;
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
    );
  }
}
