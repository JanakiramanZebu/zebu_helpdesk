import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/format.dart';
import '../core/theme/app_text.dart';
import '../models/common.dart';
import '../providers.dart';
import 'attachment_viewer.dart';

/// A tappable attachment row. Images show an inline thumbnail and open in a
/// fullscreen, pinch-to-zoom in-app viewer; other files (PDF, video, docs) open
/// with the platform's default handler (an in-app browser tab on Android).
class AttachmentTile extends ConsumerWidget {
  const AttachmentTile({super.key, required this.attachment});
  final Attachment attachment;

  IconData get _icon {
    final t = attachment.type ?? '';
    if (t.startsWith('image/')) return Icons.image_outlined;
    if (t.startsWith('video/')) return Icons.videocam_outlined;
    if (t.startsWith('audio/')) return Icons.audiotrack_outlined;
    if (t.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (t.contains('sheet') || t.contains('excel') || t.contains('csv')) {
      return Icons.table_chart_outlined;
    }
    if (t.contains('word') || t.contains('document')) {
      return Icons.description_outlined;
    }
    if (t.contains('zip') || t.contains('compressed')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.attach_file;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isImage = attachment.isImage;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: isImage
          ? _Thumbnail(attachment: attachment, fallbackIcon: _icon)
          : SizedBox(
              width: 40,
              height: 40,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_icon, color: scheme.primary, size: 22),
              ),
            ),
      title: AppText.titleText(
        context,
        attachment.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: attachment.size != null
          ? AppText.subText(
              context,
              Fmt.fileSize(attachment.size),
              color: scheme.onSurfaceVariant,
            )
          : null,
      trailing: Icon(
        isImage ? Icons.zoom_out_map : Icons.open_in_new,
        size: 18,
        color: scheme.onSurfaceVariant,
      ),
      onTap: () => openAttachment(attachment, context: context),
    );
  }
}

/// A small rounded image preview that loads the attachment bytes (auth-bound),
/// falling back to a type icon while loading or on error.
class _Thumbnail extends ConsumerStatefulWidget {
  const _Thumbnail({required this.attachment, required this.fallbackIcon});
  final Attachment attachment;
  final IconData fallbackIcon;

  @override
  ConsumerState<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends ConsumerState<_Thumbnail> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url =
        widget.attachment.streamUrl ?? widget.attachment.downloadUrl;
    if (url == null) {
      setState(() => _failed = true);
      return;
    }
    try {
      final bytes = await ref.read(apiClientProvider).getBytes(url);
      if (!mounted) return;
      setState(() => _bytes = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = _bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 40,
        height: 40,
        child: bytes != null && !_failed
            ? Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholder(scheme),
              )
            : _placeholder(scheme),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) => DecoratedBox(
    decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.10)),
    child: _failed
        ? Icon(widget.fallbackIcon, color: scheme.primary, size: 22)
        : const Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
  );
}
