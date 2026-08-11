import 'package:flutter/material.dart';

/// Speech-bubble outline: a rounded rectangle with a curved tail flicking off
/// one bottom corner.
///
/// A [BorderRadius] cannot express this — it only shortens corners, and the
/// tail extends *beyond* the box. So the outline is a path, and it is a
/// [ShapeBorder] rather than a painter so `ShapeDecoration` handles the fill,
/// and so [dimensions] can reserve the tail's width automatically. Without
/// that reservation, body text would run underneath the tail.
class BubbleShape extends ShapeBorder {
  const BubbleShape({
    required this.tailOnRight,
    this.radius = 14,
    this.tailWidth = 7,
  });

  /// Which bottom corner the tail leaves from — the one nearest the speaker.
  final bool tailOnRight;
  final double radius;
  final double tailWidth;

  /// Reserved on the tail's side so the fill can extend past the content box.
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(
    left: tailOnRight ? 0 : tailWidth,
    right: tailOnRight ? tailWidth : 0,
  );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final p = Path();
    final h = rect.height;
    final r = radius;
    // Body width — the tail lives in the strip beyond it.
    final bw = rect.width - tailWidth;

    p.moveTo(r, 0);
    p.lineTo(bw - r, 0);
    p.arcToPoint(Offset(bw, r), radius: Radius.circular(r));
    p.lineTo(bw, h - r);
    // Sweep out to the tip, then curl back under it onto the bottom edge.
    // Two quadratics rather than one cubic: the concave underside is what
    // makes it read as a tail instead of a bulge.
    p.quadraticBezierTo(bw, h, bw + tailWidth, h);
    p.quadraticBezierTo(bw + 1, h - 3, bw - 8, h);
    p.lineTo(r, h);
    p.arcToPoint(Offset(0, h - r), radius: Radius.circular(r));
    p.lineTo(0, r);
    p.arcToPoint(Offset(r, 0), radius: Radius.circular(r));
    p.close();

    // The path above is drawn tail-right. Mirroring is a transform rather
    // than a second hand-written path, so the two sides can never drift.
    final mirrored = tailOnRight
        ? p
        : p.transform(
            (Matrix4.identity()
                  ..translateByDouble(rect.width, 0, 0, 1)
                  ..scaleByDouble(-1, 1, 1, 1))
                .storage,
          );
    return mirrored.shift(rect.topLeft);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  /// Fill-only shape — the thread's bubbles carry no stroke.
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => BubbleShape(
    tailOnRight: tailOnRight,
    radius: radius * t,
    tailWidth: tailWidth * t,
  );

  @override
  bool operator ==(Object other) =>
      other is BubbleShape &&
      other.tailOnRight == tailOnRight &&
      other.radius == radius &&
      other.tailWidth == tailWidth;

  @override
  int get hashCode => Object.hash(tailOnRight, radius, tailWidth);
}
