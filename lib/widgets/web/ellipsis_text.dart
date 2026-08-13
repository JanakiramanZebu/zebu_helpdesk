import 'package:flutter/material.dart';

/// One line of text that ellipsises, and carries the whole string in a tooltip
/// **only when it actually had to**.
///
/// Flutter gives you `TextOverflow.ellipsis` or a `Tooltip`, never "tooltip if
/// truncated" — so this measures the text against the width it was offered and
/// wraps itself only when the two disagree. A tooltip that repeats what is
/// already on screen fires on every hover and teaches you to ignore tooltips.
///
/// Used anywhere a value is out of the user's control and can run long: file
/// names, email addresses, org names.
class ZebuEllipsisText extends StatelessWidget {
  const ZebuEllipsisText(
    this.text, {
    super.key,
    this.style,
    this.tooltip,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;

  /// Shown instead of [text] when truncated — for a row whose full value is
  /// more than the line it is standing in for.
  final String? tooltip;

  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final effective = style ?? DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, box) {
        final line = Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: style,
        );
        if (!box.maxWidth.isFinite) return line;

        final tp = TextPainter(
          text: TextSpan(text: text, style: effective),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout();
        if (tp.width <= box.maxWidth) return line;

        return Tooltip(
          message: tooltip ?? text,
          waitDuration: const Duration(milliseconds: 400),
          child: line,
        );
      },
    );
  }
}
