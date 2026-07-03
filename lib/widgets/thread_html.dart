import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'attachment_viewer.dart';

/// Renders message/note HTML with in-app tap handling: tapping an inline image
/// opens the fullscreen zoom viewer, tapping a link to a PDF/video opens the
/// matching in-app viewer, and any other link opens in an in-app browser tab
/// (Custom Tab on Android) instead of the external browser.
class ThreadHtml extends StatelessWidget {
  const ThreadHtml({super.key, required this.html, this.textStyle});
  final String html;
  final TextStyle? textStyle;

  static String _ext(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
    final dot = path.lastIndexOf('.');
    return dot >= 0 ? path.substring(dot + 1) : '';
  }

  static const _imageExts = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic',
  };
  static const _videoExts = {'mp4', 'mov', 'm4v', 'webm', '3gp', 'mkv'};

  void _openImage(BuildContext context, String url, [String? title]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UrlImageView(url: url, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return HtmlWidget(
      html,
      textStyle: textStyle,
      // Returning true tells the package we handled the tap, so it never falls
      // back to launching the external browser.
      onTapUrl: (url) async {
        if (url.startsWith('#') ||
            url.startsWith('mailto:') ||
            url.startsWith('tel:')) {
          return false; // let the OS handle anchors / mail / phone
        }
        final ext = _ext(url);
        if (_imageExts.contains(ext)) {
          _openImage(context, url);
        } else if (ext == 'pdf') {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PdfAttachmentView(url: url),
            ),
          );
        } else if (_videoExts.contains(ext)) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => VideoAttachmentView(url: url),
            ),
          );
        } else {
          await openUrlInApp(url);
        }
        return true;
      },
      // Tapping an inline <img> opens it fullscreen in-app.
      onTapImage: (image) {
        final src = image.sources.isNotEmpty ? image.sources.first.url : null;
        if (src == null || src.isEmpty) return;
        _openImage(context, src, image.alt);
      },
    );
  }
}
