import 'dart:io';
import 'dart:typed_data';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_text.dart';
import '../models/common.dart';
import '../providers.dart';

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

/// Opens [attachment] with the best in-app viewer for its type. All viewers
/// fetch the bytes through the authed API (never handing a signed URL to an
/// external browser, which fails for auth-bound / stale-signed files):
///
///  * image  → fullscreen pinch-to-zoom viewer
///  * pdf    → in-app PDF reader
///  * video  → in-app video player
///  * else   → download the bytes and open with the OS default app
///
/// Set [external] to force a true external-app launch of the signed URL (used
/// by each viewer's "open externally" action).
Future<void> openAttachment(
  Attachment attachment, {
  required BuildContext context,
  bool external = false,
}) async {
  if (external) {
    final url = attachment.downloadUrl ?? attachment.streamUrl;
    if (url != null) await openUrlInApp(url, external: true);
    return;
  }

  final url = attachment.streamUrl ?? attachment.downloadUrl;
  if (url == null) return;

  if (attachment.isImage) {
    await _push(context, UrlImageView(url: url, title: attachment.name));
  } else if (attachment.isPdf) {
    await _push(context, PdfAttachmentView(url: url, title: attachment.name));
  } else if (attachment.isVideo) {
    await _push(context, VideoAttachmentView(url: url, title: attachment.name));
  } else {
    await downloadAndOpen(context, attachment: attachment, url: url);
  }
}

Future<void> _push(BuildContext context, Widget page) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => page));

/// Opens a raw [url] in-app via a Custom Tab / in-app browser view. Used for
/// external links inside message HTML. [external] forces the system browser.
Future<void> openUrlInApp(String url, {bool external = false}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (external) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!ok) await launchUrl(uri, mode: LaunchMode.platformDefault);
  } catch (_) {
    await launchUrl(uri, mode: LaunchMode.platformDefault);
  }
}

// ---------------------------------------------------------------------------
// Download → open with native app (for non-previewable types)
// ---------------------------------------------------------------------------

/// Downloads the file bytes (authed) to a temp file and opens it with the
/// device's default app for that type. Shows progress/errors via snackbars.
Future<void> downloadAndOpen(
  BuildContext context, {
  required Attachment attachment,
  required String url,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final ref = ProviderScope.containerOf(context);
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 30),
      content: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(width: 14),
          Expanded(child: AppText.subText(context, 'Opening ${attachment.name}…')),
        ],
      ),
    ),
  );
  try {
    final bytes = await ref.read(apiClientProvider).getBytes(url);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safeName(attachment.name)}');
    await file.writeAsBytes(bytes, flush: true);
    messenger.hideCurrentSnackBar();
    final result = await OpenFilex.open(
      file.path,
      type: attachment.type,
    );
    if (result.type != ResultType.done) {
      messenger.showSnackBar(
        SnackBar(content: Text('No app found to open ${attachment.name}')),
      );
    }
  } catch (_) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text("Couldn't open ${attachment.name}")),
    );
  }
}

/// Strip path separators / illegal chars so the temp filename is safe.
String _safeName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'file' : cleaned;
}

// ---------------------------------------------------------------------------
// Shared byte loader
// ---------------------------------------------------------------------------

/// Loads authed bytes for a viewer, exposing [bytes]/[error] and a [reload].
mixin _BytesLoader<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Uint8List? bytes;
  Object? error;

  String get sourceUrl;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() => error = null);
    try {
      final data = await ref.read(apiClientProvider).getBytes(sourceUrl);
      if (!mounted) return;
      setState(() => bytes = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e);
    }
  }
}

AppBar _viewerBar(String title, VoidCallback onOpenExternally) => AppBar(
  backgroundColor: Colors.black,
  foregroundColor: Colors.white,
  title: Text(
    title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 15),
  ),
  actions: [
    IconButton(
      tooltip: 'Open externally',
      icon: const Icon(Icons.open_in_new),
      onPressed: onOpenExternally,
    ),
  ],
);

