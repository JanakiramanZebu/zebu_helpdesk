import 'package:flutter/material.dart';

/// The selected-row tick, drawn rather than loaded.
///
/// It began as `assets/icon/check.svg`, which was correct and in the bundle —
/// but an asset is only as available as the bundle the running app was started
/// with. Hot reload ships Dart, not assets, so every session that predated the
/// file rendered an empty box where the tick should be, silently, with no
/// error to follow. Three strokes are not worth that failure mode.
///
/// Geometry matches the SVG it replaced (`M5 12.5 L9.5 17 L19 7.5` on a 24
/// grid, round caps) so the mark is the same shape it always was, and it tints
/// exactly rather than through a colour filter.
class ZebuCheckMark extends StatelessWidget {
  const ZebuCheckMark({super.key, this.size = 13, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _CheckPainter(color));
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      // Scales with the glyph, so a bigger tick is a bigger tick and not a
      // hairline stretched across more space.
      ..strokeWidth = 2.6 * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(
      Path()
        ..moveTo(5 * k, 12.5 * k)
        ..lineTo(9.5 * k, 17 * k)
        ..lineTo(19 * k, 7.5 * k),
      pen,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}
