import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A card with a 45° two-tone hatch and a dashed border.
///
/// Built for the internal-note row in a ticket thread. Neither piece is
/// available from `BoxDecoration` — Flutter has no repeating-linear-gradient
/// and no dashed `BorderSide` — so both are painted.
///
/// The texture is the point. A note that goes out to a customer by mistake is
/// the worst thing the ticket screen can do, and hatching is the one surface
/// treatment nothing else in the app uses, so it stays recognisable in
/// peripheral vision where a tint or a label would not.
class HatchedCard extends StatelessWidget {
  const HatchedCard({
    super.key,
    required this.child,
    required this.baseColor,
    required this.stripeColor,
    this.borderColor,
    required this.shape,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Widget child;
  final Color baseColor;
  final Color stripeColor;

  /// Null paints no edge at all, leaving the hatch to carry the card on its
  /// own — which it can, being the one texture nothing else in the app uses.
  final Color? borderColor;

  /// The outline. Takes a full [ShapeBorder] rather than a [BorderRadius] so
  /// a note can wear the same speech-bubble tail as a reply — it sits in the
  /// same left/right system and would otherwise be the one row on the desk's
  /// side shaped like a panel.
  final ShapeBorder shape;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _HatchPainter(
      baseColor: baseColor,
      stripeColor: stripeColor,
      borderColor: borderColor,
      shape: shape,
    ),
    // The shape's own dimensions reserve the tail strip, so body copy can't
    // run underneath it.
    child: Padding(padding: padding.add(shape.dimensions), child: child),
  );
}

/// Band thickness and repeat of the hatch, measured perpendicular to the
/// stripes — 8 on, 8 off.
const double _kBand = 8;

/// Dash geometry of the border, in logical pixels along the path.
const double _kDashOn = 5;
const double _kDashOff = 4;

class _HatchPainter extends CustomPainter {
  const _HatchPainter({
    required this.baseColor,
    required this.stripeColor,
    required this.borderColor,
    required this.shape,
  });

  final Color baseColor;
  final Color stripeColor;
  final Color? borderColor;
  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = shape.getOuterPath(Offset.zero & size);

    canvas.save();
    canvas.clipPath(outline);
    canvas.drawRect(Offset.zero & size, Paint()..color = baseColor);

    // Rotate the canvas rather than computing diagonal line endpoints: the
    // bands stay axis-aligned rectangles, so their thickness is exact instead
    // of being a stroke width measured along the wrong axis.
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 4);
    // Long enough to cover the rect's diagonal at any rotation.
    final span = size.width + size.height;
    final stripe = Paint()..color = stripeColor;
    for (var y = -span; y < span; y += _kBand * 2) {
      canvas.drawRect(Rect.fromLTWH(-span, y, span * 2, _kBand), stripe);
    }
    canvas.restore();
    canvas.restore();

    final edge = borderColor;
    if (edge == null) return;

    // Dashed edge, traced along the same outline the hatch was clipped to.
    final path = outline;
    final pen = Paint()
      ..color = edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = math.min(d + _kDashOn, metric.length);
        canvas.drawPath(metric.extractPath(d, end), pen);
        d = end + _kDashOff;
      }
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) =>
      old.baseColor != baseColor ||
      old.stripeColor != stripeColor ||
      old.borderColor != borderColor ||
      old.shape != shape;
}