// ---------------------------------------------------------------------------
// Image viewer
// ---------------------------------------------------------------------------

/// Fullscreen, pinch-to-zoom viewer for an image referenced by [url] (an
/// attachment stream URL or an inline `<img src>` tapped in message HTML).
class UrlImageView extends ConsumerStatefulWidget {
  const UrlImageView({super.key, required this.url, this.title});
  final String url;
  final String? title;

  @override
  ConsumerState<UrlImageView> createState() => _UrlImageViewState();
}

class _UrlImageViewState extends ConsumerState<UrlImageView>
    with _BytesLoader {
  @override
  String get sourceUrl => widget.url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _viewerBar(
        widget.title ?? 'Image',
        () => openUrlInApp(widget.url, external: true),
      ),
      body: Center(
        child: error != null
            ? _ViewerError(label: "Couldn't load image", onRetry: reload)
            : bytes == null
            ? const CircularProgressIndicator(color: Colors.white)
            : InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Image.memory(
                  bytes!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      _ViewerError(label: "Couldn't load image", onRetry: reload),
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PDF viewer
// ---------------------------------------------------------------------------

/// In-app PDF reader (scrollable, pinch-to-zoom) rendering bytes from [url].
class PdfAttachmentView extends ConsumerStatefulWidget {
  const PdfAttachmentView({super.key, required this.url, this.title});
  final String url;
  final String? title;

  @override
  ConsumerState<PdfAttachmentView> createState() => _PdfAttachmentViewState();
}

class _PdfAttachmentViewState extends ConsumerState<PdfAttachmentView>
    with _BytesLoader {
  PdfControllerPinch? _controller;

  @override
  String get sourceUrl => widget.url;

  @override
  Future<void> reload() async {
    await super.reload();
    if (bytes != null && mounted) {
      _controller?.dispose();
      _controller = PdfControllerPinch(
        document: PdfDocument.openData(bytes!),
      );
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _viewerBar(
        widget.title ?? 'Document',
        () => openUrlInApp(widget.url, external: true),
      ),
      body: error != null
          ? Center(
              child: _ViewerError(label: "Couldn't load PDF", onRetry: reload),
            )
          : controller == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : PdfViewPinch(controller: controller),
    );
  }
}

// ---------------------------------------------------------------------------
// Video viewer
// ---------------------------------------------------------------------------

/// In-app video player rendering bytes from [url] (downloaded to a temp file,
/// since the player needs a file/URL source).
class VideoAttachmentView extends ConsumerStatefulWidget {
  const VideoAttachmentView({super.key, required this.url, this.title});
  final String url;
  final String? title;

  @override
  ConsumerState<VideoAttachmentView> createState() =>
      _VideoAttachmentViewState();
}

class _VideoAttachmentViewState extends ConsumerState<VideoAttachmentView> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await ref.read(apiClientProvider).getBytes(widget.url);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/video_${widget.url.hashCode}.tmp');
      await file.writeAsBytes(data, flush: true);
      final video = VideoPlayerController.file(file);
      await video.initialize();
      if (!mounted) {
        await video.dispose();
        return;
      }
      setState(() {
        _video = video;
        _chewie = ChewieController(
          videoPlayerController: video,
          autoPlay: true,
          looping: false,
          aspectRatio: video.value.aspectRatio == 0
              ? 16 / 9
              : video.value.aspectRatio,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _viewerBar(
        widget.title ?? 'Video',
        () => openUrlInApp(widget.url, external: true),
      ),
      body: Center(
        child: _error != null
            ? _ViewerError(label: "Couldn't play video", onRetry: _load)
            : _chewie == null
            ? const CircularProgressIndicator(color: Colors.white)
            : Chewie(controller: _chewie!),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared error state
// ---------------------------------------------------------------------------

class _ViewerError extends StatelessWidget {
  const _ViewerError({required this.label, required this.onRetry});
  final String label;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.white54, size: 48),
        const SizedBox(height: 12),
        AppText.subText(context, label, color: Colors.white70),
        const SizedBox(height: 12),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
