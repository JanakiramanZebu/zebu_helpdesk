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

  /// Marketing / newsletter emails use fixed-width tables and spacer columns
  /// (e.g. `<table width="600">`, `<td width="400">`) that, inside a phone-width
  /// view, squeeze the real text column down to one word per line. Strip those
  /// fixed sizes and centering so the content reflows to the available width.
  /// Table *structure* is kept, so genuine data tables still render — only the
  /// forced dimensions are removed.
  static final _sizeAttr = RegExp(
    '''\\s(?:width|height)\\s*=\\s*("[^"]*"|'[^']*'|[^\\s>]+)''',
    caseSensitive: false,
  );
  // The lookbehind stops it matching the "height" inside "line-height" /
  // "border-width" etc. — only standalone width/height (and max-/min- variants).
  static final _sizeStyle = RegExp(
    r'(?<![-\w])(?:max-|min-)?(?:width|height)\s*:\s*[^;"'
    "'"
    r']*;?',
    caseSensitive: false,
  );
  static final _alignAttr = RegExp(
    '''\\salign\\s*=\\s*("center"|'center'|center)''',
    caseSensitive: false,
  );

  static String _reflow(String html) => html
      .replaceAll(_sizeAttr, '')
      .replaceAll(_sizeStyle, '')
      .replaceAll(_alignAttr, '');

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
      _reflow(html),
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
